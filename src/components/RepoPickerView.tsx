import React, { useState } from 'react';
import { Repo, Branch } from '../types';
import { GitFork, Search, Plus, Lock, Globe, Check, ChevronDown, ChevronRight, Loader2 } from 'lucide-react';
import { useToast } from './Toast';

interface RepoPickerViewProps {
  repos: Repo[];
  selectedRepo: Repo | null;
  selectedBranch: string;
  onSelectRepo: (repo: Repo) => void;
  onSelectBranch: (branch: string) => void;
  branches: Record<string, Branch[]>;
  loadingBranches: Record<string, boolean>;
  onFetchBranches: (repo: Repo) => void;
  onCreateBranch: (repo: Repo, branchName: string) => Promise<void>;
  onCreateRepo: (name: string, isPrivate: boolean, description?: string) => Promise<void>;
  isLoadingRepos: boolean;
  onRefreshRepos: () => void;
}

export const RepoPickerView: React.FC<RepoPickerViewProps> = ({
  repos,
  selectedRepo,
  selectedBranch,
  onSelectRepo,
  onSelectBranch,
  branches,
  loadingBranches,
  onFetchBranches,
  onCreateBranch,
  onCreateRepo,
  isLoadingRepos,
  onRefreshRepos,
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [expandedRepo, setExpandedRepo] = useState<string | null>(selectedRepo?.fullName || null);

  // New branch modal
  const [isBranchModalOpen, setIsBranchModalOpen] = useState(false);
  const [targetRepoForBranch, setTargetRepoForBranch] = useState<Repo | null>(null);
  const [newBranchName, setNewBranchName] = useState('');
  const [isCreatingBranch, setIsCreatingBranch] = useState(false);

  // New repo modal
  const [isRepoModalOpen, setIsRepoModalOpen] = useState(false);
  const [newRepoName, setNewRepoName] = useState('');
  const [newRepoDesc, setNewRepoDesc] = useState('');
  const [newRepoIsPrivate, setNewRepoIsPrivate] = useState(true);
  const [isCreatingRepo, setIsCreatingRepo] = useState(false);

  const toast = useToast();

  const filteredRepos = repos.filter((r) =>
    r.fullName.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const toggleExpand = (repo: Repo) => {
    if (expandedRepo === repo.fullName) {
      setExpandedRepo(null);
    } else {
      setExpandedRepo(repo.fullName);
      onSelectRepo(repo);
      if (!branches[repo.fullName]) {
        onFetchBranches(repo);
      }
    }
  };

  const handleCreateBranchSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const branch = newBranchName.trim();
    if (!targetRepoForBranch || !branch) return;

    // Validate git branch name format
    if (/[~^:?*\[\]\\]|\.\.|\/\.|\/\/|@\{/.test(branch) || branch.startsWith('/') || branch.endsWith('/') || branch.endsWith('.')) {
      toast.error('Geçersiz dal adı. Boşluk veya yasaklı Git karakterleri (~, ^, :, ?, *, .., // vb.) içeremez.');
      return;
    }

    try {
      setIsCreatingBranch(true);
      await onCreateBranch(targetRepoForBranch, branch);
      toast.success(`"${branch}" dalı başarıyla oluşturuldu.`);
      setIsBranchModalOpen(false);
      setNewBranchName('');
    } catch (err: any) {
      toast.error('Dal oluşturulamadı: ' + (err.message || 'Bilinmeyen hata'));
    } finally {
      setIsCreatingBranch(false);
    }
  };

  const handleCreateRepoSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const repoName = newRepoName.trim();
    if (!repoName) return;

    // Validate GitHub repo name format (alphanumeric, -, _, .)
    if (!/^[a-zA-Z0-9_.-]+$/.test(repoName)) {
      toast.error('Geçersiz repo adı. Yalnızca harf, rakam, tire (-), alt çizgi (_) ve nokta (.) içerebilir.');
      return;
    }

    try {
      setIsCreatingRepo(true);
      await onCreateRepo(repoName, newRepoIsPrivate, newRepoDesc.trim());
      toast.success(`"${repoName}" deposu başarıyla oluşturuldu.`);
      setIsRepoModalOpen(false);
      setNewRepoName('');
      setNewRepoDesc('');
    } catch (err: any) {
      toast.error('Repo oluşturulamadı: ' + (err.message || 'Bilinmeyen hata'));
    } finally {
      setIsCreatingRepo(false);
    }
  };

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      {/* Header & Actions */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-xl font-bold text-white tracking-tight">Repo & Dal Seçimi</h2>
          <p className="text-xs text-white/50 mt-0.5">
            Aktarım yapacağınız depoyu ve hedef branch'i belirleyin.
          </p>
        </div>

        <div className="flex items-center gap-2 self-start sm:self-auto">
          <button
            onClick={onRefreshRepos}
            className="px-3.5 py-2 rounded-xl bg-white/10 hover:bg-white/20 text-white font-medium text-xs transition cursor-pointer"
          >
            Yenile
          </button>
          <button
            onClick={() => setIsRepoModalOpen(true)}
            className="flex items-center justify-center gap-1.5 px-4 py-2 rounded-xl bg-[#9EA7FC] hover:bg-[#b2b8fe] text-[#13131A] font-bold text-xs transition cursor-pointer shadow-md"
          >
            <Plus className="w-4 h-4" />
            <span>Yeni Repo Oluştur</span>
          </button>
        </div>
      </div>

      {/* Search Bar */}
      <div className="relative">
        <Search className="w-4 h-4 absolute left-3.5 top-1/2 -translate-y-1/2 text-white/40" />
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Depolarda ara (Örn: username/repo)..."
          className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-[#1E1E28] border border-white/10 text-white text-xs placeholder:text-white/30 focus:outline-hidden focus:border-[#9EA7FC] transition"
        />
      </div>

      {/* Repo List */}
      {isLoadingRepos ? (
        <div className="p-12 text-center">
          <Loader2 className="w-8 h-8 text-[#9EA7FC] animate-spin mx-auto mb-3" />
          <p className="text-xs text-white/50">Depolar GitHub'dan alınıyor...</p>
        </div>
      ) : filteredRepos.length === 0 ? (
        <div className="p-8 text-center bg-[#1E1E28] border border-white/10 rounded-2xl">
          <p className="text-xs text-white/50">Eşleşen depo bulunamadı.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {filteredRepos.map((repo) => {
            const isSelected = selectedRepo?.fullName === repo.fullName;
            const isExpanded = expandedRepo === repo.fullName;
            const repoBranches = branches[repo.fullName] || [];
            const isLoadingB = loadingBranches[repo.fullName];

            return (
              <div
                key={repo.id}
                className={`bg-[#1E1E28] border rounded-xl overflow-hidden transition ${
                  isSelected ? 'border-[#9EA7FC]/40' : 'border-white/10 hover:border-white/20'
                }`}
              >
                {/* Header */}
                <div
                  onClick={() => toggleExpand(repo)}
                  className="p-4 flex items-center justify-between cursor-pointer"
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <div
                      className={`w-8 h-8 rounded-lg flex items-center justify-center shrink-0 ${
                        repo.isPrivate
                          ? 'bg-amber-500/10 text-amber-400'
                          : 'bg-emerald-500/10 text-emerald-400'
                      }`}
                    >
                      {repo.isPrivate ? <Lock className="w-4 h-4" /> : <Globe className="w-4 h-4" />}
                    </div>

                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="font-bold text-sm text-white truncate font-mono">
                          {repo.fullName}
                        </span>
                        {isSelected && (
                          <span className="text-[10px] bg-[#9EA7FC]/20 text-[#9EA7FC] font-semibold px-2 py-0.5 rounded-full">
                            Seçili
                          </span>
                        )}
                      </div>
                      <p className="text-xs text-white/40 truncate">
                        Varsayılan Dal: <span className="font-mono text-white/60">{repo.defaultBranch}</span>
                      </p>
                    </div>
                  </div>

                  <div className="flex items-center gap-2 text-white/40">
                    {isExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                  </div>
                </div>

                {/* Branches Accordion Content */}
                {isExpanded && (
                  <div className="border-t border-white/5 bg-[#13131A] p-4 space-y-3">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-white/60 uppercase tracking-wider flex items-center gap-1.5">
                        <GitFork className="w-3.5 h-3.5 rotate-90 text-[#9EA7FC]" />
                        Dallar (Branches)
                      </span>

                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          setTargetRepoForBranch(repo);
                          setIsBranchModalOpen(true);
                        }}
                        className="text-xs text-[#9EA7FC] hover:underline flex items-center gap-1 cursor-pointer"
                      >
                        <Plus className="w-3 h-3" />
                        <span>Yeni Dal</span>
                      </button>
                    </div>

                    {isLoadingB ? (
                      <div className="py-4 text-center">
                        <Loader2 className="w-4 h-4 text-[#9EA7FC] animate-spin mx-auto mb-1" />
                        <span className="text-[11px] text-white/40">Dallar yükleniyor...</span>
                      </div>
                    ) : (
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                        {repoBranches.map((branch) => {
                          const isBranchActive =
                            isSelected && selectedBranch === branch.name;
                          return (
                            <div
                              key={branch.name}
                              onClick={() => {
                                onSelectRepo(repo);
                                onSelectBranch(branch.name);
                              }}
                              className={`flex items-center justify-between px-3 py-2 rounded-lg cursor-pointer text-xs font-mono transition ${
                                isBranchActive
                                  ? 'bg-[#9EA7FC]/15 text-[#9EA7FC] border border-[#9EA7FC]/30 font-semibold'
                                  : 'bg-[#1E1E28] hover:bg-[#252533] text-white/70 hover:text-white'
                              }`}
                            >
                              <div className="flex items-center gap-2 truncate">
                                <GitFork className="w-3 h-3 text-[#9EA7FC]" />
                                <span className="truncate">{branch.name}</span>
                              </div>
                              {isBranchActive && <Check className="w-3.5 h-3.5 text-[#9EA7FC]" />}
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Modal: New Branch */}
      {isBranchModalOpen && targetRepoForBranch && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-xs">
          <form
            onSubmit={handleCreateBranchSubmit}
            className="bg-[#1E1E28] border border-white/10 rounded-2xl max-w-sm w-full p-6 space-y-4 shadow-2xl"
          >
            <h3 className="font-bold text-base text-white">Yeni Dal (Branch) Oluştur</h3>
            <p className="text-xs text-white/50">
              <span className="font-medium text-white">{targetRepoForBranch.fullName}</span> için yeni bir dal oluşturulacak.
            </p>

            <div>
              <label className="block text-xs font-medium text-white/70 mb-1">
                Dal Adı
              </label>
              <input
                type="text"
                autoFocus
                required
                value={newBranchName}
                onChange={(e) => setNewBranchName(e.target.value)}
                placeholder="Örn: feature-1 veya patch-v2"
                className="w-full px-3 py-2 rounded-xl bg-[#13131A] border border-white/10 text-white text-xs font-mono focus:outline-hidden focus:border-[#9EA7FC]"
              />
            </div>

            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setIsBranchModalOpen(false)}
                className="px-3.5 py-1.5 rounded-lg text-xs text-white/60 hover:text-white transition cursor-pointer"
              >
                İptal
              </button>
              <button
                type="submit"
                disabled={isCreatingBranch || !newBranchName.trim()}
                className="px-4 py-1.5 rounded-lg bg-[#9EA7FC] hover:bg-[#b2b8fe] text-[#13131A] font-bold text-xs transition cursor-pointer disabled:opacity-50"
              >
                {isCreatingBranch ? 'Oluşturuluyor...' : 'Oluştur'}
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Modal: New Repo */}
      {isRepoModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-xs">
          <form
            onSubmit={handleCreateRepoSubmit}
            className="bg-[#1E1E28] border border-white/10 rounded-2xl max-w-md w-full p-6 space-y-4 shadow-2xl"
          >
            <h3 className="font-bold text-base text-white">Yeni GitHub Deposu Oluştur</h3>

            <div>
              <label className="block text-xs font-medium text-white/70 mb-1">
                Repo Adı
              </label>
              <input
                type="text"
                autoFocus
                required
                value={newRepoName}
                onChange={(e) => setNewRepoName(e.target.value)}
                placeholder="Örn: my-awesome-project"
                className="w-full px-3 py-2 rounded-xl bg-[#13131A] border border-white/10 text-white text-xs font-mono focus:outline-hidden focus:border-[#9EA7FC]"
              />
            </div>

            <div>
              <label className="block text-xs font-medium text-white/70 mb-1">
                Açıklama (Opsiyonel)
              </label>
              <input
                type="text"
                value={newRepoDesc}
                onChange={(e) => setNewRepoDesc(e.target.value)}
                placeholder="Örn: Gitpush ile aktarılan proje"
                className="w-full px-3 py-2 rounded-xl bg-[#13131A] border border-white/10 text-white text-xs focus:outline-hidden focus:border-[#9EA7FC]"
              />
            </div>

            <div className="flex items-center justify-between p-3 rounded-xl bg-[#13131A] border border-white/5">
              <div className="flex items-center gap-2">
                {newRepoIsPrivate ? <Lock className="w-4 h-4 text-amber-400" /> : <Globe className="w-4 h-4 text-emerald-400" />}
                <span className="text-xs text-white font-medium">
                  {newRepoIsPrivate ? 'Private Repository (Gizli)' : 'Public Repository (Açık)'}
                </span>
              </div>
              <input
                type="checkbox"
                checked={newRepoIsPrivate}
                onChange={(e) => setNewRepoIsPrivate(e.target.checked)}
                className="w-4 h-4 accent-[#9EA7FC] rounded"
              />
            </div>

            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setIsRepoModalOpen(false)}
                className="px-3.5 py-1.5 rounded-lg text-xs text-white/60 hover:text-white transition cursor-pointer"
              >
                İptal
              </button>
              <button
                type="submit"
                disabled={isCreatingRepo || !newRepoName.trim()}
                className="px-4 py-1.5 rounded-lg bg-[#9EA7FC] hover:bg-[#b2b8fe] text-[#13131A] font-bold text-xs transition cursor-pointer disabled:opacity-50"
              >
                {isCreatingRepo ? 'Oluşturuluyor...' : 'Depoyu Oluştur'}
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
};
