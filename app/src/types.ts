// Mirrors shanusend-core::models::Device (serde camelCase via #[serde(rename_all)]
// is NOT applied there — the Rust struct uses snake_case field names and we
// rely on serde_json's default, so keep these in sync with core/src/models/mod.rs
// field names exactly if you add `#[serde(rename_all = "camelCase")]` there.)

export type DeviceType = "Mobile" | "Desktop" | "Web" | "Headless" | "Server";

export interface Device {
  ip: string;
  port: number;
  https: boolean;
  alias: string;
  version: string;
  device_model: string | null;
  device_type: DeviceType;
  fingerprint: string;
  download: boolean;
  trusted: boolean;
}

export interface LocalFile {
  id: string;
  path: string;
  file_name: string;
  size: number;
  mime: string;
}

export type ServerEvent =
  | { type: "IncomingRequest"; session_id: string; sender_alias: string; files: Record<string, RustFileDto> }
  | { type: "UploadProgress"; session_id: string; file_id: string; received_bytes: number; total_bytes: number; speed_bytes_per_sec?: number; eta_seconds?: number }
  | { type: "UploadComplete"; session_id: string; file_id: string; saved_path: string }
  | { type: "UploadFailed"; session_id: string; file_id: string; reason: string }
  | { type: "SessionCancelled"; session_id: string };

// Rust's FileDto struct is #[serde(rename_all not applied)] i.e. plain
// snake_case field names on the wire from our own server events (this is
// NOT the LocalSend wire protocol's FileDto, which uses camelCase — this is
// our internal Tauri event payload). Keep in sync with core/src/models/mod.rs.
export interface RustFileDto {
  id: string;
  file_name: string;
  size: number;
  file_type: string;
  hash: string | null;
  preview: string | null;
}

export type SendEvent =
  | { type: "Preparing" }
  | { type: "Rejected" }
  | { type: "PinRequired" }
  | { type: "FileProgress"; file_id: string; bytes_sent: number; total_bytes: number; speed_bytes_per_sec?: number; eta_seconds?: number }
  | { type: "FileDone"; file_id: string }
  | { type: "FileFailed"; file_id: string; reason: string }
  | { type: "AllDone" };
