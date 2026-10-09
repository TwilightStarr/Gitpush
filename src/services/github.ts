import { Repo, Branch, GitFile, ActionRun, PushProgress } from '../types';
import { normalizeAndValidateGitPath, findDuplicatePaths } from '../utils/pathValidation';
import { assertValidToken } from '../utils/secureStorage';
import { findSecrets, formatSecretError } from '../utils/secretGuard';

interface GitHubUserResponse {
  login: string;
  name: string;
  avatar_url: string;
}

interface GitHubRepoResponse {
  id: number;
  name: string;
  full_name: string;
  owner?: { login: string };
  private: boolean;
  default_branch?: string;
  description: string | null;
  html_url: string;
  updated_at: string;
}

interface GitHubBranchResponse {
  name: string;
  commit?: { sha: string };
}

interface GitHubWorkflowRunResponse {
  id: number;
  name: string | null;
  status: string;
  conclusion: string | null;
  event: string;
  created_at: string;
  html_url: string;
}

const API_ORIGIN = 'https://api.github.com';
const NAME_RE = /^[A-Za-z0-9_.-]{1,100}$/;

export class GitHubService {
  private token: string;

  constructor(token: string) {
    assertValidToken(token);
    this.token = token;
  }

  private headers() {
    return {
      Authorization: `Bearer ${this.token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Content-Type': 'application/json',
    };
  }

  /**
   * Tüm istekler buradan geçer: yalnızca api.github.com'a gider, çerez göndermez,
   * Referer sızdırmaz ve önbelleğe yazmaz. Token başka bir alan adına gönderilemez.
   */
  private request(url: string, init: RequestInit = {}): Promise<Response> {
    if (!url.startsWith(`${API_ORIGIN}/`)) {
      throw new Error('Güvenlik: yalnızca api.github.com adresine istek gönderilebilir.');
    }
    return fetch(url, {
      ...init,
      credentials: 'omit',
      referrerPolicy: 'no-referrer',
      cache: 'no-store',
    });
  }

  private repoUrl(owner: string, repo: string): string {
    if (!NAME_RE.test(owner) || owner === '.' || owner === '..') {
      throw new Error('Geçersiz depo sahibi adı.');
    }
    if (!NAME_RE.test(repo) || repo === '.' || repo === '..') {
      throw new Error('Geçersiz depo adı.');
    }
    return `${API_ORIGIN}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}`;
  }

  /** Dal adını doğrular ve her segmenti URL-encode eder (yol enjeksiyonunu engeller). */
  private encodeBranch(branch: string): string {
    // eslint-disable-next-line no-control-regex
    const bad = /[\x00-\x20\x7f~^:?*\[\\]/;
    if (
      !branch ||
      branch.length > 250 ||
      bad.test(branch) ||
      branch.includes('..') ||
      branch.includes('@{') ||
      branch.startsWith('/') ||
      branch.endsWith('/') ||
      branch.endsWith('.') ||
      branch.endsWith('.lock') ||
      branch.includes('//')
    ) {
      throw new Error(`Geçersiz dal adı: "${branch}"`);
    }
    return branch.split('/').map(encodeURIComponent).join('/');
  }

  async verifyUser(signal?: AbortSignal): Promise<GitHubUserResponse> {
    const res = await this.request('https://api.github.com/user', {
      headers: this.headers(),
      signal,
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.message || `Kullanıcı doğrulanamadı (${res.status}). Token yetkilerini kontrol edin.`);
    }
    return res.json() as Promise<GitHubUserResponse>;
  }

  async getUserRepos(signal?: AbortSignal): Promise<Repo[]> {
    const res = await this.request('https://api.github.com/user/repos?per_page=100&sort=updated', {
      headers: this.headers(),
      signal,
    });
    if (!res.ok) {
      throw new Error(`Depolar alınamadı: ${res.statusText}`);
    }
    const data = (await res.json()) as GitHubRepoResponse[];
    return data.map((r) => ({
      id: r.id,
      name: r.name,
      fullName: r.full_name,
      owner: r.owner?.login || '',
      isPrivate: r.private,
      defaultBranch: r.default_branch || 'main',
      description: r.description,
      htmlUrl: r.html_url,
      updatedAt: r.updated_at,
    }));
  }

  async getBranches(owner: string, repo: string, signal?: AbortSignal): Promise<Branch[]> {
    const res = await this.request(`${this.repoUrl(owner, repo)}/branches?per_page=100`, {
      headers: this.headers(),
      signal,
    });
    if (!res.ok) {
      throw new Error(`Dallar listelenemedi: ${res.statusText}`);
    }
    const data = (await res.json()) as GitHubBranchResponse[];
    return data.map((b) => ({
      name: b.name,
      sha: b.commit?.sha || '',
    }));
  }

  async createBranch(
    owner: string,
    repo: string,
    newBranchName: string,
    targetSha: string,
    signal?: AbortSignal
  ): Promise<void> {
    this.encodeBranch(newBranchName);
    const res = await this.request(`${this.repoUrl(owner, repo)}/git/refs`, {
      method: 'POST',
      headers: this.headers(),
      signal,
      body: JSON.stringify({
        ref: `refs/heads/${newBranchName}`,
        sha: targetSha,
      }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.message || `Dal oluşturulamadı (${res.status})`);
    }
  }

  async createRepository(
    name: string,
    isPrivate: boolean,
    description?: string,
    signal?: AbortSignal
  ): Promise<Repo> {
    const res = await this.request('https://api.github.com/user/repos', {
      method: 'POST',
      headers: this.headers(),
      signal,
      body: JSON.stringify({
        name,
        private: isPrivate,
        description: description || '',
        auto_init: true,
      }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.message || 'Yeni repo oluşturulamadı.');
    }
    const r = (await res.json()) as GitHubRepoResponse;
    return {
      id: r.id,
      name: r.name,
      fullName: r.full_name,
      owner: r.owner?.login || '',
      isPrivate: r.private,
      defaultBranch: r.default_branch || 'main',
      description: r.description,
      htmlUrl: r.html_url,
      updatedAt: r.updated_at,
    };
  }

  async getWorkflowRuns(owner: string, repo: string, signal?: AbortSignal): Promise<ActionRun[]> {
    const res = await this.request(`${this.repoUrl(owner, repo)}/actions/runs?per_page=30`, {
      headers: this.headers(),
      signal,
    });
    if (!res.ok) {
      throw new Error(`Actions kayıtları alınamadı: ${res.statusText}`);
    }
    const data = (await res.json()) as { workflow_runs?: GitHubWorkflowRunResponse[] };
    const runs = data.workflow_runs || [];
    return runs.map((r) => ({
      id: r.id,
      name: r.name || 'Workflow',
      status: r.status,
      conclusion: r.conclusion,
      event: r.event,
      createdAt: r.created_at,
      htmlUrl: r.html_url,
    }));
  }

  private uint8ToBase64(bytes: Uint8Array): string {
    let binary = '';
    const len = bytes.byteLength;
    for (let i = 0; i < len; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return window.btoa(binary);
  }

  async executeAtomicPush(
    owner: string,
    repo: string,
    branch: string,
    commitMessage: string,
    files: GitFile[],
    onProgress?: (progress: PushProgress) => void,
    signal?: AbortSignal
  ): Promise<{ commitSha: string; commitUrl: string }> {
    if (signal?.aborted) {
      throw new DOMException('İşlem iptal edildi.', 'AbortError');
    }

    if (files.length === 0) {
      throw new Error('Yüklenecek dosya bulunamadı.');
    }

    // Comprehensive Path Validation & Duplicate Detection
    const validatedFiles: Array<{ path: string; file: GitFile }> = [];
    const rawPaths: string[] = [];

    for (const f of files) {
      const v = normalizeAndValidateGitPath(f.path);
      if (!v.isValid) {
        throw new Error(`Geçersiz dosya yolu ("${f.path}"): ${v.error}`);
      }
      rawPaths.push(v.normalizedPath);
      validatedFiles.push({ path: v.normalizedPath, file: f });
    }

    const duplicates = findDuplicatePaths(rawPaths);
    if (duplicates.length > 0) {
      throw new Error(`Çakışan mükerrer dosya yolu tespit edildi: ${duplicates.join(', ')}`);
    }

    // Gizli bilgi (token, .env, özel anahtar vb.) sızıntısına karşı son savunma hattı
    const secretFindings = findSecrets(validatedFiles);
    if (secretFindings.length > 0) {
      throw new Error(formatSecretError(secretFindings));
    }

    // Dal adı erken doğrulanır (URL'ye eklenmeden önce)
    this.encodeBranch(branch);

    onProgress?.({
      progress: 0.05,
      message: 'Dal bilgisi ve önceki commit kontrol ediliyor...',
      step: 'init',
    });

    // 1. Check existing branch ref
    const refRes = await this.request(
      `${this.repoUrl(owner, repo)}/git/refs/heads/${this.encodeBranch(branch)}`,
      { headers: this.headers(), signal }
    );

    let latestCommitSha: string | null = null;
    let baseTreeSha: string | null = null;
    let isInitialCommit = false;

    if (refRes.status === 200) {
      const refData = await refRes.json();
      latestCommitSha = refData.object.sha;

      const commitRes = await this.request(
        `${this.repoUrl(owner, repo)}/git/commits/${latestCommitSha}`,
        { headers: this.headers(), signal }
      );
      if (commitRes.ok) {
        const commitData = await commitRes.json();
        baseTreeSha = commitData.tree.sha;
      }
    } else if (refRes.status === 404) {
      // Empty / non-initialized repo
      isInitialCommit = true;
    } else {
      throw new Error(`Dal referansı sorgulanamadı (${refRes.status})`);
    }

    // 2. Upload blobs for each file
    const treeEntries: Array<{ path: string; mode: string; type: string; sha: string }> = [];
    const totalFiles = validatedFiles.length;

    for (let i = 0; i < totalFiles; i++) {
      if (signal?.aborted) {
        throw new DOMException('İşlem kullanıcı tarafından iptal edildi.', 'AbortError');
      }

      const item = validatedFiles[i];
      const prog = 0.1 + (i / totalFiles) * 0.65;
      onProgress?.({
        progress: prog,
        message: `Blob oluşturuluyor: ${item.file.name} (${i + 1}/${totalFiles})`,
        step: 'blobs',
      });

      const base64Content = this.uint8ToBase64(item.file.content);
      const blobRes = await this.request(`${this.repoUrl(owner, repo)}/git/blobs`, {
        method: 'POST',
        headers: this.headers(),
        signal,
        body: JSON.stringify({
          content: base64Content,
          encoding: 'base64',
        }),
      });

      if (!blobRes.ok) {
        const err = await blobRes.json().catch(() => ({}));
        throw new Error(`Blob yükleme hatası (${item.path}): ${err.message || blobRes.statusText}`);
      }

      const blobData = await blobRes.json();
      treeEntries.push({
        path: item.path,
        mode: '100644',
        type: 'blob',
        sha: blobData.sha,
      });
    }

    if (signal?.aborted) {
      throw new DOMException('İşlem kullanıcı tarafından iptal edildi.', 'AbortError');
    }

    // 3. Create Git Tree
    onProgress?.({
      progress: 0.8,
      message: 'Git ağacı (Tree) derleniyor...',
      step: 'tree',
    });

    const treeBody: Record<string, any> = { tree: treeEntries };
    if (baseTreeSha) {
      treeBody.base_tree = baseTreeSha;
    }

    const treeRes = await this.request(`${this.repoUrl(owner, repo)}/git/trees`, {
      method: 'POST',
      headers: this.headers(),
      signal,
      body: JSON.stringify(treeBody),
    });

    if (!treeRes.ok) {
      const err = await treeRes.json().catch(() => ({}));
      throw new Error(`Git tree oluşturulamadı: ${err.message || treeRes.statusText}`);
    }

    const treeData = await treeRes.json();
    const newTreeSha = treeData.sha;

    if (signal?.aborted) {
      throw new DOMException('İşlem kullanıcı tarafından iptal edildi.', 'AbortError');
    }

    // 4. Create Commit
    onProgress?.({
      progress: 0.9,
      message: 'Commit oluşturuluyor...',
      step: 'commit',
    });

    const commitBody: Record<string, any> = {
      message: commitMessage,
      tree: newTreeSha,
      parents: isInitialCommit || !latestCommitSha ? [] : [latestCommitSha],
    };

    const newCommitRes = await this.request(`${this.repoUrl(owner, repo)}/git/commits`, {
      method: 'POST',
      headers: this.headers(),
      signal,
      body: JSON.stringify(commitBody),
    });

    if (!newCommitRes.ok) {
      const err = await newCommitRes.json().catch(() => ({}));
      throw new Error(`Commit oluşturulamadı: ${err.message || newCommitRes.statusText}`);
    }

    const newCommitData = await newCommitRes.json();
    const newCommitSha = newCommitData.sha;

    if (signal?.aborted) {
      throw new DOMException('İşlem kullanıcı tarafından iptal edildi.', 'AbortError');
    }

    // 5. Update or Create Branch Ref
    onProgress?.({
      progress: 0.96,
      message: 'Dal referansı güncelleniyor (Push)...',
      step: 'ref',
    });

    if (isInitialCommit) {
      // POST /git/refs for initial commit
      const createRefRes = await this.request(`${this.repoUrl(owner, repo)}/git/refs`, {
        method: 'POST',
        headers: this.headers(),
        signal,
        body: JSON.stringify({
          ref: `refs/heads/${branch}`,
          sha: newCommitSha,
        }),
      });

      if (!createRefRes.ok) {
        const err = await createRefRes.json().catch(() => ({}));
        throw new Error(`Dal referansı oluşturulamadı: ${err.message || createRefRes.statusText}`);
      }
    } else {
      // PATCH existing branch
      const updateRefRes = await this.request(
        `${this.repoUrl(owner, repo)}/git/refs/heads/${this.encodeBranch(branch)}`,
        {
          method: 'PATCH',
          headers: this.headers(),
          signal,
          body: JSON.stringify({
            sha: newCommitSha,
            force: false,
          }),
        }
      );

      if (!updateRefRes.ok) {
        const err = await updateRefRes.json().catch(() => ({}));
        throw new Error(`Dal güncellenemedi: ${err.message || updateRefRes.statusText}`);
      }
    }

    onProgress?.({
      progress: 1.0,
      message: 'İşlem başarıyla tamamlandı!',
      step: 'done',
    });

    return {
      commitSha: newCommitSha,
      commitUrl: `https://github.com/${owner}/${repo}/commit/${newCommitSha}`,
    };
  }
}
