//! UDP multicast discovery, protocol-compatible with LocalSend v2.1.
//!
//! LocalSend announces itself on 224.0.0.167:53317 and listens on the same
//! group for other devices' announcements. Devices that already know each
//! other reply directly (unicast) instead of re-broadcasting, to keep
//! multicast traffic low.

use crate::models::MulticastDto;
use serde::Serialize;
use socket2::{Domain, Protocol, Socket, Type};
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};
use std::sync::Arc;
use tokio::net::UdpSocket;
use tokio::sync::mpsc;
use tracing::{debug, warn};

pub const DEFAULT_PORT: u16 = 53317;
pub const MULTICAST_GROUP: Ipv4Addr = Ipv4Addr::new(224, 0, 0, 167);

/// A raw discovery event as received off the wire. The caller (server/UI
/// layer) is responsible for turning this into a `Device` + deduping.
#[derive(Debug, Clone)]
pub struct DiscoveryEvent {
    pub from_addr: SocketAddr,
    pub dto: MulticastDto,
}

/// Builds a UDP socket bound to 0.0.0.0:53317 with SO_REUSEADDR and joined to
/// the multicast group. Using socket2 directly (rather than only
/// tokio::net::UdpSocket) because SO_REUSEADDR/SO_REUSEPORT must be set
/// *before* bind, which tokio's socket builder doesn't expose on all platforms.
fn build_multicast_socket() -> std::io::Result<UdpSocket> {
    let socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    socket.set_reuse_address(true)?;
    #[cfg(unix)]
    socket.set_reuse_port(true).ok(); // best-effort, not available on all unix targets
    socket.set_nonblocking(true)?;

    let bind_addr: SocketAddr = SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, DEFAULT_PORT).into();
    socket.bind(&bind_addr.into())?;
    socket.join_multicast_v4(&MULTICAST_GROUP, &Ipv4Addr::UNSPECIFIED)?;
    socket.set_multicast_loop_v4(true)?; // useful for local dev/testing with two instances

    UdpSocket::from_std(socket.into())
}

/// Starts listening for multicast announcements. Returns a receiver that
/// yields one `DiscoveryEvent` per inbound packet. Runs until the returned
/// task handle is aborted or the socket errors out.
pub fn listen() -> (mpsc::Receiver<DiscoveryEvent>, tokio::task::JoinHandle<()>) {
    let (tx, rx) = mpsc::channel(64);

    let handle = tokio::spawn(async move {
        let socket = match build_multicast_socket() {
            Ok(s) => s,
            Err(e) => {
                warn!("failed to bind multicast socket: {e}");
                return;
            }
        };

        let mut buf = [0u8; 8192];
        loop {
            match socket.recv_from(&mut buf).await {
                Ok((len, from_addr)) => {
                    match serde_json::from_slice::<MulticastDto>(&buf[..len]) {
                        Ok(dto) => {
                            debug!("discovery packet from {from_addr}: {}", dto.alias);
                            if tx.send(DiscoveryEvent { from_addr, dto }).await.is_err() {
                                break; // receiver dropped
                            }
                        }
                        Err(e) => {
                            debug!("ignoring malformed discovery packet from {from_addr}: {e}")
                        }
                    }
                }
                Err(e) => {
                    warn!("multicast recv error: {e}");
                    break;
                }
            }
        }
    });

    (rx, handle)
}

/// Sends a single announcement/query packet to the multicast group.
/// `announce = true` means "here I am, please reply" (sent on startup and
/// periodically); reply packets set `announce = false` to avoid loops.
pub async fn announce(dto: &MulticastDto) -> std::io::Result<()> {
    send_to(dto, SocketAddrV4::new(MULTICAST_GROUP, DEFAULT_PORT).into()).await
}

/// Sends a unicast reply directly to a peer (used when responding to their
/// announcement, per protocol, to avoid multicast storms).
pub async fn reply_to(dto: &MulticastDto, target: SocketAddr) -> std::io::Result<()> {
    send_to(dto, target).await
}

async fn send_to<T: Serialize>(dto: &T, target: SocketAddr) -> std::io::Result<()> {
    let socket = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0)).await?;
    let payload = serde_json::to_vec(dto).expect("MulticastDto always serializes");
    socket.send_to(&payload, target).await?;
    Ok(())
}

/// Convenience: builds the outgoing `MulticastDto` for this device.
pub fn build_self_announcement(
    alias: &str,
    fingerprint: &str,
    port: u16,
    https: bool,
    device_model: Option<String>,
    device_type: crate::models::DeviceType,
    announce_flag: bool,
) -> MulticastDto {
    MulticastDto {
        alias: alias.to_string(),
        version: Some("2.1".to_string()),
        device_model,
        device_type: Some(device_type),
        fingerprint: fingerprint.to_string(),
        port: Some(port),
        protocol: Some(if https {
            crate::models::ProtocolType::Https
        } else {
            crate::models::ProtocolType::Http
        }),
        download: Some(false),
        announcement: Some(announce_flag),
        announce: Some(announce_flag),
    }
}

/// Shared, cloneable handle so the Tauri command layer and the HTTP server
/// can both trigger announcements without owning the socket themselves.
pub type SharedDiscovery = Arc<tokio::sync::Mutex<()>>;
