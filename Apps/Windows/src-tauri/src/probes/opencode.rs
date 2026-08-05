//! OpenCode Go — `opencode db` SQL quotas (Mac OpenCodeUsageProbe).

use crate::models::QuotaMeter;
use serde_json::Value;
use std::process::Command;

const FIVE_H_LIMIT: f64 = 12.0;
const WEEKLY_LIMIT: f64 = 30.0;
const MONTHLY_LIMIT: f64 = 60.0;

pub fn available() -> bool {
    Command::new("opencode").arg("--help").output().is_ok()
}

fn run_sql(sql: &str) -> Result<Value, String> {
    let output = Command::new("opencode")
        .args(["db", sql, "--format", "json"])
        .output()
        .map_err(|_| "未找到 opencode CLI".to_string())?;
    if !output.status.success() {
        return Err(format!(
            "opencode db 失败: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    let text = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str(text.trim()).map_err(|e| e.to_string())
}

fn pct(used: f64, limit: f64) -> f64 {
    if limit <= 0.0 {
        return 100.0;
    }
    ((limit - used) / limit * 100.0).clamp(0.0, 100.0)
}

pub async fn probe_opencode() -> Result<Vec<QuotaMeter>, String> {
    tokio::task::spawn_blocking(|| {
        let now_ms = chrono::Utc::now().timestamp_millis();
        let five_h_ms = now_ms - 5 * 3600 * 1000;
        // Monday UTC week start rough
        let week_start_ms = {
            use chrono::Datelike;
            let now = chrono::Utc::now();
            let weekday = now.weekday().num_days_from_monday() as i64;
            let day_start = now.date_naive().and_hms_opt(0, 0, 0).unwrap().and_utc();
            (day_start.timestamp() - weekday * 86400) * 1000
        };

        let filtered = r#"
    SELECT
      CAST(COALESCE(json_extract(data, '$.time.created'), time_created) AS INTEGER) AS t,
      CAST(json_extract(data, '$.cost') AS REAL) AS cost
    FROM message
    WHERE json_valid(data)
      AND json_extract(data, '$.providerID') = 'opencode-go'
      AND json_extract(data, '$.role') = 'assistant'
      AND json_type(data, '$.cost') IN ('integer', 'real')
"#;
        let primary_sql = format!(
            "SELECT
          COALESCE(SUM(CASE WHEN t >= {five_h_ms} THEN cost ELSE 0 END), 0) AS five_hour_cost,
          COALESCE(SUM(CASE WHEN t >= {week_start_ms} THEN cost ELSE 0 END), 0) AS weekly_cost,
          MIN(CASE WHEN t >= {five_h_ms} THEN t ELSE NULL END) AS five_hour_oldest_ms,
          MIN(t) AS anchor_ms
        FROM ({filtered})"
        );

        let json = run_sql(&primary_sql)?;
        let row = json
            .as_array()
            .and_then(|a| a.first())
            .cloned()
            .or_else(|| if json.is_object() { Some(json.clone()) } else { None })
            .ok_or_else(|| "opencode 无数据行".to_string())?;

        let five = row
            .get("five_hour_cost")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        let weekly = row
            .get("weekly_cost")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);

        // Monthly approximate last 30d if anchor present
        let month_start = now_ms - 30 * 86400 * 1000;
        let monthly_sql = format!(
            "SELECT COALESCE(SUM(cost), 0) AS monthly_cost FROM ({filtered}) WHERE t >= {month_start}"
        );
        let monthly = run_sql(&monthly_sql)
            .ok()
            .and_then(|j| {
                j.as_array()
                    .and_then(|a| a.first())
                    .or(Some(&j))
                    .and_then(|r| r.get("monthly_cost"))
                    .and_then(|v| v.as_f64())
            })
            .unwrap_or(0.0);

        Ok(vec![
            QuotaMeter::session(
                Some(pct(five, FIVE_H_LIMIT)),
                Some(format!("${five:.2}/${FIVE_H_LIMIT:.0}")),
                None,
            ),
            QuotaMeter::weekly(
                Some(pct(weekly, WEEKLY_LIMIT)),
                Some(format!("${weekly:.2}/${WEEKLY_LIMIT:.0}")),
                None,
            ),
            QuotaMeter::time_limit(
                "Monthly",
                Some(pct(monthly, MONTHLY_LIMIT)),
                Some(format!("${monthly:.2}/${MONTHLY_LIMIT:.0}")),
                None,
            ),
        ])
    })
    .await
    .map_err(|e| e.to_string())?
}
