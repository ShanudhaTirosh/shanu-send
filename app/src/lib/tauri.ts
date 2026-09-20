import type { Device, SendEvent } from "../types";

// Whether we're actually running inside the Tauri shell. When developing
// the UI in a plain browser (e.g. `npm run dev` opened in Chrome instead of
// via `tauri dev`), `window.__TAURI_INTERNALS__` is absent — we fall back to
// mock data so the interface is still fully clickable/demoable without a
// compiled Rust backend. Real command names below match what's wired up in
// src-tauri/src/commands.rs; keep them in sync when either side changes.
const isTauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

async function realInvoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<T>(cmd, args);
}

async function realListen<T>(event: string, handler: (payload: T) => void): Promise<() => void> {
  const { listen } = await import("@tauri-apps/api/event");
  const unlisten = await listen<T>(event, (e) => handler(e.payload));
  return unlisten;
}

// ---- Mock backend (browser-preview only) -----------------------------

const MOCK_DEVICES: Device[] = [
  {
    ip: "192.168.1.42",
    port: 53317,
    https: true,
    alias: "Shanudha's Pixel",
    version: "2.1",
    device_model: "Pixel 8",
    device_type: "Mobile",
    fingerprint: "mock-fingerprint-1",
    download: false,
    trusted: true,
  },
  {
    ip: "192.168.1.17",
    port: 53317,
    https: true,
    alias: "SHANUTECHX-DESKTOP",
    version: "2.1",
    device_model: "Windows",
    device_type: "Desktop",
    fingerprint: "mock-fingerprint-2",
    download: false,
    trusted: false,
  },
];

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---- Public API ---------------------------------------------------------

export async function startDiscovery(onDevice: (device: Device) => void): Promise<() => void> {
  if (isTauri) {
    return realListen<Device>("device-discovered", onDevice);
  }

  // Mock mode: trickle in the two fake devices to demo the radar UI.
  let cancelled = false;
  (async () => {
    for (const device of MOCK_DEVICES) {
      await delay(600 + Math.random() * 900);
      if (!cancelled) onDevice(device);
    }
  })();
  return () => {
    cancelled = true;
  };
}

export async function refreshDiscovery(): Promise<void> {
  if (isTauri) {
    await realInvoke("refresh_discovery");
  }
  // no-op in mock mode
}

export async function sendFiles(
  target: Device,
  files: LocalFileInput[],
  onEvent: (event: SendEvent) => void,
): Promise<void> {
  if (isTauri) {
    const unlisten = await realListen<SendEvent>("send-progress", onEvent);
    try {
      await realInvoke("send_files", { target, files });
    } finally {
      unlisten();
    }
    return;
  }

  // Mock mode: simulate a believable send so the UI is demoable standalone.
  onEvent({ type: "Preparing" });
  await delay(500);
  for (const file of files) {
    const steps = 6;
    for (let i = 1; i <= steps; i++) {
      await delay(120);
      onEvent({
        type: "FileProgress",
        file_id: file.id,
        bytes_sent: Math.round((file.size * i) / steps),
        total_bytes: file.size,
      });
    }
    onEvent({ type: "FileDone", file_id: file.id });
  }
  onEvent({ type: "AllDone" });
}

export interface LocalFileInput {
  id: string;
  path: string;
  file_name: string;
  size: number;
  mime: string;
}

export interface IncomingRequestPayload {
  sessionId: string;
  senderAlias: string;
  files: { id: string; fileName: string; size: number; fileType: string }[];
}

/**
 * Subscribes to incoming transfer requests from peers. The handler decides
 * accept/reject and calls the returned `respond` function.
 */
export async function onIncomingRequest(
  handler: (payload: IncomingRequestPayload, respond: (accept: boolean) => Promise<void>) => void,
): Promise<() => void> {
  if (isTauri) {
    return realListen<import("../types").ServerEvent>("incoming-request", (event) => {
      if (event.type !== "IncomingRequest") return;
      const payload: IncomingRequestPayload = {
        sessionId: event.session_id,
        senderAlias: event.sender_alias,
        files: Object.values(event.files).map((f) => ({
          id: f.id,
          fileName: f.file_name,
          size: f.size,
          fileType: f.file_type,
        })),
      };
      handler(payload, async (accept) => {
        await realInvoke("respond_prepare_upload", {
          sessionId: payload.sessionId,
          acceptedFileIds: accept ? payload.files.map((f) => f.id) : null,
        });
      });
    });
  }

  // Mock mode: fire one demo incoming request a couple seconds after load,
  // so the accept/reject UI is visible without a running backend.
  let cancelled = false;
  (async () => {
    await delay(4000);
    if (cancelled) return;
    handler(
      {
        sessionId: "mock-session-1",
        senderAlias: "Shanudha's Pixel",
        files: [{ id: "f1", fileName: "vacation-photo.jpg", size: 3_200_000, fileType: "image/jpeg" }],
      },
      async (accept) => {
        console.log("[mock] transfer request", accept ? "accepted" : "rejected");
      },
    );
  })();
  return () => {
    cancelled = true;
  };
}

export interface Settings {
  alias: string;
  save_dir: string;
  pin_enabled: boolean;
  trusted_fingerprints: string[];
}

const MOCK_SETTINGS: Settings = {
  alias: "ShanuSend (this device)",
  save_dir: "~/Downloads/ShanuSend",
  pin_enabled: false,
  trusted_fingerprints: ["mock-fingerprint-1"],
};

export interface SelfInfo {
  alias: string;
  fingerprint: string;
  port: number;
}

export async function getSelfInfo(): Promise<SelfInfo> {
  if (isTauri) return realInvoke<SelfInfo>("get_self_info");
  await delay(100);
  return { alias: "ShanuSend Device", fingerprint: "mock-fingerprint", port: 53317 };
}

export async function getSettings(): Promise<Settings> {
  if (isTauri) return realInvoke<Settings>("get_settings");
  await delay(200);
  return { ...MOCK_SETTINGS };
}

export async function setPin(pin: string | null): Promise<void> {
  if (isTauri) {
    await realInvoke("set_pin", { pin });
    return;
  }
  MOCK_SETTINGS.pin_enabled = !!pin;
}

export async function setDeviceTrusted(fingerprint: string, trusted: boolean): Promise<void> {
  if (isTauri) {
    await realInvoke("set_device_trusted", { fingerprint, trusted });
    return;
  }
  MOCK_SETTINGS.trusted_fingerprints = trusted
    ? [...MOCK_SETTINGS.trusted_fingerprints, fingerprint]
    : MOCK_SETTINGS.trusted_fingerprints.filter((f) => f !== fingerprint);
}

/** Takes effect on next launch — see the Rust-side doc comment for why. */
export async function renameDevice(newAlias: string): Promise<void> {
  if (isTauri) {
    await realInvoke("rename_device", { newAlias });
    return;
  }
  MOCK_SETTINGS.alias = newAlias;
}

export interface IncomingTransferState {
  sessionId: string;
  fileId: string;
  fileName?: string;
  receivedBytes: number;
  totalBytes: number;
  status: "receiving" | "done" | "failed";
  reason?: string;
}

/** Subscribes to receive-side progress for files peers are sending *us*. */
export async function onIncomingProgress(
  onUpdate: (state: IncomingTransferState) => void,
): Promise<() => void> {
  if (isTauri) {
    const unlistenProgress = await realListen<import("../types").ServerEvent>(
      "upload-progress",
      (e) => {
        if (e.type !== "UploadProgress") return;
        onUpdate({
          sessionId: e.session_id,
          fileId: e.file_id,
          receivedBytes: e.received_bytes,
          totalBytes: e.total_bytes,
          status: "receiving",
        });
      },
    );
    const unlistenComplete = await realListen<import("../types").ServerEvent>(
      "upload-complete",
      (e) => {
        if (e.type !== "UploadComplete") return;
        onUpdate({
          sessionId: e.session_id,
          fileId: e.file_id,
          receivedBytes: 1,
          totalBytes: 1,
          status: "done",
        });
      },
    );
    const unlistenFailed = await realListen<import("../types").ServerEvent>("upload-failed", (e) => {
      if (e.type !== "UploadFailed") return;
      onUpdate({
        sessionId: e.session_id,
        fileId: e.file_id,
        receivedBytes: 0,
        totalBytes: 1,
        status: "failed",
        reason: e.reason,
      });
    });
    return () => {
      unlistenProgress();
      unlistenComplete();
      unlistenFailed();
    };
  }

  // Mock mode: no incoming transfers happen on their own; nothing to wire up
  // beyond the demo IncomingRequestModal firing, since simulating a full
  // receive alongside that would be more misleading than helpful in preview.
  return () => {};
}

export async function setSaveDir(path: string): Promise<void> {
  if (isTauri) {
    await realInvoke("set_save_dir", { path });
    return;
  }
  MOCK_SETTINGS.save_dir = path;
}

/**
 * Opens the native folder picker. Returns the chosen path, or null if the
 * user cancelled. Uses `@tauri-apps/plugin-dialog` directly rather than a
 * Rust command — the plugin's JS API already returns the result, so routing
 * it through `invoke` first would just add a hop.
 */
export async function pickSaveFolder(): Promise<string | null> {
  if (isTauri) {
    const { open } = await import("@tauri-apps/plugin-dialog");
    const result = await open({ directory: true, multiple: false, title: "Choose a save folder" });
    return typeof result === "string" ? result : null;
  }
  // Mock mode: browsers can't show a native folder picker, so simulate the
  // choice so the settings UI is still demoable end-to-end.
  await delay(300);
  return "~/Downloads/ShanuSend (demo)";
}

export interface TransferRecord {
  id: string;
  direction: "sent" | "received";
  peer_alias: string;
  file_name: string;
  size: number;
  status: "done" | "failed";
  timestamp: number;
  source_path?: string;
}

const MOCK_HISTORY: TransferRecord[] = [
  {
    id: "h1",
    direction: "sent",
    peer_alias: "SHANUTECHX-DESKTOP",
    file_name: "deploy-notes.pdf",
    size: 480_000,
    status: "done",
    timestamp: Math.floor(Date.now() / 1000) - 3600,
  },
  {
    id: "h2",
    direction: "received",
    peer_alias: "Shanudha's Pixel",
    file_name: "screenshot.png",
    size: 1_240_000,
    status: "done",
    timestamp: Math.floor(Date.now() / 1000) - 86_400,
  },
];

export async function listHistory(): Promise<TransferRecord[]> {
  if (isTauri) return realInvoke<TransferRecord[]>("list_history");
  await delay(200);
  return [...MOCK_HISTORY];
}

export async function clearHistory(): Promise<void> {
  if (isTauri) {
    await realInvoke("clear_history");
    return;
  }
  MOCK_HISTORY.length = 0;
}

// ---- KDE Connect Live IPC Helpers ----------------------------------------

export async function kdeconnectSendMousepad(dx?: number, dy?: number, click?: string): Promise<void> {
  if (isTauri) {
    await realInvoke("kdeconnect_send_mousepad", { dx, dy, click });
  }
}

export async function kdeconnectTriggerFindPhone(ring: boolean): Promise<void> {
  if (isTauri) {
    await realInvoke("kdeconnect_trigger_find_phone", { ring });
  }
}

export async function kdeconnectLockDevice(locked: boolean): Promise<void> {
  if (isTauri) {
    await realInvoke("kdeconnect_lock_device", { locked });
  }
}

export async function kdeconnectRunRemoteCommand(command: string): Promise<string> {
  if (isTauri) {
    return realInvoke<string>("kdeconnect_run_remote_command", { command });
  }
  return `[Mock Exec] ${command}`;
}

export async function kdeconnectSendSms(recipient: String, body: String): Promise<void> {
  if (isTauri) {
    await realInvoke("kdeconnect_send_sms", { recipient, body });
  }
}

export async function kdeconnectMprisControl(action: string, volume?: number): Promise<void> {
  if (isTauri) {
    await realInvoke("kdeconnect_mpris_control", { action, volume });
  }
}

export { isTauri };

