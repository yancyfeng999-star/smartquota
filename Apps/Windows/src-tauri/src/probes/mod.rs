mod codex;
mod grok;
mod minimax;

pub use codex::probe_codex;
pub use grok::probe_grok;
pub use minimax::probe_minimax;

use crate::models::{session_weekly_from_meters, status_from_remaining, QuotaCard, QuotaMeter};
use crate::settings::AppSettings;

pub async fn probe_provider(id: &str, settings: &AppSettings) -> QuotaCard {
    let display_name = match id {
        "codex" => "ChatGPT (Codex)",
        "minimax" => "MiniMax",
        "grok" => "Grok",
        other => other,
    }
    .to_string();

    let plan_label = settings.plan_label(id);
    let enabled = settings.is_enabled(id);

    if !enabled {
        return QuotaCard {
            provider_id: id.into(),
            display_name,
            status: "disabled".into(),
            session_remaining_percent: None,
            weekly_remaining_percent: None,
            meters: vec![],
            plan_label,
            detail: "已关闭（在设置中开启）".into(),
            enabled: false,
        };
    }

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
                    "探测成功".into()
                } else {
                    detail
                },
                enabled: true,
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
            detail: msg,
            enabled: true,
        },
    }
}

