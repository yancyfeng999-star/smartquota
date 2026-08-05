//! Provider catalog — mirrors Mac `ProviderCatalog`.

/// Core products enabled by default (Mac coreProviderIDs).
pub const CORE_PROVIDER_IDS: &[&str] = &["codex", "kimi", "minimax", "grok"];

/// Stable display order (Mac displayOrder).
pub const DISPLAY_ORDER: &[&str] = &[
    "codex",
    "kimi",
    "minimax",
    "grok",
    "claude",
    "gemini",
    "copilot",
    "cursor",
    "antigravity",
    "zai",
    "bedrock",
    "alibaba",
    "ampcode",
    "kiro",
    "mistral",
    "opencode-go",
    "omp",
];

pub fn display_name(id: &str) -> &'static str {
    match id {
        "codex" => "ChatGPT (Codex)",
        "kimi" => "Kimi",
        "minimax" => "MiniMax",
        "grok" => "Grok",
        "claude" => "Claude",
        "gemini" => "Gemini",
        "copilot" => "GitHub Copilot",
        "cursor" => "Cursor",
        "antigravity" => "Antigravity",
        "zai" => "Z.ai",
        "bedrock" => "AWS Bedrock",
        "alibaba" => "通义 / Alibaba",
        "ampcode" => "AmpCode",
        "kiro" => "Kiro",
        "mistral" => "Mistral",
        "opencode-go" => "OpenCode Go",
        "omp" => "Oh My Pi",
        _ => "Unknown",
    }
}

pub fn is_core(id: &str) -> bool {
    CORE_PROVIDER_IDS.contains(&id)
}

/// Default enabled: core on, extensions off (Mac behavior).
pub fn default_enabled(id: &str) -> bool {
    is_core(id)
}
