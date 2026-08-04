mod codex;
mod grok;
mod minimax;

pub use codex::probe_codex;
pub use grok::probe_grok;
pub use minimax::probe_minimax;

use crate::detect;
use crate::models::{session_weekly_from_meters, status_from_remaining, QuotaCard};
use crate::settings::AppSettings;

pub async fn probe_provider(id: &str, settings: &AppSettings) -> QuotaCard {
    let display_name = match id {
        "codex" => "ChatGPT (Codex)",
        "minimax" => "MiniMax",
        "grok" => "Grok",
        other => other,
    }
    .to_string();

    // Only user-filled plan name — never invent tiers for them
    let plan_label = settings.plan_label(id);
    let enabled = settings.is_enabled(id);
    let det = detect::detect_all(settings)
        .into_iter()
        .find(|d| d.provider_id == id);

    if !enabled {
        return QuotaCard {
            provider_id: id.into(),
            display_name,
            status: "disabled".into(),
            session_remaining_percent: None,
            weekly_remaining_percent: None,
            meters: vec![],
            plan_label,
            detail: "已关闭。在「设置」中打开后才会探测。".into(),
            enabled: false,
            source_mode: "none".into(),
        };
    }

    // Not ready to probe — guide user to fill/login (not an "app error")
    if let Some(ref d) = det {
        if !d.ready {
            return QuotaCard {
                provider_id: id.into(),
                display_name,
                status: "setup".into(),
                session_remaining_percent: None,
                weekly_remaining_percent: None,
                meters: vec![],
                plan_label,
                detail: format!("{} — {}", d.summary, d.how_to),
                enabled: true,
                source_mode: d.mode.clone(),
            };
        }
    }

    let source_mode = det
        .as_ref()
        .map(|d| d.mode.clone())
        .unwrap_or_else(|| "none".into());

    let result = match id {
        "codex" => probe_codex().await,
        "minimax" => probe_minimax(settings).await,
        "grok" => probe_grok().await,
        _ => Err("未知会员".into()),
    };

    match result {
        Ok(meters) => {
            let (session, weekly) = session_weekly_from_meters(&meters);
            let status = status_from_remaining(session, weekly);
            let detail = meters
                .iter()
                .filter_map(|m| m.reset_text.as_ref().map(|t| format!("{}: {}", m.label, t)))
                .collect::<Vec<_>>()
                .join(" · ");
            QuotaCard {
                provider_id: id.into(),
                display_name,
                status,
                session_remaining_percent: session,
                weekly_remaining_percent: weekly,
                meters,
                plan_label,
                detail: if detail.is_empty() {
                    "已根据本机登录态查询成功".into()
                } else {
                    detail
                },
                enabled: true,
                source_mode,
            }
        }
        Err(msg) => QuotaCard {
            provider_id: id.into(),
            display_name,
            status: "error".into(),
            session_remaining_percent: None,
            weekly_remaining_percent: None,
            meters: vec![],
            plan_label,
            detail: format!(
                "{msg}。若无法自动识别，请到「设置」按说明自行填写或重新登录对应 CLI。"
            ),
            enabled: true,
            source_mode,
        },
    }
}

