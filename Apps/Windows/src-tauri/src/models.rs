use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaMeter {
    pub label: String,
    /// Remaining percent 0–100 (or null if unknown)
    pub remaining_percent: Option<f64>,
    pub reset_text: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaCard {
    pub provider_id: String,
    pub display_name: String,
    /// healthy | warning | critical | depleted | unknown | error | disabled
    pub status: String,
    pub session_remaining_percent: Option<f64>,
    pub weekly_remaining_percent: Option<f64>,
    pub meters: Vec<QuotaMeter>,
    pub plan_label: String,
    pub detail: String,
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotPayload {
    pub updated_at: String,
    pub cards: Vec<QuotaCard>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProbeTestResult {
    pub ok: bool,
    pub message: String,
}

pub fn status_from_remaining(session: Option<f64>, weekly: Option<f64>) -> String {
    let worst = [session, weekly]
        .into_iter()
        .flatten()
        .fold(None, |acc: Option<f64>, v| {
            Some(acc.map(|a| a.min(v)).unwrap_or(v))
        });
    match worst {
        None => "unknown".into(),
        Some(v) if v <= 0.0 => "depleted".into(),
        Some(v) if v < 20.0 => "critical".into(),
        Some(v) if v < 40.0 => "warning".into(),
        Some(_) => "healthy".into(),
    }
}

pub fn session_weekly_from_meters(meters: &[QuotaMeter]) -> (Option<f64>, Option<f64>) {
    let mut session = None;
    let mut weekly = None;
    for m in meters {
        let label = m.label.to_lowercase();
        if session.is_none()
            && (label.contains("5") || label.contains("session") || label.contains("小时"))
        {
            session = m.remaining_percent;
        }
        if weekly.is_none()
            && (label.contains("7") || label.contains("week") || label.contains("周") || label.contains("天"))
        {
            weekly = m.remaining_percent;
        }
    }
    if session.is_none() {
        session = meters.first().and_then(|m| m.remaining_percent);
    }
    if weekly.is_none() {
        weekly = meters.get(1).and_then(|m| m.remaining_percent);
    }
    (session, weekly)
}
