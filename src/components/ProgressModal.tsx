import React from 'react';
import { PushProgress, Repo } from '../types';
import { CheckCircle2, AlertCircle, Loader2, GitCommit, ExternalLink, X } from 'lucide-react';

interface ProgressModalProps {
  isOpen: boolean;
  isUploading: boolean;
  progress: PushProgress;
  result: { commitSha: string; commitUrl: string; fileCount: number } | null;
  error: string | null;
  repo: Repo | null;
  branch: string;
  onClose: () => void;
  onCancel: () => void;
}

export const ProgressModal: React.FC<ProgressModalProps> = ({
  isOpen,
  isUploading,
  progress,
  result,
  error,
  repo,
  branch,
  onClose,
  onCancel,
}) => {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-xs animate-in fade-in duration-200">
      <div className="bg-[#1E1E28] border border-white/10 rounded-2xl max-w-md w-full p-6 shadow-2xl relative">
        {/* Close Button when finished or errored */}
        {!isUploading && (
          <button
            onClick={onClose}
            className="absolute top-4 right-4 text-white/50 hover:text-white transition cursor-pointer"
          >
            <X className="w-5 h-5" />
          </button>
        )}

        {/* State 1: In Progress */}
        {isUploading && (
          <div className="space-y-5">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Loader2 className="w-5 h-5 text-[#9EA7FC] animate-spin" />
                <h3 className="font-semibold text-lg text-white">GitHub'a Aktarılıyor</h3>
              </div>
              <span className="text-sm font-mono font-bold text-[#9EA7FC]">
                {Math.round(progress.progress * 100)}%
              </span>
            </div>

            {/* Progress bar */}
            <div className="w-full bg-white/10 h-2.5 rounded-full overflow-hidden">
              <div
                className="bg-[#9EA7FC] h-full transition-all duration-300 rounded-full"
                style={{ width: `${Math.max(5, Math.round(progress.progress * 100))}%` }}
              />
            </div>

            <div className="p-3 bg-[#13131A] rounded-xl border border-white/5 text-xs text-white/80 font-mono flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-[#9EA7FC] animate-ping shrink-0" />
              <span className="truncate">{progress.message}</span>
            </div>

            <p className="text-xs text-white/40">
              Hedef: <strong className="text-white/70">{repo?.fullName}</strong> ({branch})
            </p>

            <button
              onClick={onCancel}
              className="w-full py-2.5 px-4 rounded-xl border border-red-500/30 text-red-400 hover:bg-red-500/10 text-xs font-semibold transition cursor-pointer"
            >
              İşlemi İptal Et
            </button>
          </div>
        )}

        {/* State 2: Success Result */}
        {!isUploading && result && (
          <div className="space-y-5 text-center">
            <div className="w-16 h-16 rounded-full bg-emerald-500/20 text-emerald-400 flex items-center justify-center mx-auto border border-emerald-500/30">
              <CheckCircle2 className="w-8 h-8" />
            </div>

            <div>
              <h3 className="text-xl font-bold text-white">Atomik Push Tamamlandı!</h3>
              <p className="text-xs text-white/60 mt-1">
                {result.fileCount} dosya başarıyla <span className="text-white font-medium">{repo?.fullName}</span> deposunun <span className="text-[#9EA7FC] font-medium">{branch}</span> dalına aktarıldı.
              </p>
            </div>

            {/* Commit Details Card */}
            <div className="bg-[#13131A] border border-white/5 rounded-xl p-4 text-left space-y-2">
              <div className="flex items-center justify-between text-xs">
                <span className="text-white/40">Commit SHA:</span>
                <span className="font-mono font-bold text-[#9EA7FC] bg-[#9EA7FC]/10 px-2 py-0.5 rounded">
                  {result.commitSha.slice(0, 7)}
                </span>
              </div>
              <div className="flex items-center justify-between text-xs">
                <span className="text-white/40">Tam Hash:</span>
                <span className="font-mono text-white/70 text-[10px] truncate max-w-[200px]">
                  {result.commitSha}
                </span>
              </div>
            </div>

            <div className="space-y-2 pt-2">
              <a
                href={result.commitUrl}
                target="_blank"
                rel="noreferrer"
                className="w-full inline-flex items-center justify-center gap-2 py-2.5 px-4 rounded-xl bg-[#9EA7FC] hover:bg-[#b2b8fe] text-[#13131A] font-bold text-xs transition cursor-pointer shadow-md"
              >
                <ExternalLink className="w-4 h-4" />
                <span>GitHub'da Görüntüle</span>
              </a>

              <button
                onClick={onClose}
                className="w-full py-2 px-4 rounded-xl text-white/60 hover:text-white text-xs transition cursor-pointer"
              >
                Tamam ve Kapat
              </button>
            </div>
          </div>
        )}

        {/* State 3: Error */}
        {!isUploading && error && !result && (
          <div className="space-y-4 text-center">
            <div className="w-14 h-14 rounded-full bg-red-500/20 text-red-400 flex items-center justify-center mx-auto border border-red-500/30">
              <AlertCircle className="w-7 h-7" />
            </div>

            <div>
              <h3 className="text-lg font-bold text-white">Yükleme Başarısız</h3>
              <p className="text-xs text-red-300 mt-2 bg-red-950/40 p-3 rounded-xl border border-red-800/40 font-mono break-all text-left">
                {error}
              </p>
            </div>

            <button
              onClick={onClose}
              className="w-full py-2.5 px-4 rounded-xl bg-[#2E2E3E] hover:bg-[#3E3E4E] text-white text-xs font-semibold transition cursor-pointer"
            >
              Kapat ve Tekrar Dene
            </button>
          </div>
        )}
      </div>
    </div>
  );
};
