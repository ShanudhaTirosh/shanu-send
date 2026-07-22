# ShanuSend — Local Run & Build Guide

This covers everything from "clone it" to "produce an installer." If you hit
an error not covered here, see [Troubleshooting](#troubleshooting) — several
known quirks from this project's early sandboxed development are documented
there with exact fixes.

## 1. Prerequisites

Install these once, in order:

| Tool | Version | Install |
|---|---|---|
| **Rust** | stable, ≥1.77 (Tauri 2's floor) | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` (or [rustup.rs](https://rustup.rs) on Windows) |
| **Node.js** | ≥18 (20 LTS recommended) | [nodejs.org](https://nodejs.org) or `nvm install 20` |
| **Tauri CLI** | matches `@tauri-apps/cli` in `app/package.json` | installed automatically via `npm install` — no separate step |
| **System webview + build deps** | OS-specific | see below |

### Linux (Debian/Ubuntu)
```bash
sudo apt update
sudo apt install -y \
  libwebkit2gtk-4.1-dev \
  libgtk-3-dev \
  libayatana-appindicator3-dev \
  librsvg2-dev \
  libsoup-3.0-dev \
  build-essential \
  curl \
  wget \
  file \
  pkg-config
```
Other distros: see [Tauri's Linux prerequisites](https://tauri.app/start/prerequisites/) for the equivalent packages (Fedora uses `webkit2gtk4.1-devel`, etc.).

### macOS
```bash
xcode-select --install
```
That's it — macOS ships the required WebKit.

### Windows
Install the **Microsoft C++ Build Tools** (via [Visual Studio Installer](https://visualstudio.microsoft.com/visual-cpp-build-tools/), "Desktop development with C++" workload) and **WebView2** (pre-installed on Windows 11 and most up-to-date Windows 10 machines; otherwise [download it](https://developer.microsoft.com/microsoft-edge/webview2/)).

### Verify
```bash
rustc --version   # should be >= 1.77
node --version    # should be >= 18
cargo --version
```

## 2. Project layout

```
shanu-send/
├── core/            # Rust protocol crate — discovery, transfer, crypto, history
├── app/              # Tauri shell
│   ├── src/            # React/TS frontend
│   └── src-tauri/        # Rust ↔ UI glue (commands, main.rs)
```

`core` has zero UI dependencies and builds/tests standalone — always start
there if something's broken, to isolate protocol bugs from UI bugs.

## 3. First-time setup

```bash
git clone <your-repo-url> shanu-send
cd shanu-send

# 1. Verify the protocol core builds and its tests pass
cd core
cargo test
cd ..

# 2. Install frontend dependencies
cd app
npm install
cd ..
```

If `cargo test` in step 1 fails, fix that before touching the frontend — the
Tauri shell depends on `core` compiling cleanly, so protocol-layer errors
will otherwise resurface as confusing Tauri build failures later.

## 4. Running it locally

### Just the UI (fastest feedback loop, no Rust/Tauri involved)
```bash
cd app
npm run dev
```
Opens at `http://localhost:1420` in your browser. Runs against **mock data**
(fake devices, simulated transfers) — see `src/lib/tauri.ts`'s `isTauri`
check. Good for iterating on layout/styling without a full Tauri rebuild
each time.

### Full app (real discovery, real transfers, real Tauri window)
```bash
cd app
npm run tauri dev
```
This compiles `src-tauri` (pulling in `core` as a path dependency), starts
the Vite dev server, and opens a native window. First run compiles the full
Rust dependency tree and will take a few minutes; subsequent runs are
incremental and fast. Hot-reloads the frontend on save; Rust changes require
a restart of this command.

To test discovery/transfer for real, run this on **two machines** on the
same LAN (or one machine + a phone/laptop running actual LocalSend — the
protocol is compatible).

## 5. Building release binaries

```bash
cd app
npm run tauri build
```

Outputs land in `app/src-tauri/target/release/bundle/`:

| Platform | What you get |
|---|---|
| Linux | `.deb`, `.AppImage`, `.rpm` (if `rpm-build` installed) |
| macOS | `.app`, `.dmg` |
| Windows | `.msi`, `.exe` (NSIS) |

Cross-compiling (e.g. building the Windows installer from Linux) is
possible with Tauri but fiddly — the GitHub Actions workflow below builds
natively on each OS instead, which is simpler and more reliable.

## 6. Running the `core` crate's optional TLS feature

Phase 3 (real HTTPS + fingerprint pinning) is written but gated behind an
opt-in Cargo feature, because pulling it in changes `core`'s dependency
tree in ways that need a full, unconstrained `cargo` resolution:

```bash
cd core
cargo build --features tls
cargo test --features tls
```

On a normal, up-to-date Rust install this should "just work." If it
doesn't, see [Troubleshooting](#troubleshooting) below — there's a known
upstream version-compatibility nuance between `axum-server` and `hyper-util`
that occasionally needs a version bump.

To wire this into the running app (make `main.rs` actually call
`server::serve_tls` instead of plain `axum::serve`, and switch the client
to `client::pinned_http_client`), that integration hasn't been done yet —
the building blocks exist and compile, but nothing calls them yet. That's
the next piece of work, not something you need to do to build/run the app
as-is.

## 7. Linting & formatting

```bash
# Rust
cd core && cargo fmt --check && cargo clippy --all-targets -- -D warnings

# Frontend
cd app && npx tsc -b && npx eslint . # (eslint config not yet added — tsc is the main gate today)
```

## Troubleshooting

**`error: package X cannot be built because it requires rustc 1.8x`** or
**`feature 'edition2024' is required`**
You're on an old Rust toolchain. Run `rustup update stable` and
`rustup default stable`. (This entire project was originally scaffolded in
a sandboxed environment stuck on `rustc 1.75` via apt — if you ever see
exact `=x.y.z` version pins in `core/Cargo.toml` with a comment mentioning
"sandbox constraint," that's residue from working around *that specific
environment*, not a requirement of the code itself. On your real machine
with `rustup`-installed current stable Rust, delete `core/Cargo.lock` and
run `cargo build` — everything resolves to current versions fine.)

**`cargo build --features tls` fails inside `axum-server` with a trait-bound
error mentioning `hyper-util`**
This is a real upstream compatibility gap between specific `axum-server`
and `hyper-util` versions, not a code bug. Fix:
```bash
cd core
cargo update -p axum-server   # picks the latest compatible axum-server
cargo build --features tls
```
If that alone doesn't resolve it, check [axum-server's releases](https://github.com/programatik29/axum-server/releases) for a version bump and update the pin in `Cargo.toml`.

**Tauri window opens but discovery finds nothing**
- Confirm both devices are on the same LAN/subnet and not on a guest
  network that isolates clients from each other (common on public/office
  Wi-Fi).
- Some routers block UDP multicast entirely. The HTTP subnet-scan fallback
  described in the protocol notes isn't implemented yet in this codebase —
  currently discovery is multicast-only.
- Check your OS firewall isn't blocking inbound UDP/TCP on port `53317`.

**`npm run tauri dev` fails immediately with a webview/GTK error (Linux)**
You're missing a system package from [step 1](#1-prerequisites). Re-run the
`apt install` line — `libwebkit2gtk-4.1-dev` is the one people miss most
often (older guides reference `4.0`, which doesn't exist on newer Ubuntu).

**Folder picker button does nothing**
Confirm `app/src-tauri/capabilities/default.json` includes `"dialog:default"`
in its `permissions` array — Tauri 2's permission system silently no-ops
plugin calls that aren't explicitly granted, rather than erroring loudly.

---

For the phased feature roadmap (what's built vs. what's next), see the
implementation plan shared earlier in this project's history — this guide
only covers *how to run what exists*, not what's left to build.
