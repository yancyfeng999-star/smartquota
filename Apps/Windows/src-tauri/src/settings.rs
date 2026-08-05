use crate::catalog::{self, DISPLAY_ORDER};
use crate::paths::{ensure_config_dir, settings_path};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    /// UI language: zh-Hans | en
    #[serde(default = "default_language")]
    pub language: String,
    /// Provider enable flags + plan labels
    #[serde(default)]
    pub providers: HashMap<String, ProviderSettings>,
    /// MiniMax region: china | international
    #[serde(default = "default_minimax_region")]
    pub minimax_region: String,
    /// Optional env var name for MiniMax key (empty = MINIMAX_API_KEY)
    #[serde(default)]
    pub minimax_auth_env_var: String,
    /// Auto refresh interval seconds (0 = only manual). Aligned with Mac: 0/300/600/900/1800
    #[serde(default = "default_refresh_secs")]
    pub refresh_interval_secs: u64,

    // --- Quota threshold alerts (Mac QuotaAlertPolicy) ---
    #[serde(default = "default_true")]
    pub quota_threshold_alerts_enabled: bool,
    #[serde(default = "default_alert_threshold")]
    pub session_alert_threshold: f64,
    #[serde(default = "default_alert_threshold")]
    pub weekly_alert_threshold: f64,
    #[serde(default = "default_near_reset_hours")]
    pub near_reset_alert_hours: f64,
    #[serde(default = "default_underuse_remaining")]
    pub underuse_alert_remaining: f64,

    /// Debounce map: "providerId:kind" -> last fired unix
    #[serde(default)]
    pub alert_last_fired: HashMap<String, i64>,

    /// Card display order (provider ids). Empty = catalog default.
    #[serde(default)]
    pub provider_order: Vec<String>,

    /// Keep main window always on top (pinned)
    #[serde(default)]
    pub window_pinned: bool,

    /// Load user extensions from ~/.smartquota/extensions
    #[serde(default = "default_true")]
    pub extensions_enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ProviderSettings {
    /// None = use catalog default (core on / extension off)
    pub enabled: Option<bool>,
    #[serde(default)]
    pub plan_label: String,
    #[serde(default)]
    pub renewal_date: String,
}

fn default_language() -> String {
    "zh-Hans".into()
}
fn default_minimax_region() -> String {
    "china".into()
}
fn default_refresh_secs() -> u64 {
    900 // Mac default 15 minutes
}
fn default_true() -> bool {
    true
}
fn default_alert_threshold() -> f64 {
    20.0
}
fn default_near_reset_hours() -> f64 {
    24.0
}
fn default_underuse_remaining() -> f64 {
    40.0
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            language: default_language(),
            providers: HashMap::new(),
            minimax_region: default_minimax_region(),
            minimax_auth_env_var: String::new(),
            refresh_interval_secs: default_refresh_secs(),
            quota_threshold_alerts_enabled: true,
            session_alert_threshold: default_alert_threshold(),
            weekly_alert_threshold: default_alert_threshold(),
            near_reset_alert_hours: default_near_reset_hours(),
            underuse_alert_remaining: default_underuse_remaining(),
            alert_last_fired: HashMap::new(),
            provider_order: Vec::new(),
            window_pinned: false,
            extensions_enabled: true,
        }
    }
}

/// Built-in providers (full Mac catalog order).
pub const CATALOG_PROVIDERS: &[&str] = DISPLAY_ORDER;

impl AppSettings {
    pub fn load() -> Self {
        let path = settings_path();
        match fs::read_to_string(&path) {
            Ok(text) => serde_json::from_str(&text).unwrap_or_default(),
            Err(_) => Self::default(),
        }
    }

    pub fn save(&self) -> Result<(), String> {
        ensure_config_dir().map_err(|e| e.to_string())?;
        let path = settings_path();
        let text = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        fs::write(path, text).map_err(|e| e.to_string())
    }

    pub fn is_enabled(&self, id: &str) -> bool {
        if let Some(p) = self.providers.get(id) {
            if let Some(v) = p.enabled {
                return v;
            }
        }
        catalog::default_enabled(id)
    }

    pub fn set_enabled(&mut self, id: &str, enabled: bool) {
        self.providers
            .entry(id.to_string())
            .or_default()
            .enabled = Some(enabled);
    }

    pub fn set_plan_label(&mut self, id: &str, label: String) {
        self.providers.entry(id.to_string()).or_default().plan_label = label;
    }

    pub fn plan_label(&self, id: &str) -> String {
        self.providers
            .get(id)
            .map(|p| p.plan_label.clone())
            .unwrap_or_default()
    }

    /// Normalize refresh to Mac picker: 0, 300, 600, 900, 1800
    pub fn normalized_refresh_secs(&self) -> u64 {
        let s = self.refresh_interval_secs;
        if s == 0 {
            return 0;
        }
        let options = [300u64, 600, 900, 1800];
        *options
            .iter()
            .min_by_key(|&&o| (o as i64 - s as i64).unsigned_abs())
            .unwrap_or(&900)
    }

    /// Resolved provider order: user order first (valid ids), then remaining catalog.
    pub fn resolved_order(&self) -> Vec<String> {
        let mut seen = std::collections::HashSet::new();
        let mut out = Vec::new();
        for id in &self.provider_order {
            if CATALOG_PROVIDERS.contains(&id.as_str()) && seen.insert(id.clone()) {
                out.push(id.clone());
            }
        }
        for id in CATALOG_PROVIDERS {
            if seen.insert((*id).to_string()) {
                out.push((*id).to_string());
            }
        }
        out
    }
}
