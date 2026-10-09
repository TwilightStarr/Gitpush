import JSZip from 'jszip';
import { GitFile } from '../types';
import { normalizeAndValidateGitPath } from '../utils/pathValidation';

interface GitIgnoreRule {
  isNegation: boolean;
  regex: RegExp;
  raw: string;
}

export class ZipService {
  static async extractZip(file: File | ArrayBuffer): Promise<GitFile[]> {
    const zip = await JSZip.loadAsync(file);
    const rawFiles: Array<{ path: string; zipObject: JSZip.JSZipObject }> = [];
    let gitIgnoreContent: string | null = null;

    zip.forEach((relativePath, zipObject) => {
      if (zipObject.dir) return;

      let normalizedName = relativePath.replace(/\\/g, '/').replace(/^\/+/, '');

      // Filter system junk and internal git history
      if (
        normalizedName.includes('__MACOSX') ||
        normalizedName.endsWith('.DS_Store') ||
        normalizedName.includes('/.git/') ||
        normalizedName.startsWith('.git/') ||
        normalizedName.endsWith('/Thumbs.db')
      ) {
        return;
      }

      rawFiles.push({ path: normalizedName, zipObject });
    });

    // Check for root .gitignore
    const gitignoreObj = rawFiles.find(
      (f) => f.path === '.gitignore' || f.path.endsWith('/.gitignore')
    );
    if (gitignoreObj) {
      try {
        gitIgnoreContent = await gitignoreObj.zipObject.async('text');
      } catch {
        // ignore
      }
    }

    // Auto-detect common redundant single root directory (e.g. project-master/)
    const commonPrefix = this.detectCommonRoot(rawFiles.map((f) => f.path));
    const ignoreRules = this.compileGitIgnoreRules(gitIgnoreContent);
    const validFiles: GitFile[] = [];

    for (const item of rawFiles) {
      let normalizedPath = item.path;
      if (commonPrefix && normalizedPath.startsWith(commonPrefix)) {
        normalizedPath = normalizedPath.slice(commonPrefix.length);
      }

      // Validate path safety
      const pathCheck = normalizeAndValidateGitPath(normalizedPath);
      if (!pathCheck.isValid) {
        continue;
      }
      normalizedPath = pathCheck.normalizedPath;

      // Ignore rule check
      if (this.isIgnoredByRules(normalizedPath, ignoreRules)) {
        continue;
      }

      const content = await item.zipObject.async('uint8array');
      const name = normalizedPath.split('/').pop() || normalizedPath;
      const isText = this.isTextFile(name);

      validFiles.push({
        path: normalizedPath,
        name,
        content,
        size: content.byteLength,
        isText,
      });
    }

    return validFiles;
  }

  private static detectCommonRoot(paths: string[]): string {
    if (paths.length === 0) return '';
    let firstRoot: string | null = null;

    for (const p of paths) {
      const parts = p.split('/');
      if (parts.length <= 1) {
        // There is at least one root-level file, so no shared parent wrapper folder
        return '';
      }
      const root = parts[0];
      if (firstRoot === null) {
        firstRoot = root;
      } else if (firstRoot !== root) {
        return '';
      }
    }

    return firstRoot ? `${firstRoot}/` : '';
  }

  private static compileGitIgnoreRules(content: string | null): GitIgnoreRule[] {
    const defaultPatterns = [
      'node_modules/**',
      '.dart_tool/**',
      'build/**',
      '.idea/**',
      '.vscode/**',
      '.gradle/**',
      '*.log',
      '*.tmp',
    ];

    const lines: string[] = [];
    if (content) {
      lines.push(...content.split(/\r?\n/));
    }
    lines.push(...defaultPatterns);

    const rules: GitIgnoreRule[] = [];

    for (let line of lines) {
      line = line.trim();
      if (!line || line.startsWith('#')) continue;

      let isNegation = false;
      if (line.startsWith('!')) {
        isNegation = true;
        line = line.slice(1).trim();
      }

      if (!line) continue;

      // Convert gitignore glob pattern to RegExp
      const regex = this.globToRegex(line);
      rules.push({ isNegation, regex, raw: line });
    }

    return rules;
  }

  private static globToRegex(pattern: string): RegExp {
    let p = pattern.replace(/\\/g, '/');

    // If starts with /, match from root
    let matchFromRoot = false;
    if (p.startsWith('/')) {
      matchFromRoot = true;
      p = p.slice(1);
    }

    // Trailing slash matches directories and contents
    const matchDirOnly = p.endsWith('/');
    if (matchDirOnly) {
      p = p.slice(0, -1);
    }

    // Escape regex characters except * and ?
    let regexStr = p
      .replace(/[.+^${}()|[\]\\]/g, '\\$&')
      .replace(/\*\*/g, '§DOUBLESTAR§')
      .replace(/\*/g, '[^/]*')
      .replace(/\?/g, '[^/]')
      .replace(/§DOUBLESTAR§/g, '.*');

    if (matchDirOnly) {
      regexStr = `(?:^|/)${regexStr}(?:/.*)?$`;
    } else if (matchFromRoot) {
      regexStr = `^${regexStr}(?:/.*)?$`;
    } else {
      regexStr = `(?:^|/)${regexStr}(?:/.*)?$`;
    }

    return new RegExp(regexStr);
  }

  private static isIgnoredByRules(path: string, rules: GitIgnoreRule[]): boolean {
    let ignored = false;
    for (const rule of rules) {
      if (rule.regex.test(path)) {
        if (rule.isNegation) {
          ignored = false;
        } else {
          ignored = true;
        }
      }
    }
    return ignored;
  }

  private static isTextFile(fileName: string): boolean {
    const textExtensions = [
      '.dart', '.ts', '.tsx', '.js', '.jsx', '.json', '.yaml', '.yml',
      '.html', '.css', '.md', '.txt', '.env', '.gitignore', '.xml',
      '.gradle', '.properties', '.sh', '.bat', '.c', '.cpp', '.h', '.py',
      '.svg', '.sql', '.toml', '.lock',
    ];
    const lower = fileName.toLowerCase();
    return textExtensions.some((ext) => lower.endsWith(ext));
  }
}
