import React, { useState, useRef } from 'react';
import { Repo, GitFile } from '../types';
import { ZipService } from '../services/zip';
import { Upload, CheckSquare, Square, FolderArchive, ArrowRight, GitFork, AlertTriangle } from 'lucide-react';
import { useToast } from './Toast';

interface ZipTransferViewProps {
  selectedRepo: Repo | null;
  selectedBranch: string;
  onOpenRepoPicker: () => void;
  onStartUpload: (files: GitFile[], commitMessage: string) => void;
  isTokenReady: boolean;
  onOpenAuth: () => void;
}

export const ZipTransferView: React.FC<ZipTransferViewProps> = ({
  selectedRepo,
  selectedBranch,
  onOpenRepoPicker,
  onStartUpload,
  isTokenReady,
  onOpenAuth,
}) => {
  const [zipFileName, setZipFileName] = useState<string | null>(null);
  const [allFiles, setAllFiles] = useState<GitFile[]>([]);
  const [selectedPaths, setSelectedPaths] = useState<Set<string>>(new Set());
  const [commitMessage, setCommitMessage] = useState<string>('Update project via Gitpush');
  const [isProcessingZip, setIsProcessingZip] = useState<boolean>(false);
  const [isDragging, setIsDragging] = useState<boolean>(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const toast = useToast();

  const handleZipFile = async (file: File) => {
    if (!file.name.toLowerCase().endsWith('.zip')) {
      toast.error('Lütfen geçerli bir .zip dosyası seçin.');
      return;
    }

    try {
      setIsProcessingZip(true);
      const extracted = await ZipService.extractZip(file);
      if (extracted.length === 0) {
        toast.error('ZIP içerisinde aktarılabilecek geçerli dosya bulunamadı (.gitignore filtrelenmiş olabilir).');
        return;
      }
      setZipFileName(file.name);
      setAllFiles(extracted);
      setSelectedPaths(new Set(extracted.map((f) => f.path)));
      toast.success(`${extracted.length} dosya ZIP arşivinden ayıklandı.`);
    } catch (err: any) {
      toast.error('ZIP ayıklanırken hata oluştu: ' + (err.message || 'Bilinmeyen hata'));
    } finally {
      setIsProcessingZip(false);
    }
  };

  const handleFileInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      handleZipFile(e.target.files[0]);
    }
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      handleZipFile(e.dataTransfer.files[0]);
    }
  };

  const toggleSelect = (path: string) => {
    const next = new Set(selectedPaths);
    if (next.has(path)) {
      next.delete(path);
    } else {
      next.add(path);
    }
    setSelectedPaths(next);
  };

  const selectAll = () => {
    setSelectedPaths(new Set(allFiles.map((f) => f.path)));
  };

  const deselectAll = () => {
    setSelectedPaths(new Set());
  };

  const formatSize = (bytes: number): string => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  const selectedCount = selectedPaths.size;
  const filteredFilesToUpload = allFiles.filter((f) => selectedPaths.has(f.path));

  const handlePushClick = () => {
    if (!isTokenReady) {
      onOpenAuth();
      return;
    }
    if (!selectedRepo) {
      onOpenRepoPicker();
      return;
    }
    if (filteredFilesToUpload.length === 0) {
      toast.error('Lütfen en az bir dosya seçin.');
      return;
    }
    onStartUpload(filteredFilesToUpload, commitMessage.trim() || 'Update project via Gitpush');
  };

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      {/* Target Repo Banner */}
      <div className="bg-[#1E1E28] border border-white/10 rounded-2xl p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 shadow-md">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-[#9EA7FC]/10 border border-[#9EA7FC]/20 flex items-center justify-center text-[#9EA7FC]">
            <GitFork className="w-5 h-5 rotate-90" />
          </div>
          <div>
            <span className="text-xs text-white/50 block font-medium">Hedef Repository & Dal</span>
            {selectedRepo ? (
              <div className="flex items-center gap-2">
                <span className="font-bold text-white text-sm">{selectedRepo.fullName}</span>
                <span className="text-xs px-2 py-0.5 rounded bg-white/10 font-mono text-[#9EA7FC]">
                  {selectedBranch}
                </span>
              </div>
            ) : (
              <span className="text-xs text-amber-300 font-medium flex items-center gap-1">
                <AlertTriangle className="w-3.5 h-3.5" /> Henüz repo seçilmedi
              </span>
            )}
          </div>
        </div>

        <button
          onClick={onOpenRepoPicker}
          className="self-start sm:self-center px-3.5 py-1.5 rounded-lg bg-[#2E2E3E] hover:bg-[#3B3B4E] text-xs font-semibold text-white transition cursor-pointer"
        >
          {selectedRepo ? 'Değiştir' : 'Repo Seç'}
        </button>
      </div>

      {/* 1. ZIP File Picker Card */}
      <div className="bg-[#1E1E28] border border-white/10 rounded-2xl p-6 shadow-md">
        <h2 className="text-base font-bold text-white flex items-center gap-2 mb-4">
          <span className="w-6 h-6 rounded-full bg-[#9EA7FC] text-[#13131A] text-xs flex items-center justify-center font-bold">
            1
          </span>
          ZIP Dosyası Yükleme
        </h2>

        <input
          type="file"
          ref={fileInputRef}
          accept=".zip"
          onChange={handleFileInputChange}
          className="hidden"
        />

        {!zipFileName ? (
          <div
            onDragOver={(e) => {
              e.preventDefault();
              setIsDragging(true);
            }}
            onDragLeave={() => setIsDragging(false)}
            onDrop={handleDrop}
            onClick={() => fileInputRef.current?.click()}
            className={`border-2 border-dashed rounded-2xl p-8 text-center cursor-pointer transition flex flex-col items-center justify-center gap-3 ${
              isDragging
                ? 'border-[#9EA7FC] bg-[#9EA7FC]/10'
                : 'border-white/15 hover:border-white/30 bg-[#161622]/50'
            }`}
          >
            <div className="w-14 h-14 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-center text-[#9EA7FC]">
              <Upload className="w-7 h-7" />
            </div>
            <div>
              <p className="font-semibold text-white text-sm">
                ZIP dosyasını buraya sürükleyin veya seçmek için tıklayın
              </p>
              <p className="text-xs text-white/40 mt-1">
                Otomatik olarak kök klasör temizliği ve .gitignore filtrelemesi uygulanır
              </p>
            </div>
            {isProcessingZip && (
              <span className="text-xs text-[#9EA7FC] font-medium animate-pulse">
                Ayıklanıyor, lütfen bekleyin...
              </span>
            )}
          </div>
        ) : (
          <div className="flex items-center justify-between p-4 bg-[#13131A] border border-white/10 rounded-xl">
            <div className="flex items-center gap-3 min-w-0">
              <div className="w-10 h-10 rounded-xl bg-blue-500/20 text-blue-400 border border-blue-500/30 flex items-center justify-center shrink-0">
                <FolderArchive className="w-5 h-5" />
              </div>
              <div className="truncate">
                <p className="text-sm font-semibold text-white truncate">{zipFileName}</p>
                <p className="text-xs text-white/50">{allFiles.length} dosya ayıklandı</p>
              </div>
            </div>

            <button
              onClick={() => fileInputRef.current?.click()}
              className="px-3 py-1.5 rounded-lg text-xs bg-white/10 hover:bg-white/20 text-white font-medium transition cursor-pointer"
            >
              Farklı ZIP Seç
            </button>
          </div>
        )}
      </div>

      {/* 2. File Selection & Filter List */}
      {allFiles.length > 0 && (
        <div className="bg-[#1E1E28] border border-white/10 rounded-2xl p-6 shadow-md space-y-4">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-white/10 pb-4">
            <div>
              <h2 className="text-base font-bold text-white flex items-center gap-2">
                <span className="w-6 h-6 rounded-full bg-[#9EA7FC] text-[#13131A] text-xs flex items-center justify-center font-bold">
                  2
                </span>
                Aktarılacak Dosyalar ({selectedCount} / {allFiles.length})
              </h2>
              <p className="text-xs text-white/50 mt-0.5">
                Kök dizinden gereksiz kapsayıcı sıyrılmıştır
              </p>
            </div>

            <div className="flex items-center gap-2">
              <button
                onClick={selectAll}
                className="text-xs px-2.5 py-1 rounded-md bg-white/5 hover:bg-white/10 text-white/80 hover:text-white transition cursor-pointer"
              >
                Tümünü Seç
              </button>
              <button
                onClick={deselectAll}
                className="text-xs px-2.5 py-1 rounded-md bg-white/5 hover:bg-white/10 text-white/80 hover:text-white transition cursor-pointer"
              >
                Temizle
              </button>
            </div>
          </div>

          {/* Scrollable File List */}
          <div className="max-h-72 overflow-y-auto space-y-1 pr-1 divide-y divide-white/5">
            {allFiles.map((file) => {
              const isSelected = selectedPaths.has(file.path);
              return (
                <div
                  key={file.path}
                  onClick={() => toggleSelect(file.path)}
                  className={`flex items-center justify-between p-2 rounded-lg cursor-pointer transition text-xs font-mono ${
                    isSelected ? 'bg-[#9EA7FC]/10 text-white' : 'text-white/60 hover:bg-white/5'
                  }`}
                >
                  <div className="flex items-center gap-2.5 min-w-0">
                    {isSelected ? (
                      <CheckSquare className="w-4 h-4 text-[#9EA7FC] shrink-0" />
                    ) : (
                      <Square className="w-4 h-4 text-white/30 shrink-0" />
                    )}
                    <span className="truncate">{file.path}</span>
                  </div>
                  <span className="text-[11px] text-white/40 shrink-0 ml-2">
                    {formatSize(file.size)}
                  </span>
                </div>
              );
            })}
          </div>

          {/* 3. Commit Message */}
          <div className="pt-4 border-t border-white/10">
            <label className="block text-xs font-medium text-white/70 mb-1.5">
              Commit Mesajı
            </label>
            <input
              type="text"
              value={commitMessage}
              onChange={(e) => setCommitMessage(e.target.value)}
              placeholder="Örn: Update project via Gitpush"
              className="w-full px-3.5 py-2.5 rounded-xl bg-[#13131A] border border-white/10 text-white text-xs focus:outline-hidden focus:border-[#9EA7FC] transition"
            />
          </div>
        </div>
      )}

      {/* Bottom Floating Bar */}
      <div className="sticky bottom-4 bg-[#161622]/95 backdrop-blur-md border border-white/10 rounded-2xl p-4 flex items-center justify-between shadow-2xl">
        <div>
          <span className="text-xs text-white/50 block">Seçilen Dosya</span>
          <span className="text-sm font-bold text-white">
            {selectedCount} dosya gönderilmeye hazır
          </span>
        </div>

        <button
          onClick={handlePushClick}
          disabled={selectedCount === 0}
          className={`flex items-center gap-2 px-6 py-2.5 rounded-xl font-bold text-xs transition cursor-pointer shadow-md ${
            selectedCount > 0
              ? 'bg-[#9EA7FC] hover:bg-[#b2b8fe] text-[#13131A]'
              : 'bg-white/10 text-white/40 cursor-not-allowed'
          }`}
        >
          <span>{selectedRepo ? 'Depoya Push Et' : 'Repo Seç & Gönder'}</span>
          <ArrowRight className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};
