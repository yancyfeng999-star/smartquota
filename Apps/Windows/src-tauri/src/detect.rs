//! Pure detection of local credentials — no personal data, no network.

use crate::catalog::{self, DISPLAY_ORDER};
use crate::paths::{
    claude_dir, claude_json_path, codex_auth_path, cursor_state_db_path, gemini_oauth_path,
    grok_auth_path, kimi_config_path, minimax_config_path,
};
use crate::secrets::{self, provider_key_account, GITHUB_TOKEN, KIMI_API_KEY, MINIMAX_API_KEY};
use crate::settings::AppSettings;
use serde::{Deserialize, Serialize};
use std::fs;
use std::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DetectItem {
    pub provider_id: String,
    pub display_name: String,
    pub mode: String,
    pub ready: bool,
    pub summary: String,
    pub how_to: String,
}

pub fn detect_all(settings: &AppSettings) -> Vec<DetectItem> {
    DISPLAY_ORDER
        .iter()
        .map(|id| detect_one(id, settings))
        .collect()
}

fn detect_one(id: &str, settings: &AppSettings) -> DetectItem {
    match id {
        "codex" => detect_codex(),
        "kimi" => detect_kimi(),
        "minimax" => detect_minimax(settings),
        "grok" => detect_grok(),
        "claude" => detect_claude(),
        "gemini" => detect_gemini(),
        "copilot" => detect_copilot(),
        "cursor" => detect_cursor(),
        "zai" => detect_zai(),
        "alibaba" => detect_key("alibaba", &["ALIBABA_API_KEY", "DASHSCOPE_API_KEY"]),
        "ampcode" => detect_cli("ampcode", "amp", "安装 AmpCode CLI (amp)"),
        "kiro" => detect_cli_multi("kiro", &["kiro-cli", "kiro"], "安装 kiro-cli"),
        "opencode-go" => detect_cli("opencode-go", "opencode", "安装 opencode CLI"),
        "omp" => detect_cli("omp", "omp", "安装 Oh My Pi (omp)"),
        "mistral" => detect_mistral(),
        "antigravity" => detect_antigravity(),
        "bedrock" => detect_bedrock(),
        other => detect_extra(other),
    }
}

fn item(id: &str, mode: &str, ready: bool, summary: &str, how_to: &str) -> DetectItem {
    DetectItem {
        provider_id: id.into(),
        display_name: catalog::display_name(id).into(),
        mode: mode.into(),
        ready,
        summary: summary.into(),
        how_to: how_to.into(),
    }
}

fn detect_codex() -> DetectItem {
    let path = codex_auth_path();
    if !path.exists() {
        return item(
            "codex",
            "none",
            false,
            "未识别到本机登录",
            "安装 Codex CLI 并登录（%USERPROFILE%\\.codex\\auth.json）",
        );
    }
    let ok = fs::read_to_string(&path)
        .map(|t| t.contains("access_token"))
        .unwrap_or(false);
    item(
        "codex",
        if ok { "auto" } else { "none" },
        ok,
        if ok {
            "已识别本机 Codex 登录文件"
        } else {
            "找到 auth.json 但无 OAuth token"
        },
        if ok {
            "可自动查额度"
        } else {
            "请重新 codex 登录"
        },
    )
}

fn detect_kimi() -> DetectItem {
    if secrets::get_secret(KIMI_API_KEY).is_some() {
        return item("kimi", "manual", true, "已保存 Kimi API Key", "sk-kimi Coding Key");
    }
    if std::env::var("KIMI_API_KEY").map(|v| !v.is_empty()).unwrap_or(false)
        || std::env::var("KIMI_CODE_API_KEY")
            .map(|v| !v.is_empty())
            .unwrap_or(false)
    {
        return item("kimi", "auto", true, "已识别 Kimi 环境变量", "也可在设置填写");
    }
    if kimi_config_path().exists() {
        return item("kimi", "auto", true, "已识别 .kimi 配置", "若失败请粘贴 sk-kimi");
    }
    item(
        "kimi",
        "none",
        false,
        "未识别到 Kimi Key",
        "设置中粘贴 sk-kimi-… Coding Key",
    )
}

fn detect_minimax(settings: &AppSettings) -> DetectItem {
    if secrets::get_secret(MINIMAX_API_KEY).is_some() {
        return item("minimax", "manual", true, "已保存 MiniMax Key", "确认区域匹配");
    }
    let env_name = if settings.minimax_auth_env_var.is_empty() {
        "MINIMAX_API_KEY"
    } else {
        settings.minimax_auth_env_var.as_str()
    };
    if std::env::var(env_name).map(|v| !v.is_empty()).unwrap_or(false) {
        return item(
            "minimax",
            "auto",
            true,
            &format!("环境变量 {env_name}"),
            "也可设置中填写",
        );
    }
    if minimax_config_path().exists() {
        return item(
            "minimax",
            "auto",
            true,
            "已识别 .minimax\\config.yaml",
            "若失败请粘贴 sk-cp-…",
        );
    }
    item(
        "minimax",
        "none",
        false,
        "未识别到 Key",
        "设置中粘贴 Coding Plan Key 并选区域",
    )
}

fn detect_grok() -> DetectItem {
    let path = grok_auth_path();
    if !path.exists() {
        return item(
            "grok",
            "none",
            false,
            "未识别到本机登录",
            "grok login → %USERPROFILE%\\.grok\\auth.json",
        );
    }
    let ok = fs::read_to_string(&path)
        .map(|t| t.contains("\"key\"") || t.contains("access_token"))
        .unwrap_or(false);
    item(
        "grok",
        if ok { "auto" } else { "none" },
        ok,
        if ok {
            "已识别 Grok 登录"
        } else {
            "auth.json 无法解析"
        },
        if ok { "可自动查额度" } else { "重新 grok login" },
    )
}

fn detect_claude() -> DetectItem {
    if claude_json_path().exists() || claude_dir().exists() {
        item(
            "claude",
            "auto",
            true,
            "已识别 Claude 配置",
            "调用 claude /usage（需 CLI 在 PATH）",
        )
    } else {
        item(
            "claude",
            "none",
            false,
            "未识别到 Claude",
            "安装 Claude Code 并 claude login",
        )
    }
}

fn detect_gemini() -> DetectItem {
    if gemini_oauth_path().exists() {
        item(
            "gemini",
            "auto",
            true,
            "已识别 gemini oauth_creds",
            "失败请重新 gemini 登录",
        )
    } else {
        item(
            "gemini",
            "none",
            false,
            "未识别 Gemini OAuth",
            "%USERPROFILE%\\.gemini\\oauth_creds.json",
        )
    }
}

fn detect_copilot() -> DetectItem {
    let has = secrets::get_secret(GITHUB_TOKEN).is_some()
        || ["GITHUB_TOKEN", "GH_TOKEN", "COPILOT_GITHUB_TOKEN"]
            .iter()
            .any(|e| std::env::var(e).map(|v| !v.is_empty()).unwrap_or(false));
    if has {
        item(
            "copilot",
            if secrets::get_secret(GITHUB_TOKEN).is_some() {
                "manual"
            } else {
                "auto"
            },
            true,
            "已识别 GitHub Token",
            "Classic PAT + copilot 权限",
        )
    } else {
        item(
            "copilot",
            "none",
            false,
            "未识别 Token",
            "设置中填写 GitHub Token",
        )
    }
}

fn detect_cursor() -> DetectItem {
    if cursor_state_db_path().exists() {
        item(
            "cursor",
            "auto",
            true,
            "已识别 Cursor 数据库",
            "建议安装 sqlite3",
        )
    } else {
        item(
            "cursor",
            "none",
            false,
            "未找到 Cursor 状态库",
            "安装并登录 Cursor",
        )
    }
}

fn detect_zai() -> DetectItem {
    if crate::probes::zai::has_config() {
        item(
            "zai",
            "auto",
            true,
            "已识别 Z.ai Key / Claude settings",
            "或设置 ZAI_API_KEY",
        )
    } else {
        item(
            "zai",
            "none",
            false,
            "未配置 Z.ai",
            "扩展 Key 或 ~/.claude/settings.json",
        )
    }
}

fn detect_key(id: &str, envs: &[&str]) -> DetectItem {
    if secrets::get_secret(&provider_key_account(id)).is_some() {
        return item(id, "manual", true, "已保存 API Key", "凭据管理器");
    }
    if envs
        .iter()
        .any(|e| std::env::var(e).map(|v| !v.is_empty()).unwrap_or(false))
    {
        return item(id, "auto", true, "已识别环境变量", "也可设置中填写");
    }
    item(id, "none", false, "未配置 Key", "设置中填写 API Key")
}

fn detect_cli(id: &str, bin: &str, how: &str) -> DetectItem {
    let ok = Command::new(bin).arg("--help").output().is_ok();
    if ok {
        item(id, "auto", true, &format!("已找到 {bin}"), "可探测")
    } else {
        item(id, "none", false, &format!("未找到 {bin}"), how)
    }
}

fn detect_cli_multi(id: &str, bins: &[&str], how: &str) -> DetectItem {
    for b in bins {
        if Command::new(b).arg("--help").output().is_ok() {
            return item(id, "auto", true, &format!("已找到 {b}"), "可探测");
        }
    }
    item(id, "none", false, "未找到 CLI", how)
}

fn detect_mistral() -> DetectItem {
    if dirs::home_dir()
        .map(|h| h.join(".vibe").join("logs").join("session").exists())
        .unwrap_or(false)
    {
        item(
            "mistral",
            "auto",
            true,
            "已识别 Vibe 会话日志",
            "~/.vibe/logs/session",
        )
    } else {
        item(
            "mistral",
            "none",
            false,
            "未找到 Vibe 日志",
            "安装 Vibe 并产生会话",
        )
    }
}

fn detect_antigravity() -> DetectItem {
    if crate::probes::antigravity::available() {
        item(
            "antigravity",
            "auto",
            true,
            "检测到 language_server 进程",
            "将扫描本地端口",
        )
    } else {
        item(
            "antigravity",
            "none",
            false,
            "未运行 Antigravity",
            "启动 Antigravity 后再刷新",
        )
    }
}

fn detect_bedrock() -> DetectItem {
    let aws = Command::new("aws").arg("--version").output().is_ok();
    let creds = dirs::home_dir()
        .map(|h| h.join(".aws").join("credentials").exists())
        .unwrap_or(false);
    if aws && creds {
        item(
            "bedrock",
            "auto",
            true,
            "AWS CLI + credentials 就绪",
            "需 bedrock 权限",
        )
    } else if creds {
        item(
            "bedrock",
            "none",
            false,
            "有 credentials 但无 aws CLI",
            "安装 AWS CLI",
        )
    } else {
        item(
            "bedrock",
            "none",
            false,
            "未配置 AWS",
            "~/.aws/credentials + AWS CLI",
        )
    }
}

fn detect_extra(id: &str) -> DetectItem {
    detect_key(id, &[])
}
