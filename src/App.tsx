import React, { useState, useEffect, useRef, Suspense } from 'react';
import { Repo, Branch, GitFile, ActiveTab, PushProgress } from './types';
import { GitHubService } from './services/github';
import { Navbar } from './components/Navbar';
import { ZipTransferView } from './components/ZipTransferView';
import { MultiFileView } from './components/MultiFileView';
import { RepoPickerView } from './components/RepoPickerView';
import { ActionsView } from './components/ActionsView';
import { ProgressModal } from './components/ProgressModal';
import { AuthModal } from './components/AuthModal';
import {
  StorageType,
  purgeLegacyPlaintext,
  hasEncryptedToken,
  getEncryptedLoginHint,
  saveEncryptedToken,
  loadEncryptedToken,
  clearEncryptedToken,
} from './utils/secureStorage';
import { ToastProvider, useToast } from './components/Toast';
import { KeyRound, Loader2 } from 'lucide-react';

const DartCodeViewer = React.lazy(() =>
  import('./components/DartCodeViewer').then((mod) => ({ default: mod.DartCodeViewer }))
);

function AppContent() {
  const toast = useToast();

  // Güvenlik: token varsayılan olarak yalnızca bellekte tutulur. Eski sürümlerin
  // düz metin kayıtları (localStorage/sessionStorage) açılışta silinir.
  // İsteğe bağlı kalıcı kayıt yalnızca parola ile ŞİFRELİ olarak yapılır.
  const [authData, setAuthData] = useState<{
    token: string;
    login: string | null;
    storage: StorageType;
  }>(() => {
    purgeLegacyPlaintext();
    return { token: '', login: null, storage: 'memory' };
  });
  const [lockedLogin, setLockedLogin] = useState<string | null>(() =>
    hasEncryptedToken() ? getEncryptedLoginHint() || 'kayıtlı-kullanıcı' : null
  );
  const token = authData.token;
  const userLogin = authData.login;
  const storageType = authData.storage;

  const [activeTab, setActiveTab] = useState<ActiveTab>('zip');

  // Repositories state
  const [repos, setRepos] = useState<Repo[]>([]);
  const [selectedRepo, setSelectedRepo] = useState<Repo | null>(null);
  const [selectedBranch, setSelectedBranch] = useState<string>('main');
  const [branches, setBranches] = useState<Record<string, Branch[]>>({});
  const [loadingBranches, setLoadingBranches] = useState<Record<string, boolean>>({});
  const [isLoadingRepos, setIsLoadingRepos] = useState<boolean>(false);

  // Modals state
  const [isAuthModalOpen, setIsAuthModalOpen] = useState<boolean>(false);
  const [isProgressModalOpen, setIsProgressModalOpen] = useState<boolean>(false);
  const [isUploading, setIsUploading] = useState<boolean>(false);
  const [pushProgress, setPushProgress] = useState<PushProgress>({
    progress: 0,
    message: '',
    step: 'init',
  });
  const [pushResult, setPushResult] = useState<{
    commitSha: string;
    commitUrl: string;
    fileCount: number;
  } | null>(null);
  const [pushError, setPushError] = useState<string | null>(null);

  // AbortController ref for cancelling network requests
  const uploadAbortControllerRef = useRef<AbortController | null>(null);

  // GitHub Service instance
  const githubService = token ? new GitHubService(token) : null;

  // Load repos when token exists
  const loadUserRepos = async (pat: string) => {
    try {
      setIsLoadingRepos(true);
      const service = new GitHubService(pat);
      const userRepos = await service.getUserRepos();
      setRepos(userRepos);
      if (userRepos.length > 0 && !selectedRepo) {
        setSelectedRepo(userRepos[0]);
        setSelectedBranch(userRepos[0].defaultBranch || 'main');
        fetchRepoBranches(userRepos[0], service);
      }
    } catch (err: any) {
      toast.error('Depolar yüklenirken hata oluştu: ' + (err.message || 'Erişim reddedildi.'));
    } finally {
      setIsLoadingRepos(false);
    }
  };

  const fetchRepoBranches = async (repo: Repo, serviceInstance?: GitHubService) => {
    const svc = serviceInstance || githubService;
    if (!svc) return;

    try {
      setLoadingBranches((prev) => ({ ...prev, [repo.fullName]: true }));
      const bList = await svc.getBranches(repo.owner, repo.name);
      setBranches((prev) => ({ ...prev, [repo.fullName]: bList }));
    } catch (err: any) {
      toast.error(`"${repo.name}" dalları alınamadı: ${err.message || ''}`);
    } finally {
      setLoadingBranches((prev) => ({ ...prev, [repo.fullName]: false }));
    }
  };

  useEffect(() => {
    if (token) {
      loadUserRepos(token);
    }
  }, [token]);

  // Şifreli kayıt varsa açılışta kilit açma penceresini göster
  useEffect(() => {
    if (lockedLogin !== null && !token) {
      setIsAuthModalOpen(true);
    }
  }, [lockedLogin, token]);

  const handleSaveToken = async (
    newToken: string,
    login: string,
    storage: StorageType,
    passphrase?: string
  ) => {
    if (storage === 'encrypted') {
      if (!passphrase) throw new Error('Şifreli kayıt için parola gerekli.');
      await saveEncryptedToken(newToken, login, passphrase);
      setLockedLogin(null);
    } else {
      clearEncryptedToken();
      setLockedLogin(null);
    }

    setAuthData({ token: newToken, login, storage });
    toast.success(`@${login} olarak başarıyla bağlandınız.`);
  };

  const handleUnlock = async (passphrase: string) => {
    const unlocked = await loadEncryptedToken(passphrase);
    const svc = new GitHubService(unlocked);
    const user = await svc.verifyUser();
    setAuthData({ token: unlocked, login: user.login, storage: 'encrypted' });
    setLockedLogin(null);
    toast.success(`@${user.login} oturumu açıldı.`);
  };

  const handleForgetSaved = () => {
    clearEncryptedToken();
    setLockedLogin(null);
    toast.info('Kayıtlı şifreli token silindi.');
  };

  const handleLogout = () => {
    purgeLegacyPlaintext();
    clearEncryptedToken();
    setLockedLogin(null);
    setAuthData({ token: '', login: null, storage: 'memory' });
    setRepos([]);
    setSelectedRepo(null);
    setBranches({});
    toast.info('GitHub oturumu kapatıldı.');
  };

  const handleSelectRepo = (repo: Repo) => {
    setSelectedRepo(repo);
    setSelectedBranch(repo.defaultBranch || 'main');
    if (!branches[repo.fullName]) {
      fetchRepoBranches(repo);
    }
  };

  const handleCreateBranch = async (repo: Repo, branchName: string) => {
    if (!githubService) throw new Error('Token bulunamadı.');

    const repoBranchList = branches[repo.fullName] || [];
    let baseSha = '';
    const currentBranchObj = repoBranchList.find(
      (b) => b.name === selectedBranch || b.name === repo.defaultBranch
    );
    if (currentBranchObj) {
      baseSha = currentBranchObj.sha;
    } else if (repoBranchList.length > 0) {
      baseSha = repoBranchList[0].sha;
    }

    if (!baseSha) {
      const freshBranches = await githubService.getBranches(repo.owner, repo.name);
      if (freshBranches.length > 0) {
        baseSha = freshBranches[0].sha;
      } else {
        throw new Error('Depoda referans alınacak bir dal bulunamadı. Lütfen önce bir ilk commit yapın.');
      }
    }

    await githubService.createBranch(repo.owner, repo.name, branchName, baseSha);
    await fetchRepoBranches(repo);
    setSelectedBranch(branchName);
  };

  const handleCreateRepo = async (name: string, isPrivate: boolean, description?: string) => {
    if (!githubService) throw new Error('Token bulunamadı.');
    const newRepo = await githubService.createRepository(name, isPrivate, description);
    setRepos((prev) => [newRepo, ...prev]);
    setSelectedRepo(newRepo);
    setSelectedBranch(newRepo.defaultBranch || 'main');
    await fetchRepoBranches(newRepo);
  };

  const handleStartUpload = async (files: GitFile[], commitMessage: string) => {
    if (!githubService || !selectedRepo) return;

    // Create a new AbortController instance for this upload
    const controller = new AbortController();
    uploadAbortControllerRef.current = controller;

    setIsProgressModalOpen(true);
    setIsUploading(true);
    setPushResult(null);
    setPushError(null);

    try {
      const res = await githubService.executeAtomicPush(
        selectedRepo.owner,
        selectedRepo.name,
        selectedBranch,
        commitMessage,
        files,
        (progress) => {
          setPushProgress(progress);
        },
        controller.signal
      );

      setPushResult({
        commitSha: res.commitSha,
        commitUrl: res.commitUrl,
        fileCount: files.length,
      });
      toast.success(`${files.length} dosya başarıyla push edildi!`);
    } catch (err: any) {
      if (err.name === 'AbortError' || controller.signal.aborted) {
        setPushError('Push işlemi kullanıcı tarafından iptal edildi.');
        toast.info('İşlem iptal edildi.');
      } else {
        setPushError(err.message || 'Push işlemi sırasında bir hata meydana geldi.');
        toast.error('Hata: ' + (err.message || 'Push başarısız oldu.'));
      }
    } finally {
      setIsUploading(false);
      uploadAbortControllerRef.current = null;
    }
  };

  const handleCancelUpload = () => {
    if (uploadAbortControllerRef.current) {
      uploadAbortControllerRef.current.abort();
    }
    setIsUploading(false);
    setPushError('Push işlemi iptal edildi.');
  };

  return (
    <div className="min-h-screen bg-[#13131A] text-white flex flex-col font-sans selection:bg-[#9EA7FC]/30 selection:text-[#9EA7FC]">
      {/* Top Navbar */}
      <Navbar
        activeTab={activeTab}
        setActiveTab={setActiveTab}
        selectedRepo={selectedRepo}
        selectedBranch={selectedBranch}
        userLogin={userLogin}
        onOpenAuth={() => setIsAuthModalOpen(true)}
        onOpenRepoPicker={() => setActiveTab('repos')}
      />

      {/* Main Content Area */}
      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6">
        {/* Token Alert Banner if not logged in and not on code tab */}
        {!token && activeTab !== 'flutter_code' && (
          <div className="mb-6 p-4 rounded-2xl bg-gradient-to-r from-indigo-950/40 to-purple-950/30 border border-[#9EA7FC]/20 flex flex-col sm:flex-row sm:items-center justify-between gap-3 shadow-lg">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-[#9EA7FC]/10 border border-[#9EA7FC]/20 flex items-center justify-center text-[#9EA7FC] shrink-0">
                <KeyRound className="w-5 h-5" />
              </div>
              <div>
                <h4 className="text-sm font-bold text-white">GitHub Token Bağlantısı Gerekli</h4>
                <p className="text-xs text-white/60">
                  Repolarınızı listelemek ve doğrudan commit göndermek için GitHub Personal Access Token (PAT) girin.
                </p>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <button
                onClick={() => setIsAuthModalOpen(true)}
                className="px-4 py-2 rounded-xl bg-[#9EA7FC] hover:bg-[#b2b8fe] text-[#13131A] font-bold text-xs transition cursor-pointer shrink-0 shadow-sm"
              >
                Token Gir
              </button>
              <button
                onClick={() => setActiveTab('flutter_code')}
                className="px-3.5 py-2 rounded-xl bg-white/10 hover:bg-white/15 text-white font-medium text-xs transition cursor-pointer shrink-0"
              >
                Flutter Kodunu Gör
              </button>
            </div>
          </div>
        )}

        {/* Tab 1: ZIP Transfer Mode A */}
        {activeTab === 'zip' && (
          <ZipTransferView
            selectedRepo={selectedRepo}
            selectedBranch={selectedBranch}
            onOpenRepoPicker={() => setActiveTab('repos')}
            onStartUpload={handleStartUpload}
            isTokenReady={!!token}
            onOpenAuth={() => setIsAuthModalOpen(true)}
          />
        )}

        {/* Tab 2: Multi File Mode B */}
        {activeTab === 'multi' && (
          <MultiFileView
            selectedRepo={selectedRepo}
            selectedBranch={selectedBranch}
            onOpenRepoPicker={() => setActiveTab('repos')}
            onStartUpload={handleStartUpload}
            isTokenReady={!!token}
            onOpenAuth={() => setIsAuthModalOpen(true)}
          />
        )}

        {/* Tab 3: Repo & Branch Picker */}
        {activeTab === 'repos' && (
          <RepoPickerView
            repos={repos}
            selectedRepo={selectedRepo}
            selectedBranch={selectedBranch}
            onSelectRepo={handleSelectRepo}
            onSelectBranch={setSelectedBranch}
            branches={branches}
            loadingBranches={loadingBranches}
            onFetchBranches={(repo) => fetchRepoBranches(repo)}
            onCreateBranch={handleCreateBranch}
            onCreateRepo={handleCreateRepo}
            isLoadingRepos={isLoadingRepos}
            onRefreshRepos={() => token && loadUserRepos(token)}
          />
        )}

        {/* Tab 4: GitHub Actions Monitor */}
        {activeTab === 'actions' && (
          <ActionsView
            selectedRepo={selectedRepo}
            githubService={githubService}
            onOpenRepoPicker={() => setActiveTab('repos')}
          />
        )}

        {/* Tab 5: Single-File Unified Flutter main.dart (Lazy Loaded) */}
        {activeTab === 'flutter_code' && (
          <Suspense
            fallback={
              <div className="p-12 text-center">
                <Loader2 className="w-8 h-8 text-[#9EA7FC] animate-spin mx-auto mb-3" />
                <p className="text-xs text-white/50">Flutter kaynak kodu yükleniyor...</p>
              </div>
            }
          >
            <DartCodeViewer />
          </Suspense>
        )}
      </main>

      {/* Progress & Result Modal with true cancellation */}
      <ProgressModal
        isOpen={isProgressModalOpen}
        isUploading={isUploading}
        progress={pushProgress}
        result={pushResult}
        error={pushError}
        repo={selectedRepo}
        branch={selectedBranch}
        onClose={() => setIsProgressModalOpen(false)}
        onCancel={handleCancelUpload}
      />

      {/* Auth Token Modal */}
      <AuthModal
        isOpen={isAuthModalOpen}
        onClose={() => setIsAuthModalOpen(false)}
        token={token}
        userLogin={userLogin}
        storageType={storageType}
        lockedLogin={lockedLogin}
        onSaveToken={handleSaveToken}
        onUnlock={handleUnlock}
        onForgetSaved={handleForgetSaved}
        onLogout={handleLogout}
      />
    </div>
  );
}

export default function App() {
  return (
    <ToastProvider>
      <AppContent />
    </ToastProvider>
  );
}
