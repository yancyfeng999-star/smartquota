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
    /// Auto refresh interval seconds (0 = only manual)
    #[serde(default = "default_refresh_secs")]
    pub refresh_interval_secs: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ProviderSettings {
    /// None = use product default for core providers
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
    300
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            language: default_language(),
            providers: HashMap::new(),
            minimax_region: default_minimax_region(),
            minimax_auth_env_var: String::new(),
            refresh_interval_secs: default_refresh_secs(),
        }
    }
}

/// Core providers enabled by default (aligned with Mac product).
pub const CORE_PROVIDERS: &[&str] = &["codex", "minimax", "grok"];

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
        CORE_PROVIDERS.contains(&id)
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
}
