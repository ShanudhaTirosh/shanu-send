//! Self-signed certificate generation + fingerprint pinning.
//!
//! LocalSend's threat model is intentionally LAN-only: there is no CA, peers
//! instead pin the SHA-256 fingerprint of a device's self-signed cert the
//! first time they see it (announced alongside `alias`/`deviceType` in the
//! discovery payload), and compare it on every subsequent connection.

use rcgen::{CertificateParams, DistinguishedName, KeyPair};
use sha2::{Digest, Sha256};

pub struct GeneratedCert {
    pub cert_der: Vec<u8>,
    pub key_der: Vec<u8>,
    pub fingerprint: String,
}

/// Generates a fresh self-signed cert for this device. Callers should
/// generate this once per install and persist it (e.g. in app data dir),
/// not regenerate on every launch — the fingerprint is the device's
/// long-term identity as far as peers are concerned.
pub fn generate_self_signed(alias: &str) -> Result<GeneratedCert, rcgen::Error> {
    let mut params = CertificateParams::new(vec![alias.to_string()])?;
    let mut dn = DistinguishedName::new();
    dn.push(rcgen::DnType::CommonName, alias);
    params.distinguished_name = dn;

    let key_pair = KeyPair::generate()?;
    let cert = params.self_signed(&key_pair)?;

    let cert_der = cert.der().to_vec();
    let key_der = key_pair.serialize_der();
    let fingerprint = fingerprint_of(&cert_der);

    Ok(GeneratedCert {
        cert_der,
        key_der,
        fingerprint,
    })
}

/// SHA-256 fingerprint of a DER-encoded certificate, lowercase hex — matches
/// the format LocalSend uses in `RegisterDto.fingerprint`.
pub fn fingerprint_of(cert_der: &[u8]) -> String {
    use std::fmt::Write;
    let mut hasher = Sha256::new();
    hasher.update(cert_der);
    let digest = hasher.finalize();
    digest.iter().fold(String::with_capacity(64), |mut acc, b| {
        let _ = write!(acc, "{b:02x}");
        acc
    })
}

/// Constant-time-ish PIN check (length-independent short-circuit is fine
/// here since PINs are low-entropy anyway and this isn't a password hash;
/// what matters is not leaking timing on a 4-6 digit PIN over LAN).
pub fn verify_pin(provided: &str, expected: &str) -> bool {
    if provided.len() != expected.len() {
        return false;
    }
    provided
        .bytes()
        .zip(expected.bytes())
        .fold(0u8, |acc, (a, b)| acc | (a ^ b))
        == 0
}

/// Derives a deterministic 6-digit SAS (Short Authentication String) PIN
/// from two peer public keys / identity strings.
pub fn derive_sas_code(key_a: &[u8], key_b: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"SHANUSEND_SAS_V1");
    if key_a <= key_b {
        hasher.update(key_a);
        hasher.update(key_b);
    } else {
        hasher.update(key_b);
        hasher.update(key_a);
    }
    let digest = hasher.finalize();
    let num = u32::from_be_bytes([digest[0], digest[1], digest[2], digest[3]]);
    format!("{:06}", num % 1_000_000)
}

/// A `rustls` certificate verifier that ignores the normal CA chain (there
/// isn't one — every device is its own CA, by design) and instead accepts a
/// connection if and only if the presented leaf certificate's SHA-256
/// fingerprint matches the one the peer announced over multicast/HTTP
/// earlier. This *is* LocalSend's security model: trust-on-first-sight of
/// the fingerprint, then pin it.
///
/// Gated behind the `tls` feature for the same sandbox-toolchain reason as
/// `server::serve_tls` — see that function's doc comment.
#[cfg(feature = "tls")]
#[derive(Debug)]
pub struct PinnedFingerprintVerifier {
    pub expected_fingerprint: String,
    pub supported_algs: rustls::crypto::WebPkiSupportedAlgorithms,
}

#[cfg(feature = "tls")]
impl rustls::client::danger::ServerCertVerifier for PinnedFingerprintVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &rustls::pki_types::CertificateDer<'_>,
        _intermediates: &[rustls::pki_types::CertificateDer<'_>],
        _server_name: &rustls::pki_types::ServerName<'_>,
        _ocsp_response: &[u8],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        let actual = fingerprint_of(end_entity.as_ref());
        if actual.eq_ignore_ascii_case(&self.expected_fingerprint) {
            Ok(rustls::client::danger::ServerCertVerified::assertion())
        } else {
            // Deliberately generic error — don't leak which fingerprint we
            // expected vs got to anything logging TLS errors upstream.
            Err(rustls::Error::General("fingerprint mismatch".into()))
        }
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &rustls::pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(message, cert, dss, &self.supported_algs)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &rustls::pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(message, cert, dss, &self.supported_algs)
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        self.supported_algs.supported_schemes()
    }
}

/// Builds a `rustls::ClientConfig` that will only complete a handshake with
/// a peer presenting exactly `fingerprint`. Pass the result to
/// `reqwest::Client::builder().use_preconfigured_tls(config)` (requires
/// reqwest's `rustls-tls` backend feature — see the `tls` feature notes in
/// Cargo.toml for why that's opt-in in this sandbox).
#[cfg(feature = "tls")]
pub fn pinned_client_config(fingerprint: String) -> rustls::ClientConfig {
    let provider = rustls::crypto::ring::default_provider();
    let verifier = PinnedFingerprintVerifier {
        expected_fingerprint: fingerprint,
        supported_algs: provider.signature_verification_algorithms,
    };
    rustls::ClientConfig::builder_with_provider(std::sync::Arc::new(provider))
        .with_safe_default_protocol_versions()
        .expect("rustls default protocol versions are always valid")
        .dangerous()
        .with_custom_certificate_verifier(std::sync::Arc::new(verifier))
        .with_no_client_auth()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generates_valid_fingerprint() {
        let cert = generate_self_signed("test-device").expect("cert generation");
        assert_eq!(cert.fingerprint.len(), 64); // sha256 hex
    }

    #[test]
    fn pin_check_rejects_mismatch() {
        assert!(verify_pin("1234", "1234"));
        assert!(!verify_pin("1234", "4321"));
        assert!(!verify_pin("123", "1234"));
    }
}
