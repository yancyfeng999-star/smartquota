pub mod alibaba;
pub mod ampcode;
pub mod antigravity;
pub mod bedrock;
pub mod claude;
pub mod codex;
pub mod copilot;
pub mod cursor;
pub mod gemini;
pub mod grok;
pub mod kimi;
pub mod kiro;
pub mod minimax;
pub mod mistral;
pub mod omp;
pub mod opencode;
pub mod zai;

use crate::catalog;
use crate::detect;
use crate::models::{session_weekly_from_meters, status_from_meters, QuotaCard};
use crate::settings::AppSettings;

pub async fn probe_provider(id: &str, settings: &AppSettings) -> QuotaCard {
    let display_name = catalog::display_name(id).to_string();
    let plan_label = settings.plan_label(id);
    let enabled = settings.is_enabled(id);
    let is_core = catalog::is_core(id);
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
            is_core,
            account_id: None,
            account_email: None,
            account_label: None,
            account_state: None,
        };
    }

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
                is_core,
                account_id: None,
                account_email: None,
                account_label: None,
                account_state: None,
            };
        }
    }

    let source_mode = det
        .as_ref()
        .map(|d| d.mode.clone())
        .unwrap_or_else(|| "none".into());

    let result = match id {
        "codex" => codex::probe_codex().await,
        "kimi" => kimi::probe_kimi().await,
        "minimax" => minimax::probe_minimax(settings).await,
        "grok" => grok::probe_grok().await,
        "claude" => claude::probe_claude().await,
        "gemini" => gemini::probe_gemini().await,
        "copilot" => copilot::probe_copilot().await,
        "cursor" => cursor::probe_cursor().await,
        "zai" => zai::probe_zai().await,
        "alibaba" => alibaba::probe_alibaba(settings).await,
        "ampcode" => ampcode::probe_ampcode().await,
        "kiro" => kiro::probe_kiro().await,
        "opencode-go" => opencode::probe_opencode().await,
        "omp" => omp::probe_omp().await,
        "mistral" => mistral::probe_mistral().await,
        "antigravity" => antigravity::probe_antigravity().await,
        "bedrock" => bedrock::probe_bedrock().await,
        other => Err(format!("未知会员: {other}")),
    };

    match result {
        Ok(meters) => {
            let (session, weekly) = session_weekly_from_meters(&meters);
            let status = status_from_meters(&meters);
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
                is_core,
                account_id: None,
                account_email: None,
                account_label: None,
                account_state: None,
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
            is_core,
            account_id: None,
            account_email: None,
            account_label: None,
            account_state: None,
        },
    }
}
