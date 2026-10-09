import React, { useState } from 'react';
import { GitHubService } from '../services/github';
import { StorageType, MIN_PASSPHRASE_LENGTH } from '../utils/secureStorage';
import { KeyRound, ExternalLink, X, LogOut, CheckCircle2, AlertCircle, Loader2, Shield, Lock } from 'lucide-react';

export type { StorageType };

interface AuthModalProps {
  isOpen: boolean;
  onClose: () => void;
  token: string;
  userLogin: string | null;
  storageType: StorageType;
  /** Şifreli olarak kayıtlı ama henüz kilidi açılmamış token varsa kullanıcı adı */
  lockedLogin: string | null;
  onSaveToken: (
    token: string,
    login: string,
    storage: StorageType,
    passphrase?: string
  ) => Promise<void>;
  onUnlock: (passphrase: string) => Promise<void>;
  onForgetSaved: () => void;
  onLogout: () => void;
}

export const AuthModal: React.FC<AuthModalProps> = ({
  isOpen,
  onClose,
  token,
  userLogin,
  storageType,
  lockedLogin,
  onSaveToken,
  onUnlock,
  onForgetSaved,
  onLogout,
}) => {
  const [inputToken, setInputToken] = useState('');
  const [passphrase, setPassphrase] = useState('');
  const [selectedStorage, setSelectedStorage] = useState<StorageType>(storageType);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleVerifyAndSave = async (e: React.FormEvent) => {
    e.preventDefault();
    const cleanToken = inputToken.trim();
    if (!cleanToken) {
      setError('Lütfen bir token girin.');
      return;
    }

    if (selectedStorage === 'encrypted' && passphrase.length < MIN_PASSPHRASE_LENGTH) {
      setError(`Şifreli saklama için en az ${MIN_PASSPHRASE_LENGTH} karakterlik bir parola belirleyin.`);
      return;
    }

    try {
      setIsLoading(true);
      setError(null);
      const service = new GitHubService(cleanToken);
      const user = await service.verifyUser();
      await onSaveToken(
        cleanToken,
        user.login,
        selectedStorage,
        selectedStorage === 'encrypted' ? passphrase : undefined
      );
      // Ham token ve parola bileşen state'inden hemen temizlenir
      setInputToken('');
      setPassphrase('');
      onClose();
    } catch (err: any) {
      setError(err.message || 'Token doğrulanamadı. Lütfen izinleri ve doğruluğu kontrol edin.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleUnlock = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!passphrase) {
      setError('Lütfen parolanızı girin.');
      return;
    }
    try {
      setIsLoading(true);
      setError(null);
      await onUnlock(passphrase);
      setPassphrase('');
      onClose();
    } catch (err: any) {
      setError(err.message || 'Kilit açılamadı.');
    } finally {
      setIsLoading(false);
    }
  };

  const maskToken = (t: string) => {
    if (!t) return '';
    if (t.length <= 8) return '••••••••';
    return `${t.slice(0, 4)}••••••••${t.slice(-4)}`;
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-xs animate-in fade-in duration-200">
      <div className="bg-[#1E1E28] border border-white/10 rounded-2xl max-w-md w-full p-6 shadow-2xl relative">
        <button
          onClick={onClose}
          className="absolute top-4 right-4 text-white/50 hover:text-white transition cursor-pointer"
        >
          <X className="w-5 h-5" />
        </button>

        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 rounded-xl bg-[#9EA7FC]/10 border border-[#9EA7FC]/20 flex items-center justify-center text-[#9EA7FC]">
            <KeyRound className="w-5 h-5" />
          </div>
          <div>
            <h3 className="font-bold text-base text-white">GitHub Bağlantısı</h3>
            <p className="text-xs text-white/50">Personal Access Token (PAT) ve Güvenlik</p>
          </div>
        </div>

        {userLogin ? (
          <div className="space-y-4">
            <div className="p-3.5 bg-emerald-500/10 border border-emerald-500/20 rounded-xl flex items-center gap-3">
              <CheckCircle2 className="w-5 h-5 text-emerald-400 shrink-0" />
              <div className="min-w-0 flex-1">
                <p className="text-xs font-semibold text-white">Oturum Açık</p>
                <p className="text-xs text-white/60 font-mono">@{userLogin}</p>
                <p className="text-[11px] text-white/40 font-mono mt-0.5 truncate">
                  Token: {maskToken(token)} ({storageType === 'memory' ? 'Yalnızca bellek' : 'Şifreli kayıt'})
                </p>
              </div>
            </div>

            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => {
                  onLogout();
                  setInputToken('');
                }}
                className="flex-1 flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl border border-red-500/30 text-red-400 hover:bg-red-500/10 text-xs font-semibold transition cursor-pointer"
              >
                <LogOut className="w-4 h-4" />
                <span>Çıkış Yap & Token'ı Sil</span>
              </button>

              <button
                type="button"
                onClick={onClose}
                className="flex-1 py-2 px-3 rounded-xl bg-white/10 hover:bg-white/20 text-white text-xs font-semibold transition cursor-pointer"
              >
                Kapat
              </button>
            </div>
          </div>
        ) : lockedLogin ? (
          <form onSubmit={handleUnlock} className="space-y-4">
            <div className="p-3.5 bg-[#9EA7FC]/10 border border-[#9EA7FC]/20 rounded-xl flex items-center gap-3">
              <Lock className="w-5 h-5 text-[#9EA7FC] shrink-0" />
              <div className="min-w-0 flex-1">
                <p className="text-xs font-semibold text-white">Şifreli token kayıtlı</p>
                <p className="text-xs text-white/60 font-mono">@{lockedLogin}</p>
              </div>
            </div>

            <div>
              <label className="block text-xs font-medium text-white/70 mb-1.5">Parola</label>
              <input
                type="password"
                autoComplete="current-password"
                value={passphrase}
                onChange={(e) => setPassphrase(e.target.value)}
                className="w-full px-3.5 py-2.5 rounded-xl bg-[#13131A] border border-white/10 text-white text-xs focus:outline-hidden focus:border-[#9EA7FC] transition"
              />
            </div>

            {error && (
              <div className="p-3 bg-red-950/40 border border-red-800/40 rounded-xl flex items-center gap-2 text-red-300 text-xs">
                <AlertCircle className="w-4 h-4 shrink-0" />
                <span>{error}</span>
              </div>
            )}

            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => {
                  onForgetSaved();
                  setPassphrase('');
                  setError(null);
                }}
                className="flex-1 py-2 px-3 rounded-xl border border-red-500/30 text-red-400 hover:bg-red-500/10 text-xs font-semibold transition cursor-pointer"
              >
                Kaydı Sil
              </button>
              <button
                type="submit"
                disabled={isLoading || !passphrase}
                className="flex-1 flex items-center justify-center gap-2 py-2 px-3 rounded-xl bg-[#9EA7FC] hover:bg-[#b2b8fe] text-[#13131A] font-bold text-xs transition cursor-pointer disabled:opacity-50"
              >
                {isLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <span>Kilidi Aç</span>}
              </button>
            </div>
          </form>
        ) : (
          <form onSubmit={handleVerifyAndSave} className="space-y-4" autoComplete="off">
            <div>
              <label className="block text-xs font-medium text-white/70 mb-1.5">
                GitHub Personal Access Token (classic veya fine-grained)
              </label>
              <input
                type="password"
                required
                autoComplete="off"
                autoCorrect="off"
                autoCapitalize="off"
                spellCheck={false}
                value={inputToken}
                onChange={(e) => setInputToken(e.target.value)}
                placeholder="ghp_xxxxxxxxxxxxxxxxxxxx"
                className="w-full px-3.5 py-2.5 rounded-xl bg-[#13131A] border border-white/10 text-white text-xs font-mono focus:outline-hidden focus:border-[#9EA7FC] transition"
              />
            </div>

            {/* Storage Preference */}
            <div>
              <label className="block text-xs font-medium text-white/70 mb-1.5 flex items-center gap-1.5">
                <Shield className="w-3.5 h-3.5 text-[#9EA7FC]" />
                Saklama Yöntemi
              </label>
              <div className="grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => setSelectedStorage('memory')}
                  className={`p-2.5 rounded-xl border text-left cursor-pointer transition ${
                    selectedStorage === 'memory'
                      ? 'border-[#9EA7FC] bg-[#9EA7FC]/10 text-white'
                      : 'border-white/10 bg-[#13131A] text-white/60 hover:text-white'
                  }`}
                >
                  <p className="text-xs font-semibold">Yalnızca bellek (Önerilen)</p>
                  <p className="text-[10px] text-white/50 mt-0.5">Hiçbir yere yazılmaz; sayfa yenilenince silinir</p>
                </button>

                <button
                  type="button"
                  onClick={() => setSelectedStorage('encrypted')}
                  className={`p-2.5 rounded-xl border text-left cursor-pointer transition ${
                    selectedStorage === 'encrypted'
                      ? 'border-[#9EA7FC] bg-[#9EA7FC]/10 text-white'
                      : 'border-white/10 bg-[#13131A] text-white/60 hover:text-white'
                  }`}
                >
                  <p className="text-xs font-semibold">Parola ile şifreli kayıt</p>
                  <p className="text-[10px] text-white/50 mt-0.5">AES-256 ile şifrelenir; her açılışta parola sorulur</p>
                </button>
              </div>

              {selectedStorage === 'encrypted' && (
                <div className="mt-2">
                  <input
                    type="password"
                    autoComplete="new-password"
                    value={passphrase}
                    onChange={(e) => setPassphrase(e.target.value)}
                    placeholder={`Parola belirleyin (en az ${MIN_PASSPHRASE_LENGTH} karakter)`}
                    className="w-full px-3.5 py-2.5 rounded-xl bg-[#13131A] border border-white/10 text-white text-xs focus:outline-hidden focus:border-[#9EA7FC] transition"
                  />
                  <p className="text-[10px] text-amber-300/80 mt-1">
                    Parolayı unutursanız token kurtarılamaz; yeniden girmeniz gerekir.
                  </p>
                </div>
              )}
            </div>

            {error && (
              <div className="p-3 bg-red-950/40 border border-red-800/40 rounded-xl flex items-center gap-2 text-red-300 text-xs">
                <AlertCircle className="w-4 h-4 shrink-0" />
                <span>{error}</span>
              </div>
            )}

            <div className="bg-[#13131A] p-3 rounded-xl border border-white/5 text-[11px] text-white/60 space-y-1">
              <p className="font-semibold text-white/80">Gerekli Token İzinleri (Scopes):</p>
              <ul className="list-disc list-inside space-y-0.5 text-white/50 font-mono">
                <li><strong className="text-white/70">repo</strong> (Tüm repo okuma/yazma ve commit)</li>
                <li><strong className="text-white/70">workflow</strong> (Actions kontrolü için opsiyonel)</li>
              </ul>
              <p className="text-[10px] text-white/40 pt-1 border-t border-white/5">
                Token'ınız sunucuya gönderilmez; yalnızca tarayıcınızdan doğrudan GitHub API'ye iletilir.
              </p>
            </div>

            <div className="flex items-center justify-between text-xs pt-1">
              <a
                href="https://github.com/settings/tokens"
                target="_blank"
                rel="noreferrer"
                className="text-[#9EA7FC] hover:underline flex items-center gap-1"
              >
                <span>Token Nasıl Alınır?</span>
                <ExternalLink className="w-3 h-3" />
              </a>
            </div>

            <button
              type="submit"
              disabled={isLoading || !inputToken.trim()}
              className="w-full flex items-center justify-center gap-2 py-2.5 px-4 rounded-xl bg-[#9EA7FC] hover:bg-[#b2b8fe] text-[#13131A] font-bold text-xs transition cursor-pointer shadow-md disabled:opacity-50"
            >
              {isLoading ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>Doğrulanıyor...</span>
                </>
              ) : (
                <span>Doğrula ve Bağlan</span>
              )}
            </button>
          </form>
        )}
      </div>
    </div>
  );
};
