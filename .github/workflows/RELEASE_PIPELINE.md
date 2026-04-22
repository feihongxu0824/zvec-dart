# Zvec Release Pipeline

## Overview

All three workflows are **manually triggered** (`workflow_dispatch`) for maximum control.
Each step requires human verification before proceeding to the next.

## Pipeline Flow

```
  git tag v0.1.0 && git push origin v0.1.0
                    |
                    v
  ┌─────────────────────────────────────────────────────────┐
  │  Workflow #1: Build & Release Native Libs               │
  │  File: 1-build-and-release.yml                          │
  │                                                         │
  │  ┌─ macOS-14 runner ──────────────────────────────────┐  │
  │  │  1. Checkout (with git submodules)                 │  │
  │  │  2. Build Android arm64-v8a   → libzvec.so         │  │
  │  │  3. Build Android armeabi-v7a → libzvec.so         │  │
  │  │  4. Build iOS arm64           → zvec.framework     │  │
  │  │  5. Package zips              → build/release/     │  │
  │  │  6. gh release create v0.1.0  → upload zips        │  │
  │  └────────────────────────────────────────────────────┘  │
  │                                                         │
  │  Output: GitHub Release with 3 zip files                │
  │    - libzvec-android-arm64-v8a.zip                      │
  │    - libzvec-android-armeabi-v7a.zip                    │
  │    - zvec-framework-ios.zip                             │
  └─────────────────────────────────────────────────────────┘
                    |
          ✅ Verify: GitHub Release page shows all 3 zips
                    |
                    v
  ┌─────────────────────────────────────────────────────────┐
  │  Workflow #2: Publish to pub.dev                        │
  │  File: 2-publish-pub-dev.yml                            │
  │                                                         │
  │  ┌─ ubuntu-latest runner ─────────────────────────────┐  │
  │  │  1. Verify version (pubspec.yaml == input)         │  │
  │  │  2. Verify GitHub Release exists                   │  │
  │  │  3. dart pub publish --dry-run                     │  │
  │  │  4. dart pub publish --force (OIDC auth)           │  │
  │  └────────────────────────────────────────────────────┘  │
  │                                                         │
  │  Output: Package live on pub.dev                        │
  │  Auth: GitHub OIDC token (no secrets needed)            │
  └─────────────────────────────────────────────────────────┘
                    |
          ✅ Verify: pub.dev/packages/zvec shows new version
                    |
                    v
  ┌─────────────────────────────────────────────────────────┐
  │  Workflow #3: Verify Published Package                  │
  │  File: 3-verify-package.yml                             │
  │                                                         │
  │  ┌─ verify-android (ubuntu-latest) ───────────────────┐  │
  │  │  1. flutter create test_app                        │  │
  │  │  2. flutter pub add zvec:0.1.0                     │  │
  │  │  3. flutter build apk --debug                      │  │
  │  │  4. Check: libzvec.so exists in APK                │  │
  │  └────────────────────────────────────────────────────┘  │
  │                                                         │
  │  ┌─ verify-ios (macos-14) ────────────────────────────┐  │
  │  │  1. flutter create test_app                        │  │
  │  │  2. flutter pub add zvec:0.1.0                     │  │
  │  │  3. flutter build ios --no-codesign                │  │
  │  │  4. Check: zvec.framework exists in build          │  │
  │  └────────────────────────────────────────────────────┘  │
  │                                                         │
  │  Output: ✅ Both platforms verified                     │
  └─────────────────────────────────────────────────────────┘
```

## Prerequisites

### One-time setup on pub.dev

1. Go to `pub.dev/packages/zvec/admin`
2. Enable **Automated publishing from GitHub Actions**
3. Set repository: `zvec-ai/zvec-dart`
4. Set tag pattern: `v{{version}}`

### Version checklist before release

- [ ] Update `version` in `pubspec.yaml`
- [ ] Update `ZVEC_VERSION` in `android/build.gradle`
- [ ] Update `s.version` in `ios/zvec.podspec`
- [ ] Update `CHANGELOG.md`
- [ ] Commit and push to main
- [ ] Create and push git tag: `git tag v<version> && git push origin v<version>`

## Quick Commands

```bash
# Full release (after version bump and tag push)
# 1. Go to GitHub Actions → "1 - Build & Release" → Run workflow
# 2. Go to GitHub Actions → "2 - Publish to pub.dev" → Run workflow
# 3. Go to GitHub Actions → "3 - Verify Published Package" → Run workflow
```
