use std::path::PathBuf;
use serde::{Deserialize, Serialize};

use crate::models::QuotaCard;
use crate::paths::config_dir;

/// Per-account snapshot cache.
///
/// Each account's last snapshot is stored as a separate JSON file.
/// File naming: `{accountId}.json` where accountId uses dot notation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedAccountSnapshot {
    pub provider_id: String,
    pub account_id: String,
    pub card_json: String,
    pub captured_at: String,
}

pub struct AccountSnapshotCache {
    directory: PathBuf,
}

impl AccountSnapshotCache {
    pub fn new() -> Self {
        let directory = config_dir().join("snapshot_cache");
        Self { directory }
    }

    fn ensure_dir(&self) -> Result<(), String> {
        std::fs::create_dir_all(&self.directory).map_err(|e| e.to_string())
    }

    fn file_path(&self, account_id: &str) -> PathBuf {
        // Sanitize account_id for filename
        let safe = account_id.replace('/', "_").replace('\\', "_");
        self.directory.join(format!("{safe}.json"))
    }

    /// Save a card snapshot for an account.
    pub fn save(&self, account_id: &str, card: &QuotaCard, captured_at: &str) -> Result<(), String> {
        self.ensure_dir()?;
        let cached = CachedAccountSnapshot {
            provider_id: card.provider_id.clone(),
            account_id: account_id.to_string(),
            card_json: serde_json::to_string(card).map_err(|e| e.to_string())?,
            captured_at: captured_at.to_string(),
        };
        let text = serde_json::to_string_pretty(&cached).map_err(|e| e.to_string())?;
        std::fs::write(self.file_path(account_id), text).map_err(|e| e.to_string())
    }

    /// Load a cached card for an account. Returns None if missing or corrupt.
    pub fn load(&self, account_id: &str) -> Option<CachedAccountSnapshot> {
        let path = self.file_path(account_id);
        let text = std::fs::read_to_string(path).ok()?;
        serde_json::from_str(&text).ok()
    }

    /// Load the cached card as a QuotaCard. Returns None if missing or corrupt.
    pub fn load_card(&self, account_id: &str) -> Option<QuotaCard> {
        let cached = self.load(account_id)?;
        serde_json::from_str(&cached.card_json).ok()
    }

    /// Delete the cache for an account. No-op if missing.
    pub fn delete(&self, account_id: &str) {
        let _ = std::fs::remove_file(self.file_path(account_id));
    }
}
