// lib/ altındaki tüm Dart dosyalarını tek bir main.dart'ta birleştirir ve şu iki
// kopyayı üretir:
//   - public/gitpush_unified_main.dart
//   - src/services/flutterCode.ts  (React arayüzündeki "Flutter Kodu" sekmesi)
//
// Kullanım:
//   node tool/generate_unified_dart.mjs          -> dosyaları yeniden üretir
//   node tool/generate_unified_dart.mjs --check  -> senkron değilse hata kodu 1 ile çıkar
//
// Kaynak gerçek her zaman lib/'dir; üretilen dosyaları elle düzenlemeyin.

import { readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const LIB = 'lib';
const OUT_DART = 'public/gitpush_unified_main.dart';
const OUT_TS = 'src/services/flutterCode.ts';
const checkOnly = process.argv.includes('--check');

// Tek kütüphanede birleştirilince çakışabilecek içe aktarmalar daraltılır.
// (dart:ui tamamı Flutter'ın TextStyle/Image vb. adlarıyla, dart:io ise
// Link/File vb. adlarla çakışabilir.)
const IMPORT_OVERRIDES = new Map([
  ["import 'dart:ui';", "import 'dart:ui' show FlutterView;"],
  ["import 'dart:io';", "import 'dart:io' show File, SocketException, HandshakeException;"],
]);

const SECTION_ORDER = [
  ['models', '1. MODELLER (MODELS)'],
  ['utils', '2. YARDIMCILAR (UTILS)'],
  ['theme', '3. TEMA (THEME)'],
  ['services', '4. SERVİSLER (SERVICES)'],
  ['providers', '5. SAĞLAYICILAR (PROVIDERS)'],
  ['widgets', '6. BİLEŞENLER (WIDGETS)'],
  ['screens', '7. EKRANLAR (SCREENS)'],
  ['', '8. GİRİŞ NOKTASI (MAIN)'],
];

function walk(dir, out = []) {
  for (const name of readdirSync(dir).sort()) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (name.endsWith('.dart')) out.push(p);
  }
  return out;
}

function sectionOf(path) {
  const rel = relative(LIB, path).replace(/\\/g, '/');
  const top = rel.includes('/') ? rel.split('/')[0] : '';
  return top;
}

const files = walk(LIB);
const externalImports = new Set();
const bodiesBySection = new Map(SECTION_ORDER.map(([k]) => [k, []]));
const declared = new Map(); // ad -> dosya

const declRe = [
  /^(?:abstract\s+|sealed\s+|base\s+|final\s+)*(?:class|enum|mixin|extension type|extension)\s+(\w+)/,
  /^(?:typedef)\s+(\w+)/,
  /^(?:final|const|var)\s+(?:[\w<>?,\s]+?\s+)?(\w+)\s*=/,
  /^(?:Future<[^>]*>|Future|void|bool|int|double|String|List<[^>]*>|Map<[^>]*>|Set<[^>]*>|[A-Z]\w*)\??\s+(\w+)\s*\(/,
];

for (const path of files) {
  const rel = relative('.', path).replace(/\\/g, '/');
  const lines = readFileSync(path, 'utf-8').replace(/\r\n/g, '\n').split('\n');
  const kept = [];
  for (const line of lines) {
    const m = line.match(/^import\s+['"]([^'"]+)['"][^;]*;\s*$/);
    if (m) {
      const target = m[1];
      const isRelative = !target.startsWith('dart:') && !target.startsWith('package:');
      const isOwnPackage = target.startsWith('package:gitpush/');
      if (isRelative || isOwnPackage) continue; // birleşik dosyada gereksiz
      const normalized = line.trim();
      externalImports.add(IMPORT_OVERRIDES.get(normalized) ?? normalized);
      continue;
    }
    if (/^(export|part|library)\s/.test(line)) {
      throw new Error(`${rel}: export/part/library birleştirmeyle uyumsuz: ${line}`);
    }
    kept.push(line);
    for (const re of declRe) {
      const d = line.match(re);
      if (d && d[1] !== 'main') {
        if (declared.has(d[1]) && declared.get(d[1]) !== rel) {
          throw new Error(`Çakışan üst düzey ad "${d[1]}": ${declared.get(d[1])} ve ${rel}`);
        }
        declared.set(d[1], rel);
        break;
      }
    }
  }
  const body = kept.join('\n').replace(/^\n+/, '').replace(/\s+$/, '');
  const section = sectionOf(path);
  if (!bodiesBySection.has(section)) throw new Error(`Bilinmeyen lib alt klasörü: ${section} (${rel}). Eski/silinmiş bir dosya kalmış olabilir: 'bash tool/cleanup_removed.sh' çalıştırın.`);
  bodiesBySection.get(section).push({ rel, body });
}

const dartImports = [...externalImports].filter((l) => l.includes("'dart:")).sort();
const pkgImports = [...externalImports].filter((l) => l.includes("'package:")).sort();

const bar = '// ' + '='.repeat(77);
let out = `${bar}
// GITPUSH - TEK DOSYA BİRLEŞİK FLUTTER UYGULAMASI (main.dart)
${bar}
// BU DOSYA OTOMATİK ÜRETİLİR: \`node tool/generate_unified_dart.mjs\`
// Kaynak gerçek lib/ klasörüdür; burada yapılan elle değişiklikler kaybolur.
// Tüm modeller, servisler, sağlayıcılar, bileşenler ve ekranlar tek kütüphanede
// birleştirilmiştir (${files.length} dosya).
${bar}

${dartImports.join('\n')}
${pkgImports.join('\n')}
`;

for (const [key, title] of SECTION_ORDER) {
  const entries = bodiesBySection.get(key);
  if (!entries.length) continue;
  out += `\n${bar}\n// ${title}\n${bar}\n`;
  for (const { rel, body } of entries) {
    out += `\n// --- ${rel} ---\n${body}\n`;
  }
}

const dartText = out;
const escaped = dartText.replace(/\\/g, '\\\\').replace(/`/g, '\\`').replace(/\$\{/g, '\\${');
const tsText = `// BU DOSYA OTOMATİK ÜRETİLİR: \`node tool/generate_unified_dart.mjs\`\nexport const UNIFIED_DART_CODE = \`${escaped}\`;\n`;

function read(p) {
  try {
    return readFileSync(p, 'utf-8');
  } catch {
    return null;
  }
}

if (checkOnly) {
  const stale = [];
  if (read(OUT_DART) !== dartText) stale.push(OUT_DART);
  if (read(OUT_TS) !== tsText) stale.push(OUT_TS);
  if (stale.length) {
    console.error('lib/ ile senkron DEĞİL:\n  - ' + stale.join('\n  - '));
    console.error('\nÇözüm: node tool/generate_unified_dart.mjs');
    process.exit(1);
  }
  console.log('✓ Birleşik main.dart ve flutterCode.ts, lib/ ile senkron.');
} else {
  writeFileSync(OUT_DART, dartText, 'utf-8');
  writeFileSync(OUT_TS, tsText, 'utf-8');
  console.log(`Üretildi: ${OUT_DART} ve ${OUT_TS} (${files.length} dosya, ${declared.size} üst düzey ad).`);
}
