# ShanuSend

A lightweight, LocalSend-protocol-compatible file transfer app — Tauri 2 +
React frontend, Rust protocol core. Built to interoperate with real
[LocalSend](https://localsend.org) clients on the wire (same discovery,
same HTTP transfer API) while staying a fraction of the binary size.

[![CI](https://github.com/OWNER/REPO/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/ci.yml)
[![Release](https://github.com/OWNER/REPO/actions/workflows/release.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/release.yml)

> Replace `OWNER/REPO` above with your actual GitHub path once this is pushed.

## Quick start

```bash
cd core && cargo test          # verify the protocol layer
cd ../app && npm install       # install frontend deps
npm run tauri dev              # run the full app
```

Full setup, troubleshooting, and release-build instructions:
**[docs/BUILD.md](docs/BUILD.md)**

## What's here

| Path | What |
|---|---|
| `core/` | Rust crate: LocalSend v2.1-compatible discovery, HTTP transfer server/client, self-signed TLS + fingerprint pinning, local transfer history. Framework-agnostic, fully unit-tested. |
| `app/src/` | React + TypeScript + Tailwind frontend — device discovery, drag-and-drop send, incoming-transfer accept/reject, settings, history. |
| `app/src-tauri/` | Tauri 2 glue wiring `core` into the desktop app and exposing it to the frontend via commands/events. |

## Status

Core protocol (discovery, send/receive, PIN, history) is implemented and
tested. TLS/fingerprint pinning is implemented behind an opt-in Cargo
feature (`--features tls`) but not yet wired into the running app by
default — see `docs/BUILD.md` for details. Mobile targets (Android/iOS)
aren't scaffolded yet.

## License

Choose one and drop it in `LICENSE` — not decided yet.
