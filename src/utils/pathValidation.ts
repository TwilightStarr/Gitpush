/**
 * Git path validation and normalization utility
 */

export interface PathValidationResult {
  isValid: boolean;
  error?: string;
  normalizedPath: string;
}

export function normalizeAndValidateGitPath(rawPath: string): PathValidationResult {
  if (!rawPath || !rawPath.trim()) {
    return {
      isValid: false,
      error: 'Dosya yolu boş olamaz.',
      normalizedPath: '',
    };
  }

  // Convert Windows backslashes to forward slashes and trim
  let p = rawPath.trim().replace(/\\/g, '/');

  // Strip leading and trailing slashes
  while (p.startsWith('/')) {
    p = p.slice(1);
  }
  while (p.endsWith('/')) {
    p = p.slice(0, -1);
  }

  // Collapse consecutive slashes
  p = p.replace(/\/+/g, '/');

  if (!p) {
    return {
      isValid: false,
      error: 'Dosya yolu yalnızca eğik çizgilerden oluşamaz.',
      normalizedPath: '',
    };
  }

  // Check for path traversal attempts
  const segments = p.split('/');
  for (const seg of segments) {
    if (seg === '..') {
      return {
        isValid: false,
        error: 'Dosya yolunda ".." (üst dizin yönlendirmesi) kullanılamaz.',
        normalizedPath: p,
      };
    }
    if (seg === '.') {
      return {
        isValid: false,
        error: 'Dosya yolunda geçersiz "." segmenti var.',
        normalizedPath: p,
      };
    }
    // Disallow invalid filename characters
    if (/[\0<>:"|?*\x00-\x1F]/.test(seg)) {
      return {
        isValid: false,
        error: `Dosya adı geçersiz karakterler içeriyor (${seg}).`,
        normalizedPath: p,
      };
    }
  }

  // Max path length safety
  if (p.length > 400) {
    return {
      isValid: false,
      error: 'Dosya yolu 400 karakter sınırını aşıyor.',
      normalizedPath: p,
    };
  }

  return {
    isValid: true,
    normalizedPath: p,
  };
}

export function findDuplicatePaths(paths: string[]): string[] {
  const seen = new Set<string>();
  const duplicates = new Set<string>();

  for (const raw of paths) {
    const norm = normalizeAndValidateGitPath(raw).normalizedPath.toLowerCase();
    if (seen.has(norm)) {
      duplicates.add(norm);
    } else {
      seen.add(norm);
    }
  }

  return Array.from(duplicates);
}
