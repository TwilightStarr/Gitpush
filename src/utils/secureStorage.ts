/**
 * Token saklama yardımcıları.
 *
 * Güvenlik modeli:
 *  - "memory": Token yalnızca React state'inde (RAM) tutulur. Sayfa yenilenince
 *    silinir. Hiçbir Web Storage alanına yazılmaz. (Varsayılan)
 *  - "encrypted": Token, kullanıcının belirlediği parolayla AES-GCM (PBKDF2-SHA256
 *    ile türetilmiş anahtar) kullanılarak şifrelenir ve localStorage'a yalnızca
 *    ŞİFRELİ olarak yazılır. Parola hiçbir yerde saklanmaz.
 *
 * Eski sürümlerin düz metin `gitpush_pat` kayıtları açılışta silinir.
 */

export type StorageType = 'memory' | 'encrypted';

const LEGACY_KEYS = ['gitpush_pat', 'gitpush_login'];
const ENC_KEY = 'gitpush_pat_enc_v1';
const ENC_LOGIN_KEY = 'gitpush_login_hint';

const PBKDF2_ITERATIONS = 600_000;
export const MIN_PASSPHRASE_LENGTH = 10;

/** Yazdırılabilir ASCII, boşluksuz, makul uzunluk (header enjeksiyonunu engeller). */
const TOKEN_RE = /^[\x21-\x7E]{1,255}$/;

export function isPlausibleToken(token: string): boolean {
  return TOKEN_RE.test(token);
}

export function assertValidToken(token: string): void {
  if (!isPlausibleToken(token)) {
    throw new Error(
      'Token geçersiz karakterler içeriyor (boşluk, satır sonu veya ASCII dışı karakter olamaz).'
    );
  }
}

/** Önceki sürümlerin düz metin token kayıtlarını her iki depodan da siler. */
export function purgeLegacyPlaintext(): void {
  try {
    for (const k of LEGACY_KEYS) {
      window.localStorage.removeItem(k);
      window.sessionStorage.removeItem(k);
    }
  } catch {
    /* depo erişilemez olabilir (gizli mod vb.) */
  }
}

export function hasEncryptedToken(): boolean {
  try {
    return !!window.localStorage.getItem(ENC_KEY);
  } catch {
    return false;
  }
}

export function getEncryptedLoginHint(): string | null {
  try {
    return window.localStorage.getItem(ENC_LOGIN_KEY);
  } catch {
    return null;
  }
}

export function clearEncryptedToken(): void {
  try {
    window.localStorage.removeItem(ENC_KEY);
    window.localStorage.removeItem(ENC_LOGIN_KEY);
  } catch {
    /* yoksay */
  }
}

// ---------------------------------------------------------------------------
// Şifreleme
// ---------------------------------------------------------------------------

function requireSubtle(): SubtleCrypto {
  const subtle = globalThis.crypto?.subtle;
  if (!subtle) {
    throw new Error(
      'Şifreli saklama için güvenli bağlantı (HTTPS) gerekli. Oturumluk (bellek) modunu kullanın.'
    );
  }
  return subtle;
}

function toB64(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

function fromB64(b64: string): Uint8Array<ArrayBuffer> {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function deriveKey(
  passphrase: string,
  salt: Uint8Array<ArrayBuffer>,
  iterations: number
): Promise<CryptoKey> {
  const subtle = requireSubtle();
  const material = await subtle.importKey(
    'raw',
    new TextEncoder().encode(passphrase),
    'PBKDF2',
    false,
    ['deriveKey']
  );
  return subtle.deriveKey(
    { name: 'PBKDF2', salt, iterations, hash: 'SHA-256' },
    material,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt']
  );
}

export async function saveEncryptedToken(
  token: string,
  login: string,
  passphrase: string
): Promise<void> {
  assertValidToken(token);
  if (passphrase.length < MIN_PASSPHRASE_LENGTH) {
    throw new Error(`Parola en az ${MIN_PASSPHRASE_LENGTH} karakter olmalı.`);
  }
  const subtle = requireSubtle();
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await deriveKey(passphrase, salt, PBKDF2_ITERATIONS);
  const ct = await subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    new TextEncoder().encode(token)
  );
  const blob = {
    v: 1,
    iter: PBKDF2_ITERATIONS,
    salt: toB64(salt),
    iv: toB64(iv),
    ct: toB64(new Uint8Array(ct)),
  };
  window.localStorage.setItem(ENC_KEY, JSON.stringify(blob));
  window.localStorage.setItem(ENC_LOGIN_KEY, login);
}

export async function loadEncryptedToken(passphrase: string): Promise<string> {
  const raw = window.localStorage.getItem(ENC_KEY);
  if (!raw) throw new Error('Kayıtlı şifreli token bulunamadı.');

  let blob: { v: number; iter: number; salt: string; iv: string; ct: string };
  try {
    blob = JSON.parse(raw);
  } catch {
    clearEncryptedToken();
    throw new Error('Kayıtlı token bozuk; silindi. Lütfen yeniden girin.');
  }
  if (blob.v !== 1 || !Number.isInteger(blob.iter) || blob.iter < 100_000 || blob.iter > 5_000_000) {
    clearEncryptedToken();
    throw new Error('Kayıtlı token biçimi tanınmadı; silindi. Lütfen yeniden girin.');
  }

  try {
    const key = await deriveKey(passphrase, fromB64(blob.salt), blob.iter);
    const pt = await requireSubtle().decrypt(
      { name: 'AES-GCM', iv: fromB64(blob.iv) },
      key,
      fromB64(blob.ct)
    );
    const token = new TextDecoder().decode(pt);
    assertValidToken(token);
    return token;
  } catch {
    throw new Error('Parola yanlış veya kayıt bozulmuş.');
  }
}
