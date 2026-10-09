import React, { useState } from 'react';
import { UNIFIED_DART_CODE } from '../services/flutterCode';
import { Code2, Copy, Check, Download, ShieldCheck, CheckCircle2, Sparkles } from 'lucide-react';

export const DartCodeViewer: React.FC = () => {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText(UNIFIED_DART_CODE);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleDownload = () => {
    const blob = new Blob([UNIFIED_DART_CODE], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'main.dart';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  };

  return (
    <div className="max-w-5xl mx-auto space-y-6">
      {/* Overview Card */}
      <div className="bg-gradient-to-r from-[#1E1E28] to-[#252535] border border-white/10 rounded-2xl p-6 shadow-xl">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2">
              <span className="p-2 rounded-xl bg-[#9EA7FC]/10 text-[#9EA7FC] border border-[#9EA7FC]/20">
                <Code2 className="w-6 h-6" />
              </span>
              <div>
                <h2 className="text-xl font-bold text-white tracking-tight">
                  Tek Dosya Tam Entegre Flutter Kodu (main.dart)
                </h2>
                <p className="text-xs text-white/60">
                  Tüm modeller, servisler, provider'lar ve ekranlar tek bir derlenebilir dosyada birleştirildi.
                </p>
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2 self-start md:self-auto">
            <button
              onClick={handleCopy}
              className="flex items-center gap-1.5 px-4 py-2 rounded-xl bg-white/10 hover:bg-white/15 text-white font-medium text-xs transition cursor-pointer"
            >
              {copied ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
              <span>{copied ? 'Kopyalandı!' : 'Kodu Kopyala'}</span>
            </button>

            <button
              onClick={handleDownload}
              className="flex items-center gap-1.5 px-4 py-2 rounded-xl bg-[#9EA7FC] hover:bg-[#b2b8fe] text-[#13131A] font-bold text-xs transition cursor-pointer shadow-md"
            >
              <Download className="w-4 h-4" />
              <span>main.dart İndir</span>
            </button>
          </div>
        </div>

        {/* 4 Düzeltilen Unsur Kontrol Listesi */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-6 pt-5 border-t border-white/10 text-xs">
          <div className="flex items-start gap-2.5 p-3 rounded-xl bg-[#13131A]/60 border border-white/5">
            <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
            <div>
              <strong className="text-white block">1. Tanımsız İkon Düzeltildi</strong>
              <span className="text-white/50">
                Tanımsız <code className="text-amber-300">Icons.git_branch</code> yerine Material uyumlu <code className="text-emerald-300">Icons.fork_right</code> uygulandı.
              </span>
            </div>
          </div>

          <div className="flex items-start gap-2.5 p-3 rounded-xl bg-[#13131A]/60 border border-white/5">
            <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
            <div>
              <strong className="text-white block">2. Boş / Yeni Repo Desteği</strong>
              <span className="text-white/50">
                Sıfır commit'li repolar için orphan commit ve <code className="text-emerald-300">POST /git/refs</code> ile otomatik dal oluşturma eklendi.
              </span>
            </div>
          </div>

          <div className="flex items-start gap-2.5 p-3 rounded-xl bg-[#13131A]/60 border border-white/5">
            <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
            <div>
              <strong className="text-white block">3. Otomatik Kök Klasör Temizliği</strong>
              <span className="text-white/50">
                ZIP içi gereksiz ana kök dizini sıyıran <code className="text-emerald-300">_detectCommonRoot()</code> mantığı eklendi.
              </span>
            </div>
          </div>

          <div className="flex items-start gap-2.5 p-3 rounded-xl bg-[#13131A]/60 border border-white/5">
            <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
            <div>
              <strong className="text-white block">4. Sıfır Tekrar & %100 Uyum</strong>
              <span className="text-white/50">
                AuthProvider, RepoProvider, UploadProvider ve modeller eksiksiz birbirine bağlandı, mükerrer tanımlar elendi.
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Code Display Container */}
      <div className="bg-[#13131A] border border-white/10 rounded-2xl overflow-hidden shadow-2xl">
        <div className="px-4 py-3 bg-[#181824] border-b border-white/10 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="w-3 h-3 rounded-full bg-red-500/80 inline-block" />
            <span className="w-3 h-3 rounded-full bg-yellow-500/80 inline-block" />
            <span className="w-3 h-3 rounded-full bg-green-500/80 inline-block" />
            <span className="text-xs font-mono text-white/50 ml-2">lib/main.dart (Tek Dosya Tam Sürüm)</span>
          </div>
          <span className="text-[11px] text-white/40 font-mono">Dart 3.x / Flutter 3.x</span>
        </div>

        <div className="p-4 max-h-[600px] overflow-auto">
          <pre className="text-xs font-mono text-white/90 leading-relaxed">
            <code>{UNIFIED_DART_CODE}</code>
          </pre>
        </div>
      </div>
    </div>
  );
};
