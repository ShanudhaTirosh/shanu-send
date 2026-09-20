//! shanusend-core
//!
//! Protocol-compatible (LocalSend v2.1) discovery, transfer, and crypto
//! logic, deliberately kept free of any UI framework so it can be embedded
//! identically in the Tauri desktop shell and the Tauri-mobile shell.
//!
//! Module map:
//! - `models`    wire-format DTOs (must match upstream LocalSend field names)
//! - `discovery` UDP multicast announce/listen on 224.0.0.167:53317
//! - `server`    receiving side: axum HTTP server (info/register/prepare-upload/upload/cancel)
//! - `client`    sending side: outbound HTTP requests to a peer's server
//! - `transfer`  sender-side orchestration + progress events
//! - `crypto`    self-signed cert generation + fingerprint pinning + PIN check

pub mod airdrop;
pub mod client;
pub mod crypto;
pub mod discovery;
pub mod history;
pub mod models;
pub mod server;
pub mod transfer;


pub use models::{Device, DeviceType};
