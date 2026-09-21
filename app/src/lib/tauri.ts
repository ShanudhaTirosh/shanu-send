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

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---- Public API ---------------------------------------------------------

export async function startDiscovery(onDevice: (device: Device) => void): Promise<() => void> {
  if (isTauri) {
    return realListen<Device>("device-discovered", onDevice);
  }

  // Web / Browser mode: query local server endpoint if active
  let cancelled = false;
  (async () => {
    try {
      const res = await fetch("/api/localsend/v2/info");
      if (res.ok && !cancelled) {
        const info = await res.json();
        onDevice({
          ip: window.location.hostname || "127.0.0.1",
          port: info.port || 53317,
          https: false,
          alias: info.alias || "Local Host Device",
          version: info.version || "2.1",
          device_model: info.device_model || "Host System",
          device_type: info.device_type || "Desktop",
          fingerprint: info.fingerprint || "local-host-fp",
          download: false,
          trusted: true,
        });
      }
    } catch (_) {
      // Offline / stand-alone browser preview
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

export async function pickFilesToTransfer(): Promise<LocalFileInput[]> {
  if (isTauri) {
    const { open } = await import("@tauri-apps/plugin-dialog");
    const selected = await open({
      multiple: true,
      directory: false,
      title: "Select Files to Send",
    });
    if (!selected) return [];
    const paths = Array.isArray(selected) ? selected : [selected];
    return paths.map((p) => {
      const pathStr = typeof p === "string" ? p : (p as any).path;
      const fileName = pathStr.split(/[/\\]/).pop() || pathStr;
      return {
        id: crypto.randomUUID(),
        path: pathStr,
        file_name: fileName,
        size: 0,
        mime: "application/octet-stream",
      };
    });
  }
  return [];
}

export async function onNativeFileDrop(
  onPaths: (paths: string[]) => void,
): Promise<() => void> {
  if (isTauri) {
    return realListen<any>("tauri://drag-drop", (payload) => {
      const paths = Array.isArray(payload)
        ? payload
        : (payload?.paths || []);
      if (paths.length > 0) onPaths(paths);
    });
  }
  return () => {};
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

  // Browser / Web mode: return no-op unlisten (no spontaneous fake incoming requests)
  return () => {};
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
  local_ip: string;
}

export async function getSelfInfo(): Promise<SelfInfo> {
  if (isTauri) return realInvoke<SelfInfo>("get_self_info");
  await delay(100);
  return { alias: "ShanuSend Device", fingerprint: "mock-fingerprint", port: 53317, local_ip: "127.0.0.1" };
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

export async function listHistory(): Promise<TransferRecord[]> {
  if (isTauri) return realInvoke<TransferRecord[]>("list_history");
  return [];
}

export async function clearHistory(): Promise<void> {
  if (isTauri) {
    await realInvoke("clear_history");
    return;
  }
}

// ---- ShanuConnect Live IPC Helpers ----------------------------------------

export async function shanuconnectSendMousepad(dx?: number, dy?: number, click?: string): Promise<void> {
  if (isTauri) {
    await realInvoke("shanuconnect_send_mousepad", { dx, dy, click });
  }
}

export async function shanuconnectTriggerFindPhone(ring: boolean): Promise<void> {
  if (isTauri) {
    await realInvoke("shanuconnect_trigger_find_phone", { ring });
  }
}

export async function shanuconnectLockDevice(locked: boolean): Promise<void> {
  if (isTauri) {
    await realInvoke("shanuconnect_lock_device", { locked });
  }
}

export async function shanuconnectRunRemoteCommand(command: string): Promise<string> {
  if (isTauri) {
    return realInvoke<string>("shanuconnect_run_remote_command", { command });
  }
  return `[Exec] ${command}`;
}

export async function shanuconnectSendSms(recipient: String, body: String): Promise<void> {
  if (isTauri) {
    await realInvoke("shanuconnect_send_sms", { recipient, body });
  }
}

export async function shanuconnectMprisControl(action: string, volume?: number): Promise<void> {
  if (isTauri) {
    await realInvoke("shanuconnect_mpris_control", { action, volume });
  }
}

export async function shanuconnectSendSystemVolume(volume: number): Promise<void> {
  if (isTauri) {
    await realInvoke("shanuconnect_send_system_volume", { volume });
  }
}

export async function shanuconnectSendClipboard(content: string): Promise<void> {
  if (isTauri) {
    await realInvoke("shanuconnect_send_clipboard", { content });
  }
}

export async function shanuconnectSendPair(pair: boolean): Promise<void> {
  if (isTauri) {
    await realInvoke("shanuconnect_send_pair", { pair });
  }
}

export async function shanuconnectReplyNotification(
  notificationId: string,
  replyMessage: string,
): Promise<void> {
  if (isTauri) {
    await realInvoke("shanuconnect_reply_notification", { notificationId, replyMessage });
  }
}

export async function shanuconnectTelephonyAction(
  action: string,
  phoneNumber?: string,
  message?: string,
): Promise<void> {
  if (isTauri) {
    await realInvoke("shanuconnect_telephony_action", { action, phoneNumber, message });
  }
}

export async function shanuconnectRequestSftp(path?: string): Promise<void> {
  if (isTauri) {
    await realInvoke("shanuconnect_request_sftp", { path });
  }
}

export interface ShanuConnectEventPayload {
  type: string;
  body: any;
}

export type KdeConnectEventPayload = ShanuConnectEventPayload;

export async function onShanuConnectEvent(
  handler: (payload: ShanuConnectEventPayload) => void,
): Promise<() => void> {
  if (isTauri) {
    return realListen<ShanuConnectEventPayload>("shanuconnect-event", handler);
  }
  return () => {};
}

export const kdeconnectSendMousepad = shanuconnectSendMousepad;
export const kdeconnectTriggerFindPhone = shanuconnectTriggerFindPhone;
export const kdeconnectLockDevice = shanuconnectLockDevice;
export const kdeconnectRunRemoteCommand = shanuconnectRunRemoteCommand;
export const kdeconnectSendSms = shanuconnectSendSms;
export const kdeconnectMprisControl = shanuconnectMprisControl;
export const onKdeConnectEvent = onShanuConnectEvent;

export interface AdbDevice {
  id: string;
  model: string;
  state: string;
}

export async function scrcpyCheckInstalled(): Promise<boolean> {
  if (isTauri) return realInvoke<boolean>("scrcpy_check_installed");
  return true;
}

export interface ScrcpyDownloadProgress {
  percent: number;
  status: string;
}

export async function scrcpyDownloadDependencies(): Promise<string> {
  if (isTauri) return realInvoke<string>("scrcpy_download_dependencies");
  return "Scrcpy & ADB tools installed automatically!";
}

export async function onScrcpyDownloadProgress(
  handler: (payload: ScrcpyDownloadProgress) => void,
): Promise<() => void> {
  if (isTauri) {
    return realListen<ScrcpyDownloadProgress>("scrcpy-download-progress", handler);
  }
  return () => {};
}

export async function scrcpyListAdbDevices(): Promise<AdbDevice[]> {
  if (isTauri) return realInvoke<AdbDevice[]>("scrcpy_list_adb_devices");
  return [];
}

export async function scrcpyAdbConnect(address: string): Promise<string> {
  if (isTauri) return realInvoke<string>("scrcpy_adb_connect", { address });
  return `connected to ${address}`;
}

export async function scrcpyAdbPair(address: string, code: string): Promise<string> {
  if (isTauri) return realInvoke<string>("scrcpy_adb_pair", { address, code });
  return `paired with ${address}`;
}

export interface ScrcpyOptions {
  deviceId?: string;
  maxSize?: number;
  bitRate?: number;
  fps?: number;
  videoCodec?: string;
  audioCodec?: string;
  cameraMode?: boolean;
  cameraFacing?: string;
  stayAwake?: boolean;
  turnScreenOff?: boolean;
  showTouches?: boolean;
  otgMode?: boolean;
  record?: boolean;
}

export async function scrcpyStartMirror(options: ScrcpyOptions = {}): Promise<string> {
  if (isTauri) {
    return realInvoke<string>("scrcpy_start_mirror", {
      deviceId: options.deviceId,
      maxSize: options.maxSize,
      bitRate: options.bitRate,
      fps: options.fps,
      videoCodec: options.videoCodec,
      audioCodec: options.audioCodec,
      cameraMode: options.cameraMode,
      cameraFacing: options.cameraFacing,
      stayAwake: options.stayAwake,
      turnScreenOff: options.turnScreenOff,
      showTouches: options.showTouches,
      otgMode: options.otgMode,
      record: options.record,
    });
  }
  return "Scrcpy process launched (Mock)";
}

export async function scrcpyAdbSendKeyevent(deviceId: string | undefined, keycode: number): Promise<string> {
  if (isTauri) {
    return realInvoke<string>("scrcpy_adb_send_keyevent", { deviceId, keycode });
  }
  return `Triggered keyevent ${keycode}`;
}

export async function scrcpyAdbShell(deviceId: string | undefined, command: string): Promise<string> {
  if (isTauri) {
    return realInvoke<string>("scrcpy_adb_shell", { deviceId, command });
  }
  return `Executed shell command ${command}`;
}

export async function quickshareGenerateUkey2Pin(): Promise<string> {
  if (isTauri) return realInvoke<string>("quickshare_generate_ukey2_pin");
  return "8492";
}

export interface WebDropSharedFile {
  id: string;
  name: string;
  path: string;
  size: number;
}

export async function webdropShareFiles(paths: string[]): Promise<number> {
  if (isTauri) return realInvoke<number>("webdrop_share_files", { paths });
  return paths.length;
}

export async function webdropGetSharedFiles(): Promise<WebDropSharedFile[]> {
  if (isTauri) return realInvoke<WebDropSharedFile[]>("webdrop_get_shared_files");
  return [];
}

export async function webdropClearSharedFiles(): Promise<void> {
  if (isTauri) return realInvoke<void>("webdrop_clear_shared_files");
}

export { isTauri };

