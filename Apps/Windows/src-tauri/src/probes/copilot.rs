//! GitHub Copilot — Internal API with user PAT (Mac CopilotInternalAPIProbe).

use crate::models::QuotaMeter;
use crate::secrets::{self, GITHUB_TOKEN};
use serde_json::Value;

const USER_URL: &str = "https://api.github.com/copilot_internal/user";

pub fn resolve_token() -> Option<String> {
    if let Ok(v) = std::env::var("GITHUB_TOKEN") {
        if !v.is_empty() {
            return Some(v);
        }
    }
    if let Ok(v) = std::env::var("GH_TOKEN") {
        if !v.is_empty() {
            return Some(v);
        }
    }
    if let Ok(v) = std::env::var("COPILOT_GITHUB_TOKEN") {
        if !v.is_empty() {
            return Some(v);
        }
    }
    secrets::get_secret(GITHUB_TOKEN)
}

fn as_f64(v: Option<&Value>) -> Option<f64> {
    v.and_then(|x| x.as_f64().or_else(|| x.as_i64().map(|i| i as f64)).or_else(|| {
        x.as_str().and_then(|s| s.parse().ok())
    }))
}

fn parse_user(json: &Value) -> Result<Vec<QuotaMeter>, String> {
    let mut meters = Vec::new();

    let snaps = json
        .get("quota_snapshots")
        .or_else(|| json.get("quotaSnapshots"));

    let premium = snaps
        .and_then(|s| s.get("premium_interactions").or_else(|| s.get("premiumInteractions")));

    if let Some(premium) = premium {
        if premium.get("unlimited").and_then(|v| v.as_bool()) == Some(true) {
            meters.push(QuotaMeter::time_limit(
                "Premium",
                Some(100.0),
                Some("无限".into()),
                None,
            ));
        } else {
            let remaining = as_f64(premium.get("remaining"));
            let percent_remaining = as_f64(premium.get("percent_remaining"))
                .or_else(|| as_f64(premium.get("percentRemaining")))
                .or_else(|| {
                    let ent = as_f64(premium.get("entitlement"))?;
                    let rem = remaining?;
                    if ent > 0.0 {
                        Some(rem / ent * 100.0)
                    } else {
                        None
                    }
                });
            if let Some(pct) = percent_remaining {
                meters.push(QuotaMeter::time_limit(
                    "Premium",
                    Some(pct.clamp(0.0, 100.0)),
                    remaining.map(|r| format!("剩余 {r}")),
                    None,
                ));
            } else if let Some(rem) = remaining {
                meters.push(QuotaMeter::time_limit(
                    "Premium",
                    None,
                    Some(format!("剩余 {rem}")),
                    None,
                ));
            }
        }
    }

    // chat / completions snapshots as extra meters
    for key in ["chat", "completions"] {
        if let Some(obj) = snaps.and_then(|s| s.get(key)) {
            if let Some(pct) = as_f64(obj.get("percent_remaining"))
                .or_else(|| as_f64(obj.get("percentRemaining")))
            {
                meters.push(QuotaMeter::time_limit(
                    key,
                    Some(pct.clamp(0.0, 100.0)),
                    None,
                    None,
                ));
            }
        }
    }

    if meters.is_empty() {
        let plan = json
            .get("copilot_plan")
            .or_else(|| json.get("copilotPlan"))
            .and_then(|v| v.as_str())
            .unwrap_or("copilot");
        meters.push(QuotaMeter::time_limit(
            "Monthly",
            Some(100.0),
            Some(format!("plan={plan}（无 premium 额度字段）")),
            None,
        ));
    }

    Ok(meters)
}

pub async fn probe_copilot() -> Result<Vec<QuotaMeter>, String> {
    let token = resolve_token().ok_or_else(|| {
        "未配置 GitHub Token：在设置中填写 Classic PAT（需 copilot 权限），或设置 GITHUB_TOKEN"
            .to_string()
    })?;

    let client = reqwest::Client::new();
    let resp = client
        .get(USER_URL)
        .bearer_auth(&token)
        .header("Accept", "application/json")
        .header("User-Agent", "SmartQuota")
        .timeout(std::time::Duration::from_secs(25))
        .send()
        .await
        .map_err(|e| format!("Copilot 网络错误: {e}"))?;

    let status = resp.status();
    if status.as_u16() == 401 {
        return Err("GitHub Token 无效或过期".into());
    }
    if status.as_u16() == 403 {
        return Err("Forbidden：请确认 Classic PAT 含 copilot 相关权限".into());
    }
    if status.as_u16() == 404 {
        return Err("未找到 Copilot 订阅".into());
    }
    if !status.is_success() {
        return Err(format!("Copilot HTTP {status}"));
    }
    let json: Value = resp.json().await.map_err(|e| e.to_string())?;
    parse_user(&json)
}
