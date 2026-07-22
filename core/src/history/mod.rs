//! Local-only transfer history, persisted as a flat JSON array.
//!
//! Deliberately not SQLite: history is small (capped list), read/written as
//! a whole file, and this keeps the "lightweight" story honest — no bundled
//! DB engine for a feature that's a few hundred rows at most. If usage ever
//! outgrows that, swap this module's internals for a real DB without
//! touching callers (the public functions all take a `&Path` and work in
//! terms of `TransferRecord`, not file format details).

use serde::{Deserialize, Serialize};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

/// Oldest records are dropped once history exceeds this many entries, so the
/// file can't grow unbounded on a machine that's been sending/receiving for
/// months.
const MAX_RECORDS: usize = 200;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Direction {
    Sent,
    Received,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RecordStatus {
    Done,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferRecord {
    pub id: String,
    pub direction: Direction,
    pub peer_alias: String,
    pub file_name: String,
    pub size: u64,
    pub status: RecordStatus,
    /// Unix seconds. Not a `SystemTime` on the wire — plain u64 keeps the
    /// JSON stable across platforms/timezones and trivial to sort/display.
    pub timestamp: u64,
    /// Only set for `Direction::Sent`, where we still know the source path
    /// on disk and can offer a "resend" action. Received files are saved to
    /// a fixed save_dir the UI already knows, so no path is stored for them.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_path: Option<String>,
}

impl TransferRecord {
    pub fn new(
        direction: Direction,
        peer_alias: impl Into<String>,
        file_name: impl Into<String>,
        size: u64,
        status: RecordStatus,
        source_path: Option<String>,
    ) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            direction,
            peer_alias: peer_alias.into(),
            file_name: file_name.into(),
            size,
            status,
            timestamp: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0),
            source_path,
        }
    }
}

async fn read_all(path: &Path) -> Vec<TransferRecord> {
    match tokio::fs::read(path).await {
        Ok(bytes) => serde_json::from_slice(&bytes).unwrap_or_default(),
        Err(_) => Vec::new(), // missing file (first run) or unreadable — treat as empty
    }
}

async fn write_all(path: &Path, records: &[TransferRecord]) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    let json = serde_json::to_vec_pretty(records).expect("TransferRecord always serializes");
    tokio::fs::write(path, json).await
}

/// Appends one record, newest-first, trimming to `MAX_RECORDS`.
pub async fn append(path: &Path, record: TransferRecord) -> std::io::Result<()> {
    let mut records = read_all(path).await;
    records.insert(0, record);
    records.truncate(MAX_RECORDS);
    write_all(path, &records).await
}

pub async fn list(path: &Path) -> Vec<TransferRecord> {
    read_all(path).await
}

pub async fn clear(path: &Path) -> std::io::Result<()> {
    write_all(path, &[]).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn append_and_list_roundtrip() {
        let dir = std::env::temp_dir().join(format!("shanusend-history-test-{}", Uuid::new_v4()));
        let path = dir.join("history.json");

        append(
            &path,
            TransferRecord::new(
                Direction::Sent,
                "Test Peer",
                "a.txt",
                10,
                RecordStatus::Done,
                None,
            ),
        )
        .await
        .unwrap();
        append(
            &path,
            TransferRecord::new(
                Direction::Received,
                "Test Peer",
                "b.txt",
                20,
                RecordStatus::Failed,
                None,
            ),
        )
        .await
        .unwrap();

        let records = list(&path).await;
        assert_eq!(records.len(), 2);
        // Newest first.
        assert_eq!(records[0].file_name, "b.txt");
        assert_eq!(records[1].file_name, "a.txt");

        clear(&path).await.unwrap();
        assert!(list(&path).await.is_empty());

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn caps_at_max_records() {
        let dir =
            std::env::temp_dir().join(format!("shanusend-history-cap-test-{}", Uuid::new_v4()));
        let path = dir.join("history.json");

        for i in 0..(MAX_RECORDS + 10) {
            append(
                &path,
                TransferRecord::new(
                    Direction::Sent,
                    "Peer",
                    format!("file{i}.txt"),
                    1,
                    RecordStatus::Done,
                    None,
                ),
            )
            .await
            .unwrap();
        }

        assert_eq!(list(&path).await.len(), MAX_RECORDS);
        let _ = tokio::fs::remove_dir_all(&dir).await;
    }
}
