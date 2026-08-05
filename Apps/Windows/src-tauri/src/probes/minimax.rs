use crate::models::QuotaMeter;
use crate::paths::minimax_config_path;
use crate::secrets::{self, MINIMAX_API_KEY};
use crate::settings::AppSettings;
use regex::Regex;
use serde_json::Value;
use std::fs;

fn region_urls(region: &str) -> Vec<String> {
    let base = if region == "international" {
        "https://api.minimax.io"
    } else {
        "https://api.minimaxi.com"
    };
    vec![
        format!("{base}/v1/token_plan/remains"),
        format!("{base}/v1/api/openplatform/coding_plan/remains"),
    ]
}

fn resolve_api_key(settings: &AppSettings) -> Option<String> {
    let env_name = if settings.minimax_auth_env_var.is_empty() {
        "MINIMAX_API_KEY".to_string()
    } else {
        settings.minimax_auth_env_var.clone()
    };
    if let Ok(v) = std::env::var(&env_name) {
        if !v.is_empty() {
            return Some(v);
        }
    }
    if let Some(k) = secrets::get_secret(MINIMAX_API_KEY) {
        return Some(k);
    }
    load_local_coding_plan_key()
}

fn load_local_coding_plan_key() -> Option<String> {
    let path = minimax_config_path();
    let text = fs::read_to_string(path).ok()?;
    let re = Regex::new(r#"(?i)(?:apiKey|api_key)\s*:\s*["']?(sk-cp-[A-Za-z0-9_\-]+)["']?"#).ok()?;
    // Prefer section with minimaxtokenplan
    let mut preferred = None;
    let mut any = None;
    let mut in_pref = false;
    for line in text.lines() {
        if line.contains("minimaxtokenplan") {
            in_pref = true;
        }
        if let Some(c) = re.captures(line) {
            let key = c.get(1)?.as_str().to_string();
            if key.len() > 20 {
                if any.is_none() {
                    any = Some(key.clone());
                }
                if in_pref {
                    preferred = Some(key);
                    break;
                }
            }
        }
    }
    preferred.or(any)
}

fn soft_error(json: &Value) -> Option<String> {
    let base = json.get("base_resp")?;
    let code = base.get("status_code")?.as_i64()?;
    if code != 0 {
        let msg = base
            .get("status_msg")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");
        return Some(format!("MiniMax API: {msg} (code {code})"));
    }
    None
}

fn as_f64(v: Option<&Value>) -> Option<f64> {
    v.and_then(|x| x.as_f64().or_else(|| x.as_i64().map(|i| i as f64)))
}

fn parse_meters(json: &Value) -> Result<Vec<QuotaMeter>, String> {
    if let Some(err) = soft_error(json) {
        return Err(err);
    }
    let remains = json
        .get("model_remains")
        .or_else(|| json.get("modelRemains"))
        .and_then(|v| v.as_array())
        .ok_or_else(|| "响应无 model_remains".to_string())?;
    if remains.is_empty() {
        return Err("model_remains 为空".into());
    }
    let primary = remains
        .iter()
        .find(|m| {
            m.get("model_name")
                .or_else(|| m.get("modelName"))
                .and_then(|v| v.as_str())
                .map(|s| s.eq_ignore_ascii_case("general"))
                .unwrap_or(false)
        })
        .unwrap_or(&remains[0]);

    let mut meters = Vec::new();

    // 5h interval remaining
    if let Some(pct) = as_f64(
        primary
            .get("current_interval_remaining_percent")
            .or_else(|| primary.get("currentIntervalRemainingPercent")),
    ) {
        let end = primary.get("end_time").or_else(|| primary.get("endTime"));
        meters.push(QuotaMeter::session(
            Some(pct.clamp(0.0, 100.0)),
            epoch_ms_reset(end),
            epoch_ms_unix(end),
        ));
    }

    // weekly remaining
    if let Some(pct) = as_f64(
        primary
            .get("current_weekly_remaining_percent")
            .or_else(|| primary.get("currentWeeklyRemainingPercent")),
    ) {
        let end = primary
            .get("weekly_end_time")
            .or_else(|| primary.get("weeklyEndTime"));
        meters.push(QuotaMeter::weekly(
            Some(pct.clamp(0.0, 100.0)),
            epoch_ms_reset(end),
            epoch_ms_unix(end),
        ));
    }

    // Fallback older count-style
    if meters.is_empty() {
        if let (Some(total), Some(usage)) = (
            as_f64(primary.get("total_count").or_else(|| primary.get("totalCount"))),
            as_f64(primary.get("usage_count").or_else(|| primary.get("usageCount"))),
        ) {
            if total > 0.0 {
                let rem = ((total - usage) / total * 100.0).clamp(0.0, 100.0);
                meters.push(QuotaMeter::time_limit("额度", Some(rem), None, None));
            }
        }
    }

    if meters.is_empty() {
        return Err("无法解析 MiniMax 额度字段".into());
    }
    Ok(meters)
}

fn epoch_ms_unix(v: Option<&Value>) -> Option<i64> {
    let ms = as_f64(v)?;
    if ms <= 0.0 {
        return None;
    }
    Some((ms / 1000.0) as i64)
}

fn epoch_ms_reset(v: Option<&Value>) -> Option<String> {
    let secs = epoch_ms_unix(v)?;
    let dt = chrono::DateTime::from_timestamp(secs, 0)?;
    Some(format!("重置 {}", dt.format("%m-%d %H:%M")))
}

pub async fn probe_minimax(settings: &AppSettings) -> Result<Vec<QuotaMeter>, String> {
    let key = resolve_api_key(settings).ok_or_else(|| {
        "未配置 MiniMax API Key：请在设置中填写，或设置环境变量 MINIMAX_API_KEY，或配置 %USERPROFILE%\\.minimax\\config.yaml".to_string()
    })?;

    let client = reqwest::Client::new();
    let mut last_err = "MiniMax: 无可用端点".to_string();
    for url in region_urls(&settings.minimax_region) {
        match client
            .get(&url)
            .bearer_auth(&key)
            .header("Accept", "application/json")
            .timeout(std::time::Duration::from_secs(25))
            .send()
            .await
        {
            Ok(resp) => {
                let status = resp.status();
                if status.as_u16() == 401 || status.as_u16() == 403 {
                    return Err("MiniMax 鉴权失败，请检查 API Key".into());
                }
                if !status.is_success() {
                    last_err = format!("MiniMax HTTP {status} @ {url}");
                    continue;
                }
                match resp.json::<Value>().await {
                    Ok(json) => match parse_meters(&json) {
                        Ok(m) => return Ok(m),
                        Err(e) => last_err = e,
                    },
                    Err(e) => last_err = e.to_string(),
                }
            }
            Err(e) => last_err = format!("网络错误 {url}: {e}"),
        }
    }
    Err(last_err)
}
