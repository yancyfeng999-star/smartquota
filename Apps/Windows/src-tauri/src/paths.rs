use std::path::PathBuf;

/// `%USERPROFILE%\.smartquota`
pub fn config_dir() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".smartquota")
}

pub fn settings_path() -> PathBuf {
    config_dir().join("settings.json")
}

pub fn logs_dir() -> PathBuf {
    dirs::data_local_dir()
        .unwrap_or_else(|| config_dir())
        .join("SmartQuota")
        .join("Logs")
}

pub fn log_file_path() -> PathBuf {
    logs_dir().join("SmartQuota.log")
}

pub fn home() -> PathBuf {
    dirs::home_dir().unwrap_or_else(|| PathBuf::from("."))
}

pub fn codex_auth_path() -> PathBuf {
    home().join(".codex").join("auth.json")
}

pub fn grok_auth_path() -> PathBuf {
    home().join(".grok").join("auth.json")
}

pub fn minimax_config_path() -> PathBuf {
    home().join(".minimax").join("config.yaml")
}

pub fn kimi_config_path() -> PathBuf {
    home().join(".kimi").join("config.json")
}

pub fn claude_json_path() -> PathBuf {
    home().join(".claude.json")
}

pub fn claude_dir() -> PathBuf {
    home().join(".claude")
}

pub fn gemini_oauth_path() -> PathBuf {
    home().join(".gemini").join("oauth_creds.json")
}

/// Cursor state DB — Windows path.
pub fn cursor_state_db_path() -> PathBuf {
    dirs::data_dir()
        .unwrap_or_else(|| home().join("AppData").join("Roaming"))
        .join("Cursor")
        .join("User")
        .join("globalStorage")
        .join("state.vscdb")
}

pub fn ensure_config_dir() -> std::io::Result<PathBuf> {
    let dir = config_dir();
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}

pub fn ensure_logs_dir() -> std::io::Result<PathBuf> {
    let dir = logs_dir();
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}
