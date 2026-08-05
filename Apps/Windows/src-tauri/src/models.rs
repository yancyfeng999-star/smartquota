use serde::{Deserialize, Serialize};

/// One quota window — aligns with Mac `UsageQuota` serializable subset.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaMeter {
    /// Stable key: session | weekly | model:x | time:x
    #[serde(default)]
    pub key: String,
    /// session | weekly | model | time | unknown
    #[serde(default = "default_kind")]
    pub kind: String,
    pub label: String,
    /// Remaining percent 0–100 (or null if unknown)
    pub remaining_percent: Option<f64>,
    pub reset_text: Option<String>,
    /// Unix seconds when this window resets (for alerts / urgency)
    #[serde(default)]
    pub resets_at_unix: Option<i64>,
}

fn default_kind() -> String {
    "unknown".into()
}

impl QuotaMeter {
    pub fn new(
        key: impl Into<String>,
        kind: impl Into<String>,
        label: impl Into<String>,
        remaining_percent: Option<f64>,
        reset_text: Option<String>,
        resets_at_unix: Option<i64>,
    ) -> Self {
        Self {
            key: key.into(),
            kind: kind.into(),
            label: label.into(),
            remaining_percent,
            reset_text,
            resets_at_unix,
        }
    }

    pub fn session(
        remaining: Option<f64>,
        reset_text: Option<String>,
        resets_at_unix: Option<i64>,
    ) -> Self {
        Self::new(
            "session",
            "session",
            "5 小时",
            remaining,
            reset_text,
            resets_at_unix,
        )
    }

    pub fn weekly(
        remaining: Option<f64>,
        reset_text: Option<String>,
        resets_at_unix: Option<i64>,
    ) -> Self {
        Self::new(
            "weekly",
            "weekly",
            "7 天",
            remaining,
            reset_text,
            resets_at_unix,
        )
    }

    pub fn time_limit(
        name: &str,
        remaining: Option<f64>,
        reset_text: Option<String>,
        resets_at_unix: Option<i64>,
    ) -> Self {
        Self::new(
            format!("time:{name}"),
            "time",
            name.to_string(),
            remaining,
            reset_text,
            resets_at_unix,
        )
    }

    pub fn model(
        name: &str,
        remaining: Option<f64>,
        reset_text: Option<String>,
        resets_at_unix: Option<i64>,
    ) -> Self {
        Self::new(
            format!("model:{name}"),
            "model",
            name.to_string(),
            remaining,
            reset_text,
            resets_at_unix,
        )
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaCard {
    pub provider_id: String,
    pub display_name: String,
    /// healthy | warning | critical | depleted | unknown | error | disabled | setup
    pub status: String,
    pub session_remaining_percent: Option<f64>,
    pub weekly_remaining_percent: Option<f64>,
    pub meters: Vec<QuotaMeter>,
    /// User-filled display only (never auto-filled from our data)
    pub plan_label: String,
    pub detail: String,
    pub enabled: bool,
    /// auto | manual | none — how credentials were resolved
    pub source_mode: String,
    /// Whether this is a core (default-on) provider
    #[serde(default)]
    pub is_core: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotPayload {
    pub updated_at: String,
    pub cards: Vec<QuotaCard>,
    /// Alerts fired this refresh (for UI toast echo)
    #[serde(default)]
    pub alerts: Vec<AlertEvent>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AlertEvent {
    pub provider_id: String,
    pub kind: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProbeTestResult {
    pub ok: bool,
    pub message: String,
}

/// Mac `QuotaStatus.from`: depleted≤0, critical<20, warning<50, else healthy.
pub fn status_from_remaining(session: Option<f64>, weekly: Option<f64>) -> String {
    status_from_percent(session.into_iter().chain(weekly).fold(None, |acc, v| {
        Some(acc.map(|a: f64| a.min(v)).unwrap_or(v))
    }))
}

pub fn status_from_percent(worst: Option<f64>) -> String {
    match worst {
        None => "unknown".into(),
        Some(v) if v <= 0.0 => "depleted".into(),
        Some(v) if v < 20.0 => "critical".into(),
        Some(v) if v < 50.0 => "warning".into(),
        Some(_) => "healthy".into(),
    }
}

pub fn status_from_meters(meters: &[QuotaMeter]) -> String {
    let worst = meters
        .iter()
        .filter_map(|m| m.remaining_percent)
        .fold(None, |acc: Option<f64>, v| {
            Some(acc.map(|a| a.min(v)).unwrap_or(v))
        });
    status_from_percent(worst)
}

pub fn session_weekly_from_meters(meters: &[QuotaMeter]) -> (Option<f64>, Option<f64>) {
    let mut session = None;
    let mut weekly = None;
    for m in meters {
        if session.is_none() && (m.kind == "session" || m.key == "session") {
            session = m.remaining_percent;
        }
        if weekly.is_none() && (m.kind == "weekly" || m.key == "weekly") {
            weekly = m.remaining_percent;
        }
    }
    // Fallback: label heuristics for legacy meters
    if session.is_none() || weekly.is_none() {
        for m in meters {
            let label = m.label.to_lowercase();
            if session.is_none()
                && (label.contains("5") || label.contains("session") || label.contains("小时"))
            {
                session = m.remaining_percent;
            }
            if weekly.is_none()
                && (label.contains("7")
                    || label.contains("week")
                    || label.contains("周")
                    || label.contains("天"))
            {
                weekly = m.remaining_percent;
            }
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

/// Parse ISO-8601 / RFC3339 to unix seconds.
pub fn parse_iso_unix(s: Option<&str>) -> Option<i64> {
    let s = s?.trim();
    if s.is_empty() {
        return None;
    }
    chrono::DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|d| d.timestamp())
        .or_else(|| {
            // date-only
            chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d")
                .ok()
                .and_then(|d| d.and_hms_opt(0, 0, 0))
                .map(|dt| dt.and_utc().timestamp())
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_thresholds_match_mac() {
        assert_eq!(status_from_percent(Some(0.0)), "depleted");
        assert_eq!(status_from_percent(Some(10.0)), "critical");
        assert_eq!(status_from_percent(Some(30.0)), "warning");
        assert_eq!(status_from_percent(Some(45.0)), "warning"); // was healthy on old Win 40%
        assert_eq!(status_from_percent(Some(50.0)), "healthy");
        assert_eq!(status_from_percent(Some(80.0)), "healthy");
    }
}
