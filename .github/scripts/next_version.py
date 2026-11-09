#!/usr/bin/env python3
"""Otomatik anlamsal sürüm (SemVer) hesaplayıcı.

Son "vX.Y.Z" etiketinden bu yana atılan commit mesajlarına ve değişen dosyalara bakarak
bir sonraki sürümü hesaplar. Her sayının bir anlamı vardır:

  MAJOR (1.x.x)  Yalnızca kullanıcı bilerek isterse artar:
                   - commit mesajında [major]
                   - başlıkta ünlem:  feat!: ...   (Conventional Commits)
                   - mesaj gövdesinde "BREAKING CHANGE: ..."
  MINOR (x.1.x)  Yeni özellik:  feat: / feature: / özellik: / yeni:   (veya [minor])
                 -> MINOR artar, PATCH sıfırlanır.
  PATCH (x.x.1)  Düzeltme / iyileştirme: fix: / perf: / refactor: / security: / revert: / düzeltme: / hata:
                 ve ÖNEKSİZ commit mesajları ("Update files", "Add x" gibi, uygulamanın varsayılanları).
  (artış yok)    docs: / chore: / ci: / test: / style: ya da [skip release] içeren commit'ler.

Ek kural: Son sürümden bu yana uygulamayı etkileyen hiçbir dosya (app/, gradle*, *.kts) değişmediyse
(yalnızca README, workflow vb.) sürüm artmaz ve release yayımlanmaz. [major] bu kuralı aşar.

Etiket yoksa (ilk çalışma) version.properties içindeki BASE_VERSION olduğu gibi yayımlanır.

Çıktılar GITHUB_OUTPUT'a yazılır: release (true/false), version, tag, bump, reason.
Sürüm notları release-notes.md dosyasına yazılır.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
HEADER_RE = re.compile(r"^(?P<type>[^\W\d_]+)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?:\s*(?P<desc>.+)$")

MINOR_TYPES = {"feat", "feature", "özellik", "ozellik", "yeni"}
PATCH_TYPES = {"fix", "bugfix", "hotfix", "düzeltme", "duzeltme", "hata",
               "perf", "refactor", "security", "revert"}
NONE_TYPES = {"docs", "doc", "chore", "ci", "test", "tests", "style"}

# Bu yollardan biri değiştiyse APK etkilenebilir -> sürüm artışı anlamlıdır.
APP_PATHS = ("app/", "gradle/", "build.gradle.kts", "settings.gradle.kts", "gradle.properties")

RANK = {"none": 0, "patch": 1, "minor": 2, "major": 3}
MAX_BOOTSTRAP_NOTES = 30


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True,
                          text=True, encoding="utf-8").stdout.strip()


def latest_tag() -> tuple[tuple[int, int, int], str] | None:
    best = None
    for tag in git("tag", "--list", "v*", "--merged", "HEAD").splitlines():
        m = TAG_RE.match(tag.strip())
        if m:
            ver = tuple(int(x) for x in m.groups())
            if best is None or ver > best[0]:
                best = (ver, tag.strip())
    return best


def base_version() -> tuple[int, int, int]:
    text = (ROOT / "version.properties").read_text(encoding="utf-8")
    m = re.search(r"^\s*BASE_VERSION\s*=\s*(\d+)\.(\d+)\.(\d+)\s*$", text, re.M)
    if not m:
        sys.exit("version.properties içinde geçerli bir BASE_VERSION=X.Y.Z bulunamadı")
    return tuple(int(x) for x in m.groups())  # type: ignore[return-value]


def read_commits(rev_range: str, limit: int | None = None) -> list[tuple[str, str]]:
    args = ["log", "--no-merges", "--format=%H%x1f%B%x1e"]
    if limit:
        args.append(f"--max-count={limit}")
    args.append(rev_range)
    out = git(*args)
    commits = []
    for chunk in out.split("\x1e"):
        chunk = chunk.strip()
        if not chunk:
            continue
        sha, _, msg = chunk.partition("\x1f")
        commits.append((sha.strip(), msg.strip()))
    return commits


def classify(message: str) -> tuple[str, str, str]:
    """-> (düzey, tür, notlarda gösterilecek açıklama). Düzey: major/minor/patch/none."""
    subject = message.splitlines()[0].strip() if message.strip() else ""
    low = message.lower()
    m = HEADER_RE.match(subject)
    ctype = m.group("type").lower() if m else ""
    known = ctype in MINOR_TYPES | PATCH_TYPES | NONE_TYPES
    desc = m.group("desc").strip() if (m and known) else subject
    scope = (m.group("scope") or "").strip() if (m and known) else ""
    if scope:
        desc = f"**{scope}:** {desc}"

    if "[skip release]" in low or "[no-release]" in low:
        return "none", "other", desc
    breaking = (
        "[major]" in low
        or bool(m and m.group("bang") and known)
        or bool(re.search(r"^breaking[ -]change:", message, re.I | re.M))
    )
    if breaking:
        return "major", "breaking", desc
    if ctype in MINOR_TYPES or "[minor]" in low:
        return "minor", "feat", desc
    if ctype in NONE_TYPES:
        return "none", "other", desc
    if ctype in PATCH_TYPES or "[patch]" in low:
        return "patch", "fix", desc
    return "patch", "other", desc  # önekli/öneksiz tanınmayan mesajlar: küçük değişiklik


def bump(ver: tuple[int, int, int], level: str) -> tuple[int, int, int]:
    major, minor, patch = ver
    if level == "major":
        return major + 1, 0, 0
    if level == "minor":
        return major, minor + 1, 0
    return major, minor, patch + 1


def fmt(ver: tuple[int, int, int]) -> str:
    return ".".join(map(str, ver))


def build_notes(tag: str, level_label: str, commits: list[tuple[str, str]], prev_tag: str | None) -> str:
    groups = {"breaking": [], "feat": [], "fix": [], "other": []}
    for sha, msg in commits:
        level, kind, desc = classify(msg)
        if level == "none" or not desc:
            continue
        groups[kind].append(f"- {desc} (`{sha[:7]}`)")
    titles = [
        ("breaking", "⚠️ Büyük değişiklikler"),
        ("feat", "✨ Yeni özellikler"),
        ("fix", "🐛 Düzeltmeler ve iyileştirmeler"),
        ("other", "🔧 Diğer değişiklikler"),
    ]
    lines = [f"## Gitpush {tag}", "", level_label, ""]
    for key, title in titles:
        if groups[key]:
            lines += [f"### {title}", *groups[key], ""]
    repo = os.environ.get("GITHUB_REPOSITORY")
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    if repo and prev_tag:
        lines.append(f"**Tüm değişiklikler:** {server}/{repo}/compare/{prev_tag}...{tag}")
    return "\n".join(lines).rstrip() + "\n"


def emit(outputs: dict[str, str], summary: str) -> None:
    for k, v in outputs.items():
        print(f"{k}={v}")
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            for k, v in outputs.items():
                fh.write(f"{k}={v}\n")
    spath = os.environ.get("GITHUB_STEP_SUMMARY")
    if spath:
        with open(spath, "a", encoding="utf-8") as fh:
            fh.write(summary + "\n")


def main() -> None:
    head = git("rev-parse", "HEAD")
    short = head[:7]
    last = latest_tag()
    notes_path = ROOT / "release-notes.md"

    # --- İlk çalışma: etiket yok -> tabanı olduğu gibi yayımla -------------------------------
    if last is None:
        ver = base_version()
        tag = f"v{fmt(ver)}"
        commits = read_commits("HEAD", limit=MAX_BOOTSTRAP_NOTES)
        notes_path.write_text(
            build_notes(tag, "İlk otomatik sürüm. Bundan sonraki sürümler commit mesajlarından hesaplanır.",
                        commits, None), encoding="utf-8")
        emit({"release": "true", "version": fmt(ver), "tag": tag, "bump": "initial",
              "reason": "ilk-surum"},
             f"### 📦 Sürüm: `{tag}` (ilk otomatik sürüm)")
        return

    last_ver, last_tag = last
    commits = read_commits(f"{last_tag}..HEAD")
    dev_version = f"{fmt(last_ver)}-dev.{short}"

    def no_release(reason_key: str, reason_text: str) -> None:
        emit({"release": "false", "version": dev_version, "tag": "", "bump": "none",
              "reason": reason_key},
             f"### ⏭️ Release yok\nSon sürüm `{last_tag}`. {reason_text}")

    if not commits:
        return no_release("yeni-commit-yok", f"`{last_tag}` etiketinden bu yana yeni commit yok.")

    level = max((classify(msg)[0] for _, msg in commits), key=RANK.get)
    if level == "none":
        return no_release("sadece-docs-chore",
                          "Yeni commit'lerin hepsi docs/chore/ci/test/style türünde ya da [skip release] içeriyor.")

    changed = git("diff", "--name-only", f"{last_tag}..HEAD").splitlines()
    app_changed = any(f.startswith(APP_PATHS) or f in APP_PATHS for f in changed)
    if level != "major" and not app_changed:
        return no_release("uygulama-degismedi",
                          "Uygulamayı etkileyen dosyalarda (app/, gradle) değişiklik yok.")

    new_ver = bump(last_ver, level)
    tag = f"v{fmt(new_ver)}"
    label = {
        "major": "**Büyük sürüm** — geriye dönük uyumsuz değişiklik (elle istendi).",
        "minor": "**Küçük sürüm** — yeni özellik(ler) eklendi.",
        "patch": "**Yama sürümü** — düzeltme ve iyileştirmeler.",
    }[level]
    notes_path.write_text(build_notes(tag, label, commits, last_tag), encoding="utf-8")
    emit({"release": "true", "version": fmt(new_ver), "tag": tag, "bump": level,
          "reason": "ok"},
         f"### 📦 Yeni sürüm: `{last_tag}` → `{tag}` ({level})")


if __name__ == "__main__":
    main()
