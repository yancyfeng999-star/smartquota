//! Pure alert rules — port of Mac `QuotaAlertPolicy`.

use crate::models::{AlertEvent, QuotaCard, QuotaMeter};
use crate::settings::AppSettings;
use chrono::Utc;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AlertKind {
    SessionLow,
    WeeklyLow,
    WeeklyUnderuseNearReset,
}

impl AlertKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::SessionLow => "sessionLow",
            Self::WeeklyLow => "weeklyLow",
            Self::WeeklyUnderuseNearReset => "weeklyUnderuseNearReset",
        }
    }
}

pub struct Evaluation {
    pub kind: AlertKind,
    pub remaining: f64,
    pub resets_at_unix: Option<i64>,
}

/// Evaluate one card's meters against user thresholds.
pub fn evaluate_card(card: &QuotaCard, settings: &AppSettings, now_unix: i64) -> Vec<Evaluation> {
    if !settings.quota_threshold_alerts_enabled {
        return vec![];
    }
    if card.status == "disabled" || card.status == "setup" || card.status == "error" {
        return vec![];
    }

    let session = card
        .meters
        .iter()
        .find(|m| m.kind == "session" || m.key == "session")
        .and_then(|m| m.remaining_percent);
    let weekly_m = card
        .meters
        .iter()
        .find(|m| m.kind == "weekly" || m.key == "weekly");
    let weekly = weekly_m.and_then(|m| m.remaining_percent);
    let weekly_reset = weekly_m.and_then(|m| m.resets_at_unix);

    let mut out = Vec::new();

    if let Some(s) = session {
        if s <= settings.session_alert_threshold {
            out.push(Evaluation {
                kind: AlertKind::SessionLow,
                remaining: s,
                resets_at_unix: None,
            });
        }
    }

    if let Some(w) = weekly {
        if w <= settings.weekly_alert_threshold {
            out.push(Evaluation {
                kind: AlertKind::WeeklyLow,
                remaining: w,
                resets_at_unix: weekly_reset,
            });
        }
        if w >= settings.underuse_alert_remaining {
            if let Some(reset) = weekly_reset {
                let hours_left = (reset - now_unix) as f64 / 3600.0;
                if hours_left > 0.0 && hours_left <= settings.near_reset_alert_hours {
                    out.push(Evaluation {
                        kind: AlertKind::WeeklyUnderuseNearReset,
                        remaining: w,
                        resets_at_unix: Some(reset),
                    });
                }
            }
        }
    }

    out
}

const COOLDOWN_SECS: i64 = 6 * 3600; // 6h between same provider+kind

/// Filter by debounce and produce UI/system messages. Mutates settings.alert_last_fired.
pub fn collect_alerts(
    cards: &[QuotaCard],
    settings: &mut AppSettings,
) -> Vec<AlertEvent> {
    let now = Utc::now().timestamp();
    let mut events = Vec::new();

    for card in cards {
        for ev in evaluate_card(card, settings, now) {
            let key = format!("{}:{}", card.provider_id, ev.kind.as_str());
            let last = settings.alert_last_fired.get(&key).copied().unwrap_or(0);
            if now - last < COOLDOWN_SECS {
                continue;
            }
            settings.alert_last_fired.insert(key, now);

            let message = match ev.kind {
                AlertKind::SessionLow => format!(
                    "{} 5 小时额度剩余 {}%，低于阈值",
                    card.display_name,
                    ev.remaining.round() as i64
                ),
                AlertKind::WeeklyLow => format!(
                    "{} 7 天额度剩余 {}%，低于阈值",
                    card.display_name,
                    ev.remaining.round() as i64
                ),
                AlertKind::WeeklyUnderuseNearReset => format!(
                    "{} 即将重置但仍有 {}% 未用，记得用完额度",
                    card.display_name,
                    ev.remaining.round() as i64
                ),
            };

            events.push(AlertEvent {
                provider_id: card.provider_id.clone(),
                kind: ev.kind.as_str().into(),
                message,
            });
        }
    }

    events
}

/// Visual urgency for reset timestamp (Mac resetUrgency).
pub fn reset_urgency(resets_at_unix: Option<i64>, near_reset_hours: f64) -> &'static str {
    let Some(reset) = resets_at_unix else {
        return "normal";
    };
    let now = Utc::now().timestamp();
    let hours = (reset - now) as f64 / 3600.0;
    if hours <= 0.0 || hours <= 6.0 {
        "imminent"
    } else if hours <= near_reset_hours {
        "soon"
    } else {
        "normal"
    }
}

#[allow(dead_code)]
pub fn meter_urgency(m: &QuotaMeter, near_reset_hours: f64) -> &'static str {
    reset_urgency(m.resets_at_unix, near_reset_hours)
}

/// Best-effort Windows toast via PowerShell (no extra crate).
pub fn show_system_notification(title: &str, body: &str) {
    #[cfg(target_os = "windows")]
    {
        let title = title.replace('\'', "''");
        let body = body.replace('\'', "''");
        let script = format!(
            "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null; \
             $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02); \
             $text = $template.GetElementsByTagName('text'); \
             $text.Item(0).AppendChild($template.CreateTextNode('{title}')) | Out-Null; \
             $text.Item(1).AppendChild($template.CreateTextNode('{body}')) | Out-Null; \
             $toast = [Windows.UI.Notifications.ToastNotification]::new($template); \
             [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('智额').Show($toast);"
        );
        let _ = std::process::Command::new("powershell")
            .args(["-NoProfile", "-Command", &script])
            .spawn();
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (title, body);
        // On macOS dev host: no-op (Windows product path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::QuotaMeter;

    fn card_with(session: f64, weekly: f64, weekly_reset: Option<i64>) -> QuotaCard {
        QuotaCard {
            provider_id: "codex".into(),
            display_name: "Codex".into(),
            status: "healthy".into(),
            session_remaining_percent: Some(session),
            weekly_remaining_percent: Some(weekly),
            meters: vec![
                QuotaMeter::session(Some(session), None, None),
                QuotaMeter::weekly(Some(weekly), None, weekly_reset),
            ],
            plan_label: String::new(),
            detail: String::new(),
            enabled: true,
            source_mode: "auto".into(),
            is_core: true,
            account_id: None,
            account_email: None,
            account_label: None,
            account_state: None,
        }
    }

    #[test]
    fn session_low_fires() {
        let settings = AppSettings::default();
        let c = card_with(15.0, 80.0, None);
        let ev = evaluate_card(&c, &settings, Utc::now().timestamp());
        assert!(ev.iter().any(|e| e.kind == AlertKind::SessionLow));
    }

    #[test]
    fn underuse_near_reset_fires() {
        let settings = AppSettings::default();
        let now = Utc::now().timestamp();
        let c = card_with(80.0, 70.0, Some(now + 12 * 3600));
        let ev = evaluate_card(&c, &settings, now);
        assert!(ev
            .iter()
            .any(|e| e.kind == AlertKind::WeeklyUnderuseNearReset));
    }
}
