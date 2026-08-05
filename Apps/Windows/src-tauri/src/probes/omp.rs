//! Oh My Pi — `omp usage --json` (Mac OmpUsageProbe).

use crate::models::QuotaMeter;
use serde_json::Value;
use std::process::Command;

pub fn available() -> bool {
    Command::new("omp").arg("--help").output().is_ok()
}

pub async fn probe_omp() -> Result<Vec<QuotaMeter>, String> {
    tokio::task::spawn_blocking(|| {
        let output = Command::new("omp")
            .args(["usage", "--json"])
            .output()
            .map_err(|_| "未找到 omp CLI（Oh My Pi）".to_string())?;
        if !output.status.success() {
            return Err(format!(
                "omp usage 失败: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }
        let text = String::from_utf8_lossy(&output.stdout);
        parse_omp_json(&text)
    })
    .await
    .map_err(|e| e.to_string())?
}

pub fn parse_omp_json(text: &str) -> Result<Vec<QuotaMeter>, String> {
    let json: Value = serde_json::from_str(text.trim()).map_err(|e| e.to_string())?;
    let reports = json
        .get("reports")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "omp JSON 无 reports".to_string())?;

    let mut meters = Vec::new();
    for report in reports {
        let provider = report
            .get("provider")
            .and_then(|v| v.as_str())
            .unwrap_or("account");
        let limits = report
            .get("limits")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();
        for limit in limits {
            let label = limit
                .get("label")
                .and_then(|v| v.as_str())
                .unwrap_or("limit");
            let remaining = limit
                .pointer("/amount/remainingFraction")
                .and_then(|v| v.as_f64())
                .map(|f| (f * 100.0).clamp(0.0, 100.0))
                .or_else(|| {
                    let used = limit.pointer("/amount/usedFraction")?.as_f64()?;
                    Some(((1.0 - used) * 100.0).clamp(0.0, 100.0))
                });
            let resets_at = limit
                .pointer("/window/resetsAt")
                .and_then(|v| v.as_i64())
                .map(|ms| if ms > 1_000_000_000_000 { ms / 1000 } else { ms });
            let window_id = limit
                .pointer("/window/id")
                .or_else(|| limit.pointer("/scope/windowId"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let name = format!("{provider} {label}");
            let meter = if window_id.contains("5h") || label.contains("5") {
                QuotaMeter::session(
                    remaining,
                    Some(name.clone()),
                    resets_at,
                )
            } else if window_id.contains("7d") || label.to_lowercase().contains("week") {
                QuotaMeter::weekly(remaining, Some(name.clone()), resets_at)
            } else {
                QuotaMeter::time_limit(&name, remaining, None, resets_at)
            };
            // Avoid duplicate pure session/weekly keys clobbering — use model for extras
            if meters
                .iter()
                .any(|m: &QuotaMeter| m.key == meter.key && meter.kind != "time")
            {
                meters.push(QuotaMeter::model(&name, remaining, None, resets_at));
            } else {
                meters.push(meter);
            }
        }
    }
    if meters.is_empty() {
        return Err("omp 无额度 limits".into());
    }
    Ok(meters)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_sample() {
        let t = r#"{"reports":[{"provider":"anthropic","limits":[{"label":"Claude 5 Hour","scope":{"windowId":"5h"},"window":{"id":"5h","resetsAt":1783885200000},"amount":{"usedFraction":0.08,"remainingFraction":0.92}}]}]}"#;
        let m = parse_omp_json(t).unwrap();
        assert!(!m.is_empty());
        assert!((m[0].remaining_percent.unwrap() - 92.0).abs() < 0.1);
    }
}
