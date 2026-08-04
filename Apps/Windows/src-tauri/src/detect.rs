//! Pure detection of local credentials — no personal data, no network.

use crate::paths::{codex_auth_path, grok_auth_path, minimax_config_path};
use crate::secrets::{self, MINIMAX_API_KEY};
use crate::settings::AppSettings;
use serde::{Deserialize, Serialize};
use std::fs;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DetectItem {
    pub provider_id: String,
    pub display_name: String,
    /// auto | manual | none
    pub mode: String,
    /// Whether enough local material exists to attempt a probe
    pub ready: bool,
    /// Short status for UI
    pub summary: String,
    /// What the user should do if not ready
    pub how_to: String,
}

pub fn detect_all(settings: &AppSettings) -> Vec<DetectItem> {
    vec![
        detect_codex(),
        detect_minimax(settings),
        detect_grok(),
    ]
}

fn detect_codex() -> DetectItem {
    let path = codex_auth_path();
    if !path.exists() {
        return DetectItem {
            provider_id: "codex".into(),
            display_name: "ChatGPT (Codex)".into(),
            mode: "none".into(),
            ready: false,
            summary: "未识别到本机登录".into(),
            how_to: "安装 Codex CLI 并登录（会生成 %USERPROFILE%\\.codex\\auth.json），然后点刷新。本软件不代你登录。".into(),
        };
    }
    let text = fs::read_to_string(&path).unwrap_or_default();
    let ok = text.contains("access_token");
    if ok {
        DetectItem {
            provider_id: "codex".into(),
            display_name: "ChatGPT (Codex)".into(),
            mode: "auto".into(),
            ready: true,
            summary: "已识别本机 Codex 登录文件".into(),
            how_to: "可自动查额度。套餐名可在设置里自行填写（可选）。".into(),
        }
    } else {
        DetectItem {
            provider_id: "codex".into(),
            display_name: "ChatGPT (Codex)".into(),
            mode: "none".into(),
            ready: false,
            summary: "找到 auth.json 但无 OAuth token".into(),
            how_to: "请重新运行 codex 登录。仅 API Key 的方式无法查额度。".into(),
        }
    }
}

fn detect_grok() -> DetectItem {
    let path = grok_auth_path();
    if !path.exists() {
        return DetectItem {
            provider_id: "grok".into(),
            display_name: "Grok".into(),
            mode: "none".into(),
            ready: false,
            summary: "未识别到本机登录".into(),
            how_to: "安装 grok CLI 并执行 grok login（生成 %USERPROFILE%\\.grok\\auth.json）。".into(),
        };
    }
    let text = fs::read_to_string(&path).unwrap_or_default();
    let ok = text.contains("\"key\"") || text.contains("access_token");
    DetectItem {
        provider_id: "grok".into(),
        display_name: "Grok".into(),
        mode: if ok { "auto" } else { "none" }.into(),
        ready: ok,
        summary: if ok {
            "已识别本机 Grok 登录文件".into()
        } else {
            "auth.json 存在但无法解析 token".into()
        },
        how_to: if ok {
            "可自动查额度。套餐名可选填。".into()
        } else {
            "请重新 grok login。".into()
        },
    }
}

fn detect_minimax(settings: &AppSettings) -> DetectItem {
    let has_user_key = secrets::get_secret(MINIMAX_API_KEY).is_some();
    let env_name = if settings.minimax_auth_env_var.is_empty() {
        "MINIMAX_API_KEY"
    } else {
        settings.minimax_auth_env_var.as_str()
    };
    let has_env = std::env::var(env_name).map(|v| !v.is_empty()).unwrap_or(false);
    let has_file = minimax_config_path().exists()
        && fs::read_to_string(minimax_config_path())
            .map(|t| t.contains("sk-cp-"))
            .unwrap_or(false);

    if has_user_key {
        return DetectItem {
            provider_id: "minimax".into(),
            display_name: "MiniMax".into(),
            mode: "manual".into(),
            ready: true,
            summary: "已使用你在设置中填写的 API Key".into(),
            how_to: "Key 仅保存在本机凭据管理器，可随时清除。请确认区域（中国/国际）与 Key 匹配。".into(),
        };
    }
    if has_env {
        return DetectItem {
            provider_id: "minimax".into(),
            display_name: "MiniMax".into(),
            mode: "auto".into(),
            ready: true,
            summary: format!("已识别环境变量 {env_name}"),
            how_to: "也可在设置中填写 Key（优先使用设置里的 Key）。".into(),
        };
    }
    if has_file {
        return DetectItem {
            provider_id: "minimax".into(),
            display_name: "MiniMax".into(),
            mode: "auto".into(),
            ready: true,
            summary: "已识别本机 .minimax\\config.yaml 中的 Coding Plan Key".into(),
            how_to: "若探测失败，请在设置中手动粘贴 sk-cp-… Key。".into(),
        };
    }
    DetectItem {
        provider_id: "minimax".into(),
        display_name: "MiniMax".into(),
        mode: "none".into(),
        ready: false,
        summary: "未识别到 Key".into(),
        how_to: "在设置 → MiniMax 中粘贴你的 Coding Plan API Key（sk-cp-…），并选择区域。Key 只存在你的电脑上。".into(),
    }
}
