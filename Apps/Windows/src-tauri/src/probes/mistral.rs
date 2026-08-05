//! Mistral / Vibe — local session logs daily usage (Mac MistralUsageProbe).

use crate::models::QuotaMeter;
use crate::paths::home;
use serde_json::Value;
use std::fs;

pub fn available() -> bool {
    home().join(".vibe").join("logs").join("session").exists()
}

pub async fn probe_mistral() -> Result<Vec<QuotaMeter>, String> {
    tokio::task::spawn_blocking(|| {
        let dir = home().join(".vibe").join("logs").join("session");
        if !dir.exists() {
            return Err("未找到 ~/.vibe/logs/session（Vibe 会话日志）".into());
        }
        let today = chrono::Local::now().format("%Y-%m-%d").to_string();
        let mut total_tokens: f64 = 0.0;
        let mut total_cost: f64 = 0.0;
        let mut sessions = 0u32;

        let entries = fs::read_dir(&dir).map_err(|e| e.to_string())?;
        for entry in entries.flatten() {
            let meta = entry.path().join("metadata.json");
            if !meta.exists() {
                continue;
            }
            let Ok(text) = fs::read_to_string(&meta) else {
                continue;
            };
            let Ok(json) = serde_json::from_str::<Value>(&text) else {
                continue;
            };
            // Filter today if timestamp present
            let is_today = json
                .get("date")
                .or_else(|| json.get("day"))
                .and_then(|v| v.as_str())
                .map(|d| d.starts_with(&today))
                .unwrap_or(true);
            if !is_today {
                // also check createdAt
                if let Some(ts) = json
                    .get("createdAt")
                    .or_else(|| json.get("created_at"))
                    .and_then(|v| v.as_str())
                {
                    if !ts.starts_with(&today) {
                        continue;
                    }
                }
            }
            sessions += 1;
            total_tokens += json
                .get("totalTokens")
                .or_else(|| json.get("total_tokens"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0);
            total_cost += json
                .get("cost")
                .or_else(|| json.get("totalCost"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0);
        }

        if sessions == 0 {
            return Ok(vec![QuotaMeter::time_limit(
                "今日",
                Some(100.0),
                Some("今日暂无 Vibe 会话".into()),
                None,
            )]);
        }

        Ok(vec![
            QuotaMeter::time_limit(
                "今日 Tokens",
                None,
                Some(format!("{total_tokens:.0} tokens · {sessions} 会话")),
                None,
            ),
            QuotaMeter::time_limit(
                "今日费用",
                None,
                Some(format!("${total_cost:.4}")),
                None,
            ),
        ])
    })
    .await
    .map_err(|e| e.to_string())?
}
