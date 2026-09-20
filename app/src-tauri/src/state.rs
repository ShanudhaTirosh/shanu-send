use shanusend_core::server::ServerState;
use std::path::PathBuf;
use std::sync::Arc;

pub struct AppState {
    pub server: Arc<ServerState>,
    pub port: u16,
    pub history_path: PathBuf,
    pub kde_engine: Arc<shanusend_core::shanuconnect::ShanuConnectEngine>,
}

/// Loads a persisted device identity (alias + cert) from the app data dir,
/// generating one on first run. Keeping the fingerprint stable across
/// restarts is what lets peers' "trusted device" pinning actually mean
/// something — regenerating the cert every launch would break that.
pub fn load_or_create_identity(
    app_data_dir: &PathBuf,
) -> (String, shanusend_core::crypto::GeneratedCert) {
    std::fs::create_dir_all(app_data_dir).ok();

    let alias_path = app_data_dir.join("alias.txt");
    let alias = std::fs::read_to_string(&alias_path).unwrap_or_else(|_| {
        let generated = default_alias();
        let _ = std::fs::write(&alias_path, &generated);
        generated
    });

    // v1: regenerate the cert each launch (fine for HTTP-only Phase 1/2;
    // Phase 3 wires this to real persisted DER files + fingerprint pinning
    // on the client side, see core/src/client/mod.rs).
    let cert = shanusend_core::crypto::generate_self_signed(&alias).expect("cert generation");

    (alias, cert)
}

fn default_alias() -> String {
    let host = std::env::var("COMPUTERNAME")
        .or_else(|_| std::env::var("HOSTNAME"))
        .unwrap_or_else(|_| "device".to_string());
    format!("ShanuSend ({host})")
}

pub fn default_save_dir() -> PathBuf {
    dirs::download_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("ShanuSend")
}
