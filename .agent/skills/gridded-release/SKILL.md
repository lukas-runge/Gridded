---
name: gridded-release
description: >-
  Bump Gridded macOS app version, commit, tag, build a universal Release app,
  and create a release DMG with pack.sh. Use when the user asks to release,
  bump version, tag a version, build a DMG, or run pack.sh for Gridded.
---

# Gridded Release

Release a new Gridded version. The user supplies the target version (e.g. `0.0.9`). Increment the build number automatically.

## Prerequisites

- macOS with Xcode
- `create-dmg` installed (`brew install create-dmg`)
- Run build and packaging commands outside the sandbox (`required_permissions: ["all"]`)

## Workflow

Copy this checklist and track progress:

```
Release Progress:
- [ ] Step 1: Read current version and build number
- [ ] Step 2: Bump version in project.pbxproj
- [ ] Step 3: Commit and tag
- [ ] Step 4: Build universal Release app
- [ ] Step 5: Stage app bundle and run pack.sh
- [ ] Step 6: Verify artifacts
```

### Step 1: Read current version

Read `Gridded.xcodeproj/project.pbxproj` and note:

- `MARKETING_VERSION` — current semver (e.g. `0.0.8`)
- `CURRENT_PROJECT_VERSION` — current build number (e.g. `15`)

If the user did not give a target version, ask for it before continuing.

Confirm the target version is greater than the current `MARKETING_VERSION`. Abort if the tag already exists (`git tag -l '<version>'`).

### Step 2: Bump version

In `Gridded.xcodeproj/project.pbxproj`, update **both** Debug and Release target configs:

- Set `MARKETING_VERSION` to the user-supplied version
- Set `CURRENT_PROJECT_VERSION` to current build number + 1

Do not change unrelated project settings.

### Step 3: Commit and tag

Only commit when the user explicitly asks (release requests count as explicit).

```bash
git add Gridded.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
chore: bump version to <version>

EOF
)"
git tag <version>
```

Use the bare version as the tag name (e.g. `0.0.9`, not `v0.0.9`).

Do **not** push unless the user asks.

### Step 4: Build universal Release app

From the repo root:

```bash
mkdir -p "builds/<version>/Gridded"

xcodebuild \
  -project Gridded.xcodeproj \
  -scheme Gridded \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build
```

Copy the built app into the release folder:

```bash
/bin/rm -rf "builds/<version>/Gridded/Gridded.app"
/bin/cp -R build/DerivedData/Build/Products/Release/Gridded.app "builds/<version>/Gridded/"
```

Use `/bin/rm` — a bare `rm -rf` may fail in some environments.

### Step 5: Create DMG

```bash
./pack.sh <version>
```

Expected output: `builds/<version>/Gridded-<version>-universal.dmg`

The app bundle inside the DMG is named `Gridded.app`. `pack.sh` detects architecture from the binary (`universal`, `arm64`, or `x86_64`) and includes it in the DMG filename.

### Step 6: Verify

Confirm before reporting success:

```bash
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
  "builds/<version>/Gridded/Gridded.app/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Print CFBundleVersion" \
  "builds/<version>/Gridded/Gridded.app/Contents/Info.plist"

file "builds/<version>/Gridded/Gridded.app/Contents/MacOS/Gridded"
```

Expect:

- `CFBundleShortVersionString` matches the target version
- `CFBundleVersion` matches the incremented build number
- Binary is a universal Mach-O (arm64 + x86_64)
- App bundle is named `Gridded.app`
- `builds/<version>/Gridded-<version>-universal.dmg` exists

## Report to user

Summarize:

- Version and build number
- Commit hash and tag name
- Artifact paths (`builds/<version>/Gridded-<version>-universal.dmg`, `builds/<version>/Gridded/Gridded.app`)
- Push commands only if they may want to publish the tag:

```bash
git push origin main
git push origin <version>
```

The user typically uploads the DMG to GitHub Releases themselves unless they ask otherwise.

## Notes

- Version lives in `Gridded.xcodeproj/project.pbxproj` only (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`). Runtime reads these via generated Info.plist.
- `builds/` is gitignored; artifacts stay local.
- `pack.sh` requires `builds/<version>/Gridded/Gridded.app` to exist before it runs and produces `Gridded-<version>-<architecture>.dmg`.
