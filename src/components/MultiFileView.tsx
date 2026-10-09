import React, { useState, useRef } from 'react';
import { Repo, GitFile } from '../types';
import { Files, Plus, Trash2, ArrowRight, GitFork, AlertTriangle, FileCode, AlertCircle } from 'lucide-react';
import { normalizeAndValidateGitPath, findDuplicatePaths } from '../utils/pathValidation';
import { useToast } from './Toast';

interface MultiFileViewProps {
  selectedRepo: Repo | null;
  selectedBranch: string;
  onOpenRepoPicker: () => void;
  onStartUpload: (files: GitFile[], commitMessage: string) => void;
  isTokenReady: boolean;
  onOpenAuth: () => void;
}

export const MultiFileView: React.FC<MultiFileViewProps> = ({
  selectedRepo,
  selectedBranch,
  onOpenRepoPicker,
  onStartUpload,
  isTokenReady,
  onOpenAuth,
}) => {
  const [files, setFiles] = useState<Array<GitFile & { id: string }>>([]);
  const [commitMessage, setCommitMessage] = useState('Update files via Gitpush Mod B');
  const fileInputRef = useRef<HTMLInputElement>(null);
  const toast = useToast();

  const handleFilesAdded = async (fileList: FileList) => {
    const newItems: Array<GitFile & { id: string }> = [];

    for (let i = 0; i < fileList.length; i++) {
      const f = fileList[i];
      const buffer = await f.arrayBuffer();
      const content = new Uint8Array(buffer);
      const isText = [
        '.dart', '.ts', '.tsx', '.js', '.jsx', '.json', '.yaml', '.yml',
        '.html', '.css', '.md', '.txt', '.env', '.gitignore', '.xml', '.gradle'
      ].some((ext) => f.name.toLowerCase().endsWith(ext));

      newItems.push({
        id: (crypto?.randomUUID ? crypto.randomUUID() : Math.random().toString(36).substring(2, 9)),
        name: f.name,
        path: f.name, // default repo path is the file name
        content,
        size: content.byteLength,
        isText,
      });
    }

    setFiles((prev) => [...prev, ...newItems]);
    toast.success(`${fileList.length} dosya eklendi.`);
  };

  const handlePathChange = (id: string, newPath: string) => {
    setFiles((prev) =>
      prev.map((item) => (item.id === id ? { ...item, path: newPath } : item))
    );
  };

  const handleRemove = (id: string) => {
    setFiles((prev) => prev.filter((item) => item.id !== id));
  };

  const formatSize = (bytes: number): string => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  // Check duplicate paths across all current files
  const duplicatePaths = findDuplicatePaths(files.map((f) => f.path));

  const handlePushClick = () => {
    if (!isTokenReady) {
      onOpenAuth();
      return;
    }
    if (!selectedRepo) {
      onOpenRepoPicker();
      return;
    }
    if (files.length === 0) {
      toast.error('Lütfen en az bir dosya ekleyin.');
      return;
    }

    // Validate each path
    for (const file of files) {
      const check = normalizeAndValidateGitPath(file.path);
      if (!check.isValid) {
        toast.error(`Geçersiz dosya yolu ("${file.name}"): ${check.error}`);
        return;
      }
    }

    if (duplicatePaths.length > 0) {
      toast.error(`Çakışan dosya yolu var: ${duplicatePaths.join(', ')}`);
      return;
    }

    // Format files with cleaned target paths
    const filesToUpload: GitFile[] = files.map((f) => {
      const check = normalizeAndValidateGitPath(f.path);
      return {
        name: f.name,
        path: check.normalizedPath,
        content: f.content,
        size: f.size,
        isText: f.isText,
      };
    });

    onStartUpload(filesToUpload, commitMessage.trim() || 'Update files via Gitpush Mod B');
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

      {/* Add Files Section */}
      <div className="bg-[#1E1E28] border border-white/10 rounded-2xl p-6 shadow-md">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h2 className="text-base font-bold text-white flex items-center gap-2">
              <Files className="w-5 h-5 text-[#9EA7FC]" />
              Çoklu Dosya Güncelleme (Mod B)
            </h2>
            <p className="text-xs text-white/50 mt-1">
              Dosyaları ekleyin ve depodaki hedef klasör yollarını (Örn: <code className="text-[#9EA7FC]">lib/main.dart</code>) belirleyin.
            </p>
          </div>

          <input
            type="file"
            ref={fileInputRef}
            multiple
            onChange={(e) => {
              if (e.target.files) handleFilesAdded(e.target.files);
            }}
            className="hidden"
          />

          <button
            onClick={() => fileInputRef.current?.click()}
            className="flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-[#9EA7FC] hover:bg-[#b2b8fe] text-[#13131A] font-bold text-xs transition cursor-pointer shadow-sm"
          >
            <Plus className="w-4 h-4" />
            <span>Dosya Ekle</span>
          </button>
        </div>

        {duplicatePaths.length > 0 && (
          <div className="mb-4 p-3 bg-red-950/40 border border-red-800/40 rounded-xl flex items-center gap-2 text-xs text-red-300">
            <AlertCircle className="w-4 h-4 shrink-0 text-red-400" />
            <span>
              Dikkat: Mükerrer hedef yollar bulundu: {duplicatePaths.join(', ')}. Lütfen yolları benzersiz yapın.
            </span>
          </div>
        )}

        {/* Files List */}
        {files.length === 0 ? (
          <div
            onClick={() => fileInputRef.current?.click()}
            className="border-2 border-dashed border-white/10 hover:border-white/25 rounded-xl p-8 text-center cursor-pointer transition"
          >
            <Files className="w-10 h-10 text-white/20 mx-auto mb-2" />
            <p className="text-xs font-medium text-white/70">Henüz dosya eklenmedi.</p>
            <p className="text-[11px] text-white/40 mt-1">Cihazınızdan dosya seçmek için tıklayın.</p>
          </div>
        ) : (
          <div className="space-y-3">
            {files.map((file) => {
              const pathValidation = normalizeAndValidateGitPath(file.path);
              const isDuplicate = duplicatePaths.includes(pathValidation.normalizedPath.toLowerCase());

              return (
                <div
                  key={file.id}
                  className={`p-3 bg-[#13131A] border rounded-xl space-y-2 transition ${
                    !pathValidation.isValid || isDuplicate
                      ? 'border-red-500/40'
                      : 'border-white/5'
                  }`}
                >
                  <div className="flex items-center justify-between text-xs">
                    <div className="flex items-center gap-2 min-w-0">
                      <FileCode className="w-4 h-4 text-[#9EA7FC] shrink-0" />
                      <span className="font-semibold text-white truncate">{file.name}</span>
                      <span className="text-[11px] text-white/40 shrink-0 font-mono">
                        ({formatSize(file.size)})
                      </span>
                    </div>

                    <button
                      onClick={() => handleRemove(file.id)}
                      className="p-1 text-white/30 hover:text-red-400 transition cursor-pointer"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>

                  {/* Target path input */}
                  <div>
                    <label className="block text-[11px] text-white/50 mb-1">
                      Depodaki Hedef Yol:
                    </label>
                    <input
                      type="text"
                      value={file.path}
                      onChange={(e) => handlePathChange(file.id, e.target.value)}
                      placeholder="Örn: lib/main.dart veya assets/icon.png"
                      className={`w-full px-3 py-1.5 rounded-lg bg-[#1E1E28] border text-white text-xs font-mono focus:outline-hidden transition ${
                        !pathValidation.isValid || isDuplicate
                          ? 'border-red-500 focus:border-red-400 text-red-200'
                          : 'border-white/10 focus:border-[#9EA7FC]'
                      }`}
                    />
                    {!pathValidation.isValid && (
                      <p className="text-[11px] text-red-400 mt-1 flex items-center gap-1">
                        <AlertCircle className="w-3 h-3" />
                        {pathValidation.error}
                      </p>
                    )}
                    {isDuplicate && pathValidation.isValid && (
                      <p className="text-[11px] text-amber-400 mt-1 flex items-center gap-1">
                        <AlertCircle className="w-3 h-3" />
                        Bu yol başka bir dosyada da kullanılıyor.
                      </p>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* Commit Message */}
        {files.length > 0 && (
          <div className="pt-4 mt-4 border-t border-white/10">
            <label className="block text-xs font-medium text-white/70 mb-1.5">
              Commit Mesajı
            </label>
            <input
              type="text"
              value={commitMessage}
              onChange={(e) => setCommitMessage(e.target.value)}
              placeholder="Örn: Update files via Gitpush Mod B"
              className="w-full px-3.5 py-2.5 rounded-xl bg-[#13131A] border border-white/10 text-white text-xs focus:outline-hidden focus:border-[#9EA7FC] transition"
            />
          </div>
        )}
      </div>

      {/* Bottom Floating Bar */}
      <div className="sticky bottom-4 bg-[#161622]/95 backdrop-blur-md border border-white/10 rounded-2xl p-4 flex items-center justify-between shadow-2xl">
        <div>
          <span className="text-xs text-white/50 block">Hazır Dosyalar</span>
          <span className="text-sm font-bold text-white">
            {files.length} dosya yüklenecek
          </span>
        </div>

        <button
          onClick={handlePushClick}
          disabled={files.length === 0 || duplicatePaths.length > 0}
          className={`flex items-center gap-2 px-6 py-2.5 rounded-xl font-bold text-xs transition cursor-pointer shadow-md ${
            files.length > 0 && duplicatePaths.length === 0
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
