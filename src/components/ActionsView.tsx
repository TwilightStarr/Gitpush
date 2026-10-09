import React, { useState, useEffect } from 'react';
import { Repo, ActionRun } from '../types';
import { GitHubService } from '../services/github';
import { Activity, RefreshCw, CheckCircle2, XCircle, Clock, ExternalLink, Loader2, AlertCircle } from 'lucide-react';

interface ActionsViewProps {
  selectedRepo: Repo | null;
  githubService: GitHubService | null;
  onOpenRepoPicker: () => void;
}

export const ActionsView: React.FC<ActionsViewProps> = ({
  selectedRepo,
  githubService,
  onOpenRepoPicker,
}) => {
  const [runs, setRuns] = useState<ActionRun[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchRuns = async () => {
    if (!selectedRepo || !githubService) return;

    try {
      setIsLoading(true);
      setError(null);
      const data = await githubService.getWorkflowRuns(selectedRepo.owner, selectedRepo.name);
      setRuns(data);
    } catch (err: any) {
      setError(err.message || 'Workflow kayıtları alınamadı.');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchRuns();
  }, [selectedRepo]);

  if (!selectedRepo) {
    return (
      <div className="max-w-4xl mx-auto p-8 text-center bg-[#1E1E28] border border-white/10 rounded-2xl">
        <Activity className="w-10 h-10 text-white/20 mx-auto mb-3" />
        <h3 className="text-sm font-bold text-white">Repository Seçilmedi</h3>
        <p className="text-xs text-white/50 mt-1 mb-4">
          Actions workflow kayıtlarını incelemek için lütfen bir depo seçin.
        </p>
        <button
          onClick={onOpenRepoPicker}
          className="px-4 py-2 rounded-xl bg-[#9EA7FC] text-[#13131A] font-bold text-xs hover:bg-[#b2b8fe] transition cursor-pointer"
        >
          Repo Seç
        </button>
      </div>
    );
  }

  const getStatusBadge = (run: ActionRun) => {
    if (run.status !== 'completed') {
      return (
        <span className="flex items-center gap-1.5 text-xs text-amber-400 bg-amber-400/10 px-2.5 py-1 rounded-full border border-amber-400/20">
          <Clock className="w-3.5 h-3.5 animate-spin" />
          <span>Çalışıyor</span>
        </span>
      );
    }

    if (run.conclusion === 'success') {
      return (
        <span className="flex items-center gap-1.5 text-xs text-emerald-400 bg-emerald-400/10 px-2.5 py-1 rounded-full border border-emerald-400/20">
          <CheckCircle2 className="w-3.5 h-3.5" />
          <span>Başarılı</span>
        </span>
      );
    }

    if (run.conclusion === 'failure') {
      return (
        <span className="flex items-center gap-1.5 text-xs text-red-400 bg-red-400/10 px-2.5 py-1 rounded-full border border-red-400/20">
          <XCircle className="w-3.5 h-3.5" />
          <span>Hata</span>
        </span>
      );
    }

    return (
      <span className="flex items-center gap-1.5 text-xs text-white/60 bg-white/5 px-2.5 py-1 rounded-full border border-white/10">
        <span>{run.status}</span>
      </span>
    );
  };

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-white flex items-center gap-2">
            <Activity className="w-5 h-5 text-[#9EA7FC]" />
            GitHub Actions ({selectedRepo.fullName})
          </h2>
          <p className="text-xs text-white/50 mt-0.5">
            CI/CD boru hatları ve son iş akışları
          </p>
        </div>

        <button
          onClick={fetchRuns}
          disabled={isLoading}
          className="flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-[#1E1E28] hover:bg-[#252533] border border-white/10 text-white text-xs font-semibold transition cursor-pointer"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${isLoading ? 'animate-spin' : ''}`} />
          <span>Yenile</span>
        </button>
      </div>

      {/* Error state */}
      {error && (
        <div className="p-4 bg-red-950/40 border border-red-800/50 rounded-xl flex items-center gap-3 text-red-300 text-xs">
          <AlertCircle className="w-4 h-4 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {/* Loading */}
      {isLoading ? (
        <div className="p-12 text-center">
          <Loader2 className="w-8 h-8 text-[#9EA7FC] animate-spin mx-auto mb-2" />
          <p className="text-xs text-white/50">Actions verileri güncelleniyor...</p>
        </div>
      ) : runs.length === 0 ? (
        <div className="p-8 text-center bg-[#1E1E28] border border-white/10 rounded-2xl">
          <p className="text-xs text-white/50">
            Bu depoda kayıtlı bir GitHub Actions workflow çalıştırması bulunamadı.
          </p>
        </div>
      ) : (
        <div className="space-y-2">
          {runs.map((run) => (
            <div
              key={run.id}
              className="p-4 bg-[#1E1E28] border border-white/10 rounded-xl flex items-center justify-between gap-4 hover:border-white/20 transition"
            >
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-bold text-sm text-white truncate">
                    {run.name}
                  </span>
                  {getStatusBadge(run)}
                </div>
                <p className="text-xs text-white/40 mt-1">
                  Event: <span className="text-white/60 font-mono">{run.event}</span> •{' '}
                  {new Date(run.createdAt).toLocaleString('tr-TR')}
                </p>
              </div>

              <a
                href={run.htmlUrl}
                target="_blank"
                rel="noreferrer"
                className="p-2 rounded-lg bg-white/5 hover:bg-white/10 text-white/60 hover:text-white transition cursor-pointer"
                title="GitHub'da Aç"
              >
                <ExternalLink className="w-4 h-4" />
              </a>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
