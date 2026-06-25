# WalkAway Release Checklist

## Current v0 Settings

- App name: `WalkAway`
- Bundle ID: `com.fizday.walkaway`
- Version: `0.1.0`
- Build: `1`
- Signing identity: `Developer ID Application: Fizday Tech (OPC) Private Limited (BSX8KAUXDZ)`
- Distribution artifact: `dist/release/WalkAway-0.1.0.dmg`

## Build A Release

```bash
./script/package_release.sh
```

The script:

1. Builds the release binary.
2. Stages `WalkAway.app`.
3. Signs the app with Developer ID and hardened runtime.
4. Creates `WalkAway-0.1.0.zip`.
5. Creates and signs `WalkAway-0.1.0.dmg`.
6. Notarizes and staples the DMG when `FizdayNotaryProfile` exists.

## Notarization Setup

Before sharing outside trusted local testing, store Apple notarization credentials
in the local keychain:

```bash
xcrun notarytool store-credentials "FizdayNotaryProfile" \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "BSX8KAUXDZ" \
  --password "APP_SPECIFIC_PASSWORD"
```

Use an Apple app-specific password, not the normal Apple Account password.

After the profile is stored, rerun:

```bash
./script/package_release.sh
```

Expected final checks:

```bash
spctl -a -vv -t open --context context:primary-signature dist/release/WalkAway-0.1.0.dmg
spctl -a -vv dist/release/WalkAway.app
```

Both should be accepted after notarization is complete and stapled.

## Universal Builds

The script tries to build a universal Apple Silicon + Intel binary when full
Xcode tooling is available. If the machine only has Command Line Tools selected,
it falls back to the current architecture for v0 testing.

Before public website distribution, install/select full Xcode and verify the app
binary is universal:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
./script/package_release.sh
lipo -info dist/release/WalkAway.app/Contents/MacOS/WalkAway
```

Expected:

```text
Architectures in the fat file: WalkAway are: x86_64 arm64
```
