/**
 * Gizli bilgilerin yanlışlıkla repoya gönderilmesini engelleyen son savunma hattı.
 * Yalnızca yüksek güvenilirlikli eşleşmeleri yakalar (yanlış alarm düşük tutulur).
 */
import { GitFile } from '../types';

const SAFE_ENV_SUFFIX = /\.(example|sample|template|dist|defaults?)$/i;

function isSensitiveFileName(path: string): boolean {
  const base = (path.split('/').pop() || '').toLowerCase();
  if (/^\.env(\..+)?$/.test(base)) return !SAFE_ENV_SUFFIX.test(base);
  if (/\.(pem|p12|pfx|jks|keystore|ppk)$/.test(base)) return true;
  if (/^id_(rsa|dsa|ecdsa|ed25519)$/.test(base)) return true;
  if (base === 'key.properties' || base === '.netrc' || base === '.pgpass') return true;
  if (/^(service-?account|credentials?)[\w.-]*\.json$/.test(base)) return true;
  return false;
}

const SECRET_PATTERNS: Array<{ name: string; re: RegExp }> = [
  { name: 'GitHub token', re: /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b/ },
  { name: 'GitHub fine-grained token', re: /\bgithub_pat_[A-Za-z0-9_]{50,}\b/ },
  { name: 'AWS access key', re: /\bAKIA[0-9A-Z]{16}\b/ },
  { name: 'Google API key', re: /\bAIza[0-9A-Za-z_-]{35}\b/ },
  { name: 'Anthropic API key', re: /\bsk-ant-[A-Za-z0-9_-]{20,}\b/ },
  { name: 'Slack token', re: /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/ },
  { name: 'Özel anahtar (private key)', re: /-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----/ },
];

const MAX_SCAN_BYTES = 2 * 1024 * 1024;

export interface SecretFinding {
  path: string;
  reason: string;
}

export function findSecrets(files: Array<{ path: string; file: GitFile }>): SecretFinding[] {
  const findings: SecretFinding[] = [];
  const decoder = new TextDecoder('utf-8', { fatal: false });

  for (const { path, file } of files) {
    if (isSensitiveFileName(path)) {
      findings.push({ path, reason: 'Hassas dosya adı' });
      continue;
    }
    if (!file.isText || file.content.byteLength > MAX_SCAN_BYTES) continue;
    const text = decoder.decode(file.content);
    const hit = SECRET_PATTERNS.find((p) => p.re.test(text));
    if (hit) findings.push({ path, reason: hit.name });
  }
  return findings;
}

export function formatSecretError(findings: SecretFinding[]): string {
  const shown = findings
    .slice(0, 5)
    .map((f) => `${f.path} (${f.reason})`)
    .join(', ');
  const more = findings.length > 5 ? ` ve ${findings.length - 5} dosya daha` : '';
  return (
    `Gizli bilgi içerebilecek dosya(lar) tespit edildi, push engellendi: ${shown}${more}. ` +
    'Bu dosyaları listeden çıkarın veya içindeki anahtarları kaldırıp tekrar deneyin.'
  );
}
