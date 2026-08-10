use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::paths::{ensure_config_dir, config_dir};

/// Normalized account identity within a provider.
///
/// The `account_id` is derived from `provider_id` + `label` (not email),
/// ensuring stability across email changes.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub struct AccountIdentity {
    pub provider_id: String,
    #[serde(default)]
    pub normalized_email: Option<String>,
    pub label: String,
    pub account_id: String,
}

impl AccountIdentity {
    pub fn new(provider_id: &str, email: Option<&str>, label: &str) -> Self {
        let normalized_email = email.map(|e| normalize_email(e));
        let account_id = generate_account_id(provider_id, label);
        Self {
            provider_id: provider_id.to_string(),
            normalized_email,
            label: label.to_string(),
            account_id,
        }
    }
}

/// Normalize email: lowercase + trim whitespace.
pub fn normalize_email(email: &str) -> String {
    email.to_lowercase().trim().to_string()
}

/// Generate a stable account ID from provider + label using a simple hash.
///
/// Format: `{provider_id}.{hex_prefix}` where hex_prefix is the first 16 hex
/// chars of sha256(provider_id:label). We use a simple FNV-like hash here
/// since we don't need cryptographic strength — just determinism.
pub fn generate_account_id(provider_id: &str, label: &str) -> String {
    let input = format!("{provider_id}:{label}");
    let hash = fnv_hash_hex(&input, 16);
    format!("{provider_id}.{hash}")
}

/// Simple FNV-1a 64-bit hash, returned as hex string of requested length.
fn fnv_hash_hex(input: &str, hex_len: usize) -> String {
    let mut hash: u64 = 0xcbf29ce484222325; // FNV offset basis
    for byte in input.bytes() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x100000001b3); // FNV prime
    }
    let hex = format!("{hash:016x}");
    hex[..hex_len.min(hex.len())].to_string()
}

/// Connection state of an account.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AccountConnectionState {
    Connected,
    Disconnected,
    PendingConfirmation,
}

impl AccountConnectionState {
    pub fn is_active(&self) -> bool {
        matches!(self, Self::Connected | Self::PendingConfirmation)
    }
}

/// Full state of a provider account.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderAccountState {
    pub identity: AccountIdentity,
    pub connection_state: AccountConnectionState,
    pub label: String,
    #[serde(default)]
    pub email: Option<String>,
    #[serde(default)]
    pub organization: Option<String>,
    #[serde(default)]
    pub last_snapshot_json: Option<String>,
    #[serde(default)]
    pub last_snapshot_time: Option<String>,
}

impl ProviderAccountState {
    pub fn account_id(&self) -> &str {
        &self.identity.account_id
    }

    pub fn display_name(&self) -> &str {
        if !self.label.is_empty() {
            return &self.label;
        }
        self.email.as_deref().unwrap_or(&self.identity.account_id)
    }
}

/// Events that drive the account discovery state machine.
#[derive(Debug, Clone)]
pub enum AccountDiscoveryEvent {
    /// Ingest a snapshot with an optional email from probe result.
    Ingest {
        email: Option<String>,
        is_interactive: bool,
    },
    /// User confirms a pending account.
    Confirm { account_id: String },
    /// User ignores a pending account.
    Ignore { account_id: String },
    /// User signs out a connected account.
    SignOut { account_id: String },
    /// User selects an account as active.
    Select { account_id: String },
    /// User deletes an account.
    Delete { account_id: String },
}

/// Per-provider account coordinator.
///
/// Manages the state machine for all accounts of a single provider.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountCoordinator {
    pub provider_id: String,
    /// Active accounts (connected or disconnected, but confirmed).
    #[serde(default)]
    pub accounts: HashMap<String, ProviderAccountState>,
    /// Accounts awaiting user confirmation.
    #[serde(default)]
    pub pending: HashMap<String, ProviderAccountState>,
    /// Currently active account ID.
    #[serde(default)]
    pub active_account_id: Option<String>,
}

impl AccountCoordinator {
    pub fn new(provider_id: &str) -> Self {
        Self {
            provider_id: provider_id.to_string(),
            accounts: HashMap::new(),
            pending: HashMap::new(),
            active_account_id: None,
        }
    }

    /// Process a discovery event and return a description of what changed.
    pub fn process(&mut self, event: AccountDiscoveryEvent) -> AccountChange {
        match event {
            AccountDiscoveryEvent::Ingest { email, is_interactive } => {
                self.handle_ingest(email, is_interactive)
            }
            AccountDiscoveryEvent::Confirm { account_id } => self.handle_confirm(&account_id),
            AccountDiscoveryEvent::Ignore { account_id } => self.handle_ignore(&account_id),
            AccountDiscoveryEvent::SignOut { account_id } => self.handle_sign_out(&account_id),
            AccountDiscoveryEvent::Select { account_id } => self.handle_select(&account_id),
            AccountDiscoveryEvent::Delete { account_id } => self.handle_delete(&account_id),
        }
    }

    fn handle_ingest(&mut self, email: Option<String>, is_interactive: bool) -> AccountChange {
        let Some(email) = email else {
            return AccountChange::NoChange;
        };
        let normalized = normalize_email(&email);

        // Check if this email matches an existing account (case/whitespace insensitive)
        if let Some((id, _)) = self.find_account_by_email(&normalized) {
            let id = id.to_string();
            // Update existing account's email to latest normalized form
            if let Some(acct) = self.accounts.get_mut(&id) {
                acct.email = Some(email.clone());
                acct.identity.normalized_email = Some(normalized.clone());
            }
            // Ensure it's connected
            if let Some(acct) = self.accounts.get_mut(&id) {
                if acct.connection_state != AccountConnectionState::Connected {
                    acct.connection_state = AccountConnectionState::Connected;
                }
            }
            // Set as active if none
            if self.active_account_id.is_none() {
                self.active_account_id = Some(id.clone());
            }
            return AccountChange::ExistingAccountUpdated { account_id: id };
        }

        // No match found.
        if is_interactive {
            // First interactive refresh: auto-create as connected.
            // Background refresh with new email: create as pending.
            if self.accounts.is_empty() && self.pending.is_empty() {
                // No accounts at all — auto-create first account.
                let identity = AccountIdentity::new(&self.provider_id, Some(&email), &email);
                let account_id = identity.account_id.clone();
                let state = ProviderAccountState {
                    identity: identity.clone(),
                    connection_state: AccountConnectionState::Connected,
                    label: email.clone(),
                    email: Some(email),
                    organization: None,
                    last_snapshot_json: None,
                    last_snapshot_time: None,
                };
                self.accounts.insert(account_id.clone(), state);
                self.active_account_id = Some(account_id.clone());
                return AccountChange::NewAccountConnected { account_id };
            } else {
                // Existing accounts exist — new email becomes pending confirmation.
                let identity = AccountIdentity::new(&self.provider_id, Some(&email), &email);
                let account_id = identity.account_id.clone();
                let state = ProviderAccountState {
                    identity,
                    connection_state: AccountConnectionState::PendingConfirmation,
                    label: email.clone(),
                    email: Some(email),
                    organization: None,
                    last_snapshot_json: None,
                    last_snapshot_time: None,
                };
                self.pending.insert(account_id.clone(), state);
                return AccountChange::NewAccountPending { account_id };
            }
        }

        // Background refresh with new email — do nothing.
        AccountChange::NoChange
    }

    fn handle_confirm(&mut self, account_id: &str) -> AccountChange {
        if let Some(mut state) = self.pending.remove(account_id) {
            state.connection_state = AccountConnectionState::Connected;
            let id = state.identity.account_id.clone();
            self.accounts.insert(id.clone(), state);
            if self.active_account_id.is_none() {
                self.active_account_id = Some(id.clone());
            }
            AccountChange::AccountConfirmed { account_id: id }
        } else {
            AccountChange::NoChange
        }
    }

    fn handle_ignore(&mut self, account_id: &str) -> AccountChange {
        if self.pending.remove(account_id).is_some() {
            AccountChange::AccountIgnored {
                account_id: account_id.to_string(),
            }
        } else {
            AccountChange::NoChange
        }
    }

    fn handle_sign_out(&mut self, account_id: &str) -> AccountChange {
        if let Some(acct) = self.accounts.get_mut(account_id) {
            acct.connection_state = AccountConnectionState::Disconnected;
            AccountChange::AccountSignedOut {
                account_id: account_id.to_string(),
            }
        } else {
            AccountChange::NoChange
        }
    }

    fn handle_select(&mut self, account_id: &str) -> AccountChange {
        if self.accounts.contains_key(account_id) {
            self.active_account_id = Some(account_id.to_string());
            AccountChange::AccountSelected {
                account_id: account_id.to_string(),
            }
        } else {
            AccountChange::NoChange
        }
    }

    fn handle_delete(&mut self, account_id: &str) -> AccountChange {
        let removed_from_accounts = self.accounts.remove(account_id).is_some();
        let removed_from_pending = self.pending.remove(account_id).is_some();
        if removed_from_accounts || removed_from_pending {
            if self.active_account_id.as_deref() == Some(account_id) {
                self.active_account_id = self.accounts.keys().next().cloned();
            }
            AccountChange::AccountDeleted {
                account_id: account_id.to_string(),
            }
        } else {
            AccountChange::NoChange
        }
    }

    /// Find an account (in active or pending) by normalized email.
    /// Returns (account_id, is_pending).
    fn find_account_by_email(&self, normalized_email: &str) -> Option<(String, bool)> {
        for (id, acct) in &self.accounts {
            if acct.identity.normalized_email.as_deref() == Some(normalized_email) {
                return Some((id.clone(), false));
            }
        }
        for (id, acct) in &self.pending {
            if acct.identity.normalized_email.as_deref() == Some(normalized_email) {
                return Some((id.clone(), true));
            }
        }
        None
    }

    /// List all accounts (active + pending) for display.
    pub fn all_accounts(&self) -> Vec<&ProviderAccountState> {
        let mut list: Vec<&ProviderAccountState> = self.accounts.values().collect();
        list.extend(self.pending.values());
        list
    }

    /// List pending accounts only.
    pub fn pending_accounts(&self) -> Vec<&ProviderAccountState> {
        self.pending.values().collect()
    }

    /// Get the active account.
    pub fn active_account(&self) -> Option<&ProviderAccountState> {
        self.active_account_id
            .as_ref()
            .and_then(|id| self.accounts.get(id))
    }
}

/// Describes what changed after processing an event.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AccountChange {
    NoChange,
    NewAccountConnected { account_id: String },
    NewAccountPending { account_id: String },
    ExistingAccountUpdated { account_id: String },
    AccountConfirmed { account_id: String },
    AccountIgnored { account_id: String },
    AccountSignedOut { account_id: String },
    AccountSelected { account_id: String },
    AccountDeleted { account_id: String },
}

/// Multi-account state for all providers.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct MultiAccountState {
    #[serde(default)]
    pub coordinators: HashMap<String, AccountCoordinator>,
}

impl MultiAccountState {
    pub fn load() -> Self {
        let path = state_path();
        match std::fs::read_to_string(&path) {
            Ok(text) => serde_json::from_str(&text).unwrap_or_default(),
            Err(_) => Self::default(),
        }
    }

    pub fn save(&self) -> Result<(), String> {
        ensure_config_dir().map_err(|e| e.to_string())?;
        let path = state_path();
        let text = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        std::fs::write(path, text).map_err(|e| e.to_string())
    }

    pub fn coordinator_mut(&mut self, provider_id: &str) -> &mut AccountCoordinator {
        self.coordinators
            .entry(provider_id.to_string())
            .or_insert_with(|| AccountCoordinator::new(provider_id))
    }

    pub fn coordinator(&self, provider_id: &str) -> Option<&AccountCoordinator> {
        self.coordinators.get(provider_id)
    }
}

fn state_path() -> std::path::PathBuf {
    config_dir().join("accounts.json")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_email_lowercase_and_trim() {
        assert_eq!(normalize_email("  User@Example.COM  "), "user@example.com");
        assert_eq!(normalize_email("FIRST@Example.com"), "first@example.com");
        assert_eq!(normalize_email(" first@example.com "), "first@example.com");
    }

    #[test]
    fn generate_account_id_deterministic() {
        let a = generate_account_id("codex", "personal");
        let b = generate_account_id("codex", "personal");
        assert_eq!(a, b);
        assert!(a.starts_with("codex."));
    }

    #[test]
    fn generate_account_id_different_labels() {
        let a = generate_account_id("codex", "personal");
        let b = generate_account_id("codex", "work");
        assert_ne!(a, b);
    }

    #[test]
    fn generate_account_id_different_providers() {
        let a = generate_account_id("codex", "test");
        let b = generate_account_id("claude", "test");
        assert_ne!(a, b);
    }

    // ---- State machine tests (aligned with Mac MultiAccountMembershipSpec) ----

    #[test]
    fn first_refresh_creates_signed_in_account() {
        let mut coord = AccountCoordinator::new("codex");

        let change = coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("first@example.com".into()),
            is_interactive: true,
        });

        assert!(matches!(change, AccountChange::NewAccountConnected { .. }));
        assert_eq!(coord.accounts.len(), 1);
        assert_eq!(coord.pending.len(), 0);

        let acct = coord.accounts.values().next().unwrap();
        assert_eq!(acct.email.as_deref(), Some("first@example.com"));
        assert_eq!(acct.connection_state, AccountConnectionState::Connected);
        assert!(coord.active_account_id.is_some());
    }

    #[test]
    fn same_email_case_whitespace_does_not_duplicate() {
        let mut coord = AccountCoordinator::new("codex");

        // First refresh
        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("First@Example.com".into()),
            is_interactive: true,
        });
        assert_eq!(coord.accounts.len(), 1);

        // Second refresh with different case + whitespace
        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some(" first@example.com ".into()),
            is_interactive: true,
        });

        assert_eq!(coord.accounts.len(), 1);
        assert_eq!(coord.pending.len(), 0);
    }

    #[test]
    fn new_email_interactive_becomes_pending() {
        let mut coord = AccountCoordinator::new("codex");

        // Establish account A
        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("account-a@example.com".into()),
            is_interactive: true,
        });
        assert_eq!(coord.accounts.len(), 1);

        // New email discovered interactively
        let change = coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("account-b@example.com".into()),
            is_interactive: true,
        });

        assert!(matches!(change, AccountChange::NewAccountPending { .. }));
        assert_eq!(coord.accounts.len(), 1);
        assert_eq!(coord.pending.len(), 1);
        assert!(coord.pending.values().any(|a| a.email.as_deref() == Some("account-b@example.com")));
    }

    #[test]
    fn background_refresh_does_not_auto_add() {
        let mut coord = AccountCoordinator::new("codex");

        // Establish account A interactively
        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("account-a@example.com".into()),
            is_interactive: true,
        });
        let count_before = coord.accounts.len();

        // Background refresh with new email
        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("account-b@example.com".into()),
            is_interactive: false,
        });

        assert_eq!(coord.accounts.len(), count_before);
        assert_eq!(coord.pending.len(), 0);
    }

    #[test]
    fn signed_out_retains_snapshot() {
        let mut coord = AccountCoordinator::new("codex");

        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("account-a@example.com".into()),
            is_interactive: true,
        });

        let account_id = coord.accounts.keys().next().unwrap().clone();

        // Sign out
        let change = coord.process(AccountDiscoveryEvent::SignOut {
            account_id: account_id.clone(),
        });
        assert!(matches!(change, AccountChange::AccountSignedOut { .. }));

        let acct = coord.accounts.get(&account_id).unwrap();
        assert_eq!(acct.connection_state, AccountConnectionState::Disconnected);
    }

    #[test]
    fn confirm_moves_pending_to_connected() {
        let mut coord = AccountCoordinator::new("codex");

        // First account auto-created
        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("a@example.com".into()),
            is_interactive: true,
        });

        // Second account becomes pending
        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("b@example.com".into()),
            is_interactive: true,
        });
        assert_eq!(coord.pending.len(), 1);

        let pending_id = coord.pending.keys().next().unwrap().clone();

        // Confirm
        let change = coord.process(AccountDiscoveryEvent::Confirm {
            account_id: pending_id.clone(),
        });
        assert!(matches!(change, AccountChange::AccountConfirmed { .. }));
        assert_eq!(coord.pending.len(), 0);
        assert_eq!(coord.accounts.len(), 2);
        assert!(coord.accounts.contains_key(&pending_id));
    }

    #[test]
    fn ignore_removes_pending() {
        let mut coord = AccountCoordinator::new("codex");

        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("a@example.com".into()),
            is_interactive: true,
        });
        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("b@example.com".into()),
            is_interactive: true,
        });
        assert_eq!(coord.pending.len(), 1);

        let pending_id = coord.pending.keys().next().unwrap().clone();
        coord.process(AccountDiscoveryEvent::Ignore {
            account_id: pending_id,
        });
        assert_eq!(coord.pending.len(), 0);
        assert_eq!(coord.accounts.len(), 1);
    }

    #[test]
    fn delete_removes_account() {
        let mut coord = AccountCoordinator::new("codex");

        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("a@example.com".into()),
            is_interactive: true,
        });
        let account_id = coord.accounts.keys().next().unwrap().clone();

        let change = coord.process(AccountDiscoveryEvent::Delete {
            account_id: account_id.clone(),
        });
        assert!(matches!(change, AccountChange::AccountDeleted { .. }));
        assert_eq!(coord.accounts.len(), 0);
        assert!(coord.active_account_id.is_none());
    }

    #[test]
    fn select_changes_active_account() {
        let mut coord = AccountCoordinator::new("codex");

        // Create first account
        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("a@example.com".into()),
            is_interactive: true,
        });
        let first_id = coord.active_account_id.clone().unwrap();

        // Create second (pending) then confirm
        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("b@example.com".into()),
            is_interactive: true,
        });
        let pending_id = coord.pending.keys().next().unwrap().clone();
        coord.process(AccountDiscoveryEvent::Confirm {
            account_id: pending_id.clone(),
        });

        // Select second account
        let change = coord.process(AccountDiscoveryEvent::Select {
            account_id: pending_id.clone(),
        });
        assert!(matches!(change, AccountChange::AccountSelected { .. }));
        assert_eq!(coord.active_account_id.as_deref(), Some(pending_id.as_str()));
        assert_ne!(coord.active_account_id.as_deref(), Some(first_id.as_str()));
    }

    #[test]
    fn alert_isolation_only_connected_accounts() {
        let mut coord = AccountCoordinator::new("codex");

        // Account A signed in
        coord.process(AccountDiscoveryEvent::Ingest {
            email: Some("a@example.com".into()),
            is_interactive: true,
        });
        let a_id = coord.accounts.keys().next().unwrap().clone();

        // Account A signs out
        coord.process(AccountDiscoveryEvent::SignOut {
            account_id: a_id.clone(),
        });

        // Verify A is disconnected
        let a = coord.accounts.get(&a_id).unwrap();
        assert_eq!(a.connection_state, AccountConnectionState::Disconnected);
        assert!(!a.connection_state.is_active());

        // Only connected accounts should be considered for alerts
        let active_accounts: Vec<_> = coord
            .accounts
            .values()
            .filter(|a| a.connection_state.is_active())
            .collect();
        assert_eq!(active_accounts.len(), 0);
    }
}
