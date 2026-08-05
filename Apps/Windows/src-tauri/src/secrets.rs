//! Secure secret storage via OS keyring (Windows Credential Manager).

const SERVICE: &str = "com.smartquota.app";

pub fn set_secret(account: &str, value: &str) -> Result<(), String> {
    let entry = keyring::Entry::new(SERVICE, account).map_err(|e| e.to_string())?;
    if value.is_empty() {
        let _ = entry.delete_credential();
        return Ok(());
    }
    entry.set_password(value).map_err(|e| e.to_string())
}

pub fn get_secret(account: &str) -> Option<String> {
    let entry = keyring::Entry::new(SERVICE, account).ok()?;
    entry.get_password().ok().filter(|s| !s.is_empty())
}

pub fn delete_secret(account: &str) -> Result<(), String> {
    let entry = keyring::Entry::new(SERVICE, account).map_err(|e| e.to_string())?;
    match entry.delete_credential() {
        Ok(()) => Ok(()),
        Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}

pub const MINIMAX_API_KEY: &str = "minimax-api-key";
pub const KIMI_API_KEY: &str = "kimi-api-key";
pub const GITHUB_TOKEN: &str = "github-token";
pub const CLAUDE_API_KEY: &str = "claude-api-key";
pub const GENERIC_API_KEY_PREFIX: &str = "provider-key:";

pub fn provider_key_account(provider_id: &str) -> String {
    format!("{GENERIC_API_KEY_PREFIX}{provider_id}")
}
