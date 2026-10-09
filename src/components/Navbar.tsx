import React from 'react';
import { ActiveTab, Repo } from '../types';
import { Archive, Files, GitFork, Activity, Code2, KeyRound, ExternalLink, ShieldCheck, Lock, Globe } from 'lucide-react';

interface NavbarProps {
  activeTab: ActiveTab;
  setActiveTab: (tab: ActiveTab) => void;
  selectedRepo: Repo | null;
  selectedBranch: string;
  userLogin: string | null;
  onOpenAuth: () => void;
  onOpenRepoPicker: () => void;
}

export const Navbar: React.FC<NavbarProps> = ({
  activeTab,
  setActiveTab,
  selectedRepo,
  selectedBranch,
  userLogin,
  onOpenAuth,
  onOpenRepoPicker,
}) => {
  return (
    <header className="border-b border-white/10 bg-[#161622] sticky top-0 z-30">
      {/* Top Banner */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          {/* Logo & Title */}
          <div className="flex items-center gap-3">
            <img src="/favicon.svg" alt="Gitpush" className="w-10 h-10 rounded-xl" />
            <div>
              <div className="flex items-center gap-2">
                <span className="font-bold text-lg text-white tracking-tight">Gitpush</span>
                <span className="text-[11px] px-2 py-0.5 rounded-full bg-[#9EA7FC]/15 text-[#9EA7FC] font-medium border border-[#9EA7FC]/30">
                  Tek Dosya Derlenmiş
                </span>
              </div>
              <p className="text-xs text-white/50 hidden sm:block">
                Atomik Git Push & Depo Yöneticisi
              </p>
            </div>
          </div>

          {/* Active Repo & Branch Chip */}
          {selectedRepo && (
            <div className="hidden md:flex items-center gap-2 px-3 py-1.5 rounded-lg bg-[#1E1E28] border border-white/10 text-xs">
              {selectedRepo.isPrivate ? (
                <Lock className="w-3.5 h-3.5 text-amber-400" />
              ) : (
                <Globe className="w-3.5 h-3.5 text-emerald-400" />
              )}
              <span className="text-white/80 font-mono font-medium max-w-[180px] truncate">
                {selectedRepo.fullName}
              </span>
              <span className="text-white/30">•</span>
              <div className="flex items-center gap-1 text-[#9EA7FC]">
                <GitFork className="w-3 h-3" />
                <span className="font-mono">{selectedBranch}</span>
              </div>
              <button
                onClick={onOpenRepoPicker}
                className="ml-1 text-white/50 hover:text-white transition underline cursor-pointer"
              >
                Değiştir
              </button>
            </div>
          )}

          {/* User Status & Token Button */}
          <div className="flex items-center gap-3">
            {userLogin ? (
              <button
                onClick={onOpenAuth}
                className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-[#1E1E28] hover:bg-[#252533] border border-white/10 text-xs text-white transition cursor-pointer"
              >
                <div className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
                <span className="font-mono font-medium">@{userLogin}</span>
              </button>
            ) : (
              <button
                onClick={onOpenAuth}
                className="flex items-center gap-2 px-3.5 py-1.5 rounded-lg bg-[#9EA7FC] hover:bg-[#b0b7fd] text-[#13131A] font-semibold text-xs transition cursor-pointer shadow-sm"
              >
                <KeyRound className="w-3.5 h-3.5" />
                <span>PAT Token Gir</span>
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Navigation Tabs */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 border-t border-white/5 overflow-x-auto scrollbar-none">
        <nav className="flex space-x-2 py-2" aria-label="Tabs">
          <button
            onClick={() => setActiveTab('zip')}
            className={`flex items-center gap-2 px-3.5 py-2 rounded-lg text-xs sm:text-sm font-medium transition cursor-pointer whitespace-nowrap ${
              activeTab === 'zip'
                ? 'bg-[#9EA7FC]/15 text-[#9EA7FC] border border-[#9EA7FC]/30 shadow-sm'
                : 'text-white/70 hover:text-white hover:bg-white/5'
            }`}
          >
            <Archive className="w-4 h-4" />
            <span>ZIP'ten Aktar (Mod A)</span>
          </button>

          <button
            onClick={() => setActiveTab('multi')}
            className={`flex items-center gap-2 px-3.5 py-2 rounded-lg text-xs sm:text-sm font-medium transition cursor-pointer whitespace-nowrap ${
              activeTab === 'multi'
                ? 'bg-[#9EA7FC]/15 text-[#9EA7FC] border border-[#9EA7FC]/30 shadow-sm'
                : 'text-white/70 hover:text-white hover:bg-white/5'
            }`}
          >
            <Files className="w-4 h-4" />
            <span>Çoklu Dosya (Mod B)</span>
          </button>

          <button
            onClick={() => setActiveTab('repos')}
            className={`flex items-center gap-2 px-3.5 py-2 rounded-lg text-xs sm:text-sm font-medium transition cursor-pointer whitespace-nowrap ${
              activeTab === 'repos'
                ? 'bg-[#9EA7FC]/15 text-[#9EA7FC] border border-[#9EA7FC]/30 shadow-sm'
                : 'text-white/70 hover:text-white hover:bg-white/5'
            }`}
          >
            <GitFork className="w-4 h-4" />
            <span>Repo & Dal Seçici</span>
          </button>

          <button
            onClick={() => setActiveTab('actions')}
            className={`flex items-center gap-2 px-3.5 py-2 rounded-lg text-xs sm:text-sm font-medium transition cursor-pointer whitespace-nowrap ${
              activeTab === 'actions'
                ? 'bg-[#9EA7FC]/15 text-[#9EA7FC] border border-[#9EA7FC]/30 shadow-sm'
                : 'text-white/70 hover:text-white hover:bg-white/5'
            }`}
          >
            <Activity className="w-4 h-4" />
            <span>GitHub Actions</span>
          </button>

          <button
            onClick={() => setActiveTab('flutter_code')}
            className={`flex items-center gap-2 px-3.5 py-2 rounded-lg text-xs sm:text-sm font-medium transition cursor-pointer whitespace-nowrap ml-auto ${
              activeTab === 'flutter_code'
                ? 'bg-[#9EA7FC] text-[#13131A] font-semibold shadow-sm'
                : 'bg-white/10 text-white hover:bg-white/15'
            }`}
          >
            <Code2 className="w-4 h-4" />
            <span>Tek Dosya Flutter (main.dart)</span>
          </button>
        </nav>
      </div>
    </header>
  );
};
