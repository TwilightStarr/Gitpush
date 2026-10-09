<p align="center">
  <img src="assets/icon/icon.svg" width="110" alt="Gitpush logo">
</p>

<h1 align="center">Gitpush</h1>

<p align="center">
  <b>Push files to GitHub and manage your repos from your phone, safely.</b><br>
  No computer, no terminal, no <code>git</code> commands.
</p>

<p align="center">
  <a href="README.md">Türkçe</a> · <b>English</b>
</p>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-1.2.1-blue">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green"></a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-Android-02569B?logo=flutter&logoColor=white">
  <img alt="React" src="https://img.shields.io/badge/Web-React%20%2B%20Vite-61DAFB?logo=react&logoColor=black">
  <a href="https://github.com/TwilightStarr/Gitpush/actions/workflows/test.yml"><img alt="Tests" src="https://github.com/TwilightStarr/Gitpush/actions/workflows/test.yml/badge.svg"></a>
</p>

---

Gitpush is a mobile Git client that lets you **send files or a ZIP to a GitHub repository without writing code**, browse and edit the repo, and watch GitHub Actions runs. The Android app is written in **Flutter**; the project also includes a **React web UI** built on the same logic.

> The app interface is in Turkish.

## Why Gitpush?

You downloaded a project ZIP on your phone, generated a file with an AI assistant, or need to make a small fix. Normally that takes a computer, a Git install and a few commands. Gitpush does it on one screen, with safety nets:

1. Sign in (token or GitHub Device Flow).
2. Pick a repository and branch.
3. Choose files or a ZIP.
4. Review exactly what will change in the preview, confirm, and it goes out as a single commit.

## Features

### Pushing
- **Atomic push:** multiple files or a ZIP are sent as one commit. If the branch moved in the meantime, nothing is overwritten (`force: false`).
- **Preview and safety net:** new, updated and to-be-deleted files are listed before sending. Deletions need a separate confirmation.
- **Secret scan:** files such as `.env`, private keys, `*.pem`, `*.jks` or known token patterns (GitHub, AWS, Google, Anthropic, Slack) stop the push. Templates like `.env.example` are allowed.

### Repository management
- **Repo browser:** folders first, sorting and search, folder summaries, breadcrumbs, file details and previews.
- **Move, rename, delete:** single, bulk and folder operations are each one commit.
- **In-app editing:** edit text files or create new ones, with an unsaved-changes warning and the same secret scan.
- **Commit history:** per file and per branch, paginated.
- **Repo and branch actions:** create repos, create and delete branches (the default branch is protected), remember the last repo.
- **GitHub Actions:** watch runs and trigger workflows.

### Security and settings
- **Sign-in:** Personal Access Token or GitHub Device Flow.
- **Secure storage:** the token is kept in Android Keystore-backed encrypted storage.
- **PIN lock:** 6-digit PIN stored as a salted hash; wait times grow after failed attempts.
- **Auto sign-out:** the token is wiped if the device is not opened for the number of days you set.
- **Customization:** accent color, AMOLED theme, default commit message, preview options and more.
- **Local history:** a record of your pushes stays on your device only.

See [CHANGES.md](CHANGES.md) for the detailed change log (Turkish) and [SECURITY.md](SECURITY.md) for the security model (Turkish).

## Installation

### Prebuilt APK (GitHub Actions)

The **Build APK** workflow runs on every push to `main`:

1. Open the repository's **Actions** tab.
2. Open the latest **Build APK** run.
3. Download `app-release-apk` from **Artifacts** and install it on your phone.

> **Note:** the APK built in CI is signed with the debug key from the `flutter create` template. Sign it with your own keystore before distributing (see [SECURITY.md](SECURITY.md)).

### Run from source (Flutter)

Requirements: Flutter (Dart `>=3.3.0 <4.0.0`) and an Android device or emulator.

```bash
flutter pub get
flutter create . --platforms=android   # if android/ does not exist
python3 tool/patch_android_manifest.py android/app/src/main/AndroidManifest.xml
flutter run
```

The manifest patch adds the INTERNET permission and sets `allowBackup=false` and `usesCleartextTraffic=false`.

### Sign in with GitHub (Device Flow)

As an alternative to pasting a token you can use the OAuth Device Flow. Only the public **Client ID** is passed at build time; no `client_secret` is needed and one must never be shipped in the client.

```bash
flutter run --dart-define=GITHUB_CLIENT_ID=<client_id>
```

Without a Client ID the "Sign in with GitHub" button is hidden and token sign-in is used.

### Web UI

```bash
npm install      # or: bun install
npm run dev      # http://localhost:3000
```

Use `npm run build` for a production build. In the web version the token is kept in memory only by default; optional persistence is encrypted with your passphrase (AES-256-GCM). Device Flow is not available on the web because of browser CORS restrictions.

## Recommended token permissions

Create a **fine-grained** PAT if possible:

| Action | Permission |
|---|---|
| Push, edit, delete files | `Contents: Read and write` |
| Monitor and trigger Actions | `Actions: Read and write` |

Pick a short expiry. If you suspect a leak, revoke the token right away under GitHub → Settings → Developer settings.

## Project structure

```
lib/
  main.dart        App entry point
  models/          Data models, settings, repo listing logic
  services/        GitHub API, storage, ZIP, app lock, Device Flow
  providers/       Auth, Repo, Upload, Theme, Settings, AppLock
  screens/         Send, repo browser, editor, Actions, settings, lock...
  widgets/ utils/ theme/
src/               React web UI (Vite + Tailwind)
test/              Unit and widget tests
tool/              Unified main.dart generator, manifest patch
assets/icon/       Logo (SVG + 1024 px source PNG)
.github/workflows/ APK build and test workflows
```

## Testing

```bash
flutter analyze
flutter test
```

Tests cover areas such as the secret scan, path validation, ZIP handling, the GitHub service, Device Flow, repo diffing and settings. `test.yml` runs automatically on every push and pull request.

## Unified single file

The `lib/` directory is merged into a single `main.dart` and shown in the web UI's **Flutter Kodu** (Flutter Code) tab:

```bash
node tool/generate_unified_dart.mjs          # regenerate
node tool/generate_unified_dart.mjs --check  # is it in sync?
```

`lib/` is always the source of truth. Do not edit the generated file by hand.

## Security

- The token is only ever sent to `https://api.github.com`.
- `owner`, `repo`, `branch` and workflow names are validated and URL-encoded.
- External links only open for `https` and `github.com` hosts.
- On Android: `allowBackup=false`, `usesCleartextTraffic=false` and `--obfuscate` builds.
- The web build is restricted with a Content-Security-Policy.

If you find a vulnerability, please report it privately to the maintainer instead of opening a public issue. Known remaining risks and recommended HTTP headers are in [SECURITY.md](SECURITY.md).

## License

Released under the [MIT](LICENSE) license.

## Contributing

Bug reports, suggestions and pull requests are welcome. Before opening a PR, make sure `flutter analyze && flutter test` pass and `node tool/generate_unified_dart.mjs --check` reports in sync.
