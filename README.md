# UsageBar

Minimal macOS menu bar app for checking AI provider usage at a glance.

It currently shows usage for:

- Codex
- Claude
- Cursor

The app is intentionally small: a native Swift menu bar item, periodic refreshes, basic provider status, and a manual Cursor token prompt.

## Build

```sh
swift build
```

## Bundle

```sh
./scripts/bundle.sh
open UsageBar.app
```

The app is ad-hoc signed. macOS may require right-clicking the app and choosing **Open** the first time.

## Release

Create and push a version tag:

```sh
git tag -a v1.0.0 -m "UsageBar v1.0.0"
git push origin v1.0.0
```

GitHub Actions will build the app, zip it, and attach it to a GitHub Release.
