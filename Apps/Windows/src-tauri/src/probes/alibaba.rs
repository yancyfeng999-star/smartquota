//! 通义 / Alibaba Coding Plan — Mac API-key path.

use crate::models::{parse_iso_unix, QuotaMeter};
use crate::secrets::{self, provider_key_account};
use crate::settings::AppSettings;
use serde_json::Value;

pub fn resolve_key() -> Option<String> {
    for env in ["ALIBABA_API_KEY", "DASHSCOPE_API_KEY", "ALIYUN_API_KEY"] {
        if let Ok(v) = std::env::var(env) {
            if !v.is_empty() {
                return Some(v);
            }
        }
    }
    secrets::get_secret(&provider_key_account("alibaba"))
}

pub fn has_key() -> bool {
    resolve_key().is_some()
}

fn region_gateway(settings: &AppSettings) -> (&'static str, &'static str, &'static str) {
    // (gateway, regionId, commodityCode)
    let r = settings
        .providers
        .get("alibaba")
        .map(|p| p.plan_label.to_lowercase())
        .unwrap_or_default();
    if r.contains("intl") || r.contains("sg") || settings.minimax_region == "international" {
        // reuse minimax_region loosely only if user set international globally — prefer china
        (
            "https://bailian-singapore-cs.alibabacloud.com",
            "ap-southeast-1",
            "sfm_codingplan_public_cn",
        )
    } else {
        (
            "https://bailian-beijing-cs.aliyuncs.com",
            "cn-beijing",
            "sfm_codingplan_public_cn",
        )
    }
}

fn walk_quota_dict(v: &Value) -> Option<&Value> {
    // Find object containing per5Hour / perWeek keys
    match v {
        Value::Object(map) => {
            if map.contains_key("per5HourUsedQuota")
                || map.contains_key("perFiveHourUsedQuota")
                || map.contains_key("perWeekUsedQuota")
            {
                return Some(v);
            }
            for val in map.values() {
                if let Some(f) = walk_quota_dict(val) {
                    return Some(f);
                }
            }
            None
        }
        Value::Array(arr) => {
            for item in arr {
                if let Some(f) = walk_quota_dict(item) {
                    return Some(f);
                }
            }
            None
        }
        _ => None,
    }
}

fn any_i64(obj: &Value, keys: &[&str]) -> Option<i64> {
    for k in keys {
        if let Some(v) = obj.get(*k) {
            if let Some(i) = v.as_i64() {
                return Some(i);
            }
            if let Some(f) = v.as_f64() {
                return Some(f as i64);
            }
            if let Some(s) = v.as_str() {
                if let Ok(i) = s.parse() {
                    return Some(i);
                }
            }
        }
    }
    None
}

fn any_str(obj: &Value, keys: &[&str]) -> Option<String> {
    for k in keys {
        if let Some(s) = obj.get(*k).and_then(|v| v.as_str()) {
            return Some(s.to_string());
        }
    }
    None
}

fn rem_pct(used: i64, total: i64) -> f64 {
    if total <= 0 {
        return 100.0;
    }
    ((total - used) as f64 / total as f64 * 100.0).clamp(0.0, 100.0)
}

fn parse_response(json: &Value) -> Result<Vec<QuotaMeter>, String> {
    let q = walk_quota_dict(json).ok_or_else(|| "响应无 coding plan 额度字段".to_string())?;
    let mut meters = Vec::new();

    if let (Some(used), Some(total)) = (
        any_i64(q, &["per5HourUsedQuota", "perFiveHourUsedQuota"]),
        any_i64(q, &["per5HourTotalQuota", "perFiveHourTotalQuota"]),
    ) {
        let reset = any_str(
            q,
            &["per5HourQuotaNextRefreshTime", "perFiveHourQuotaNextRefreshTime"],
        );
        meters.push(QuotaMeter::session(
            Some(rem_pct(used, total)),
            reset.clone(),
            parse_iso_unix(reset.as_deref()),
        ));
    }
    if let (Some(used), Some(total)) = (
        any_i64(q, &["perWeekUsedQuota"]),
        any_i64(q, &["perWeekTotalQuota"]),
    ) {
        let reset = any_str(q, &["perWeekQuotaNextRefreshTime"]);
        meters.push(QuotaMeter::weekly(
            Some(rem_pct(used, total)),
            reset.clone(),
            parse_iso_unix(reset.as_deref()),
        ));
    }
    if let (Some(used), Some(total)) = (
        any_i64(q, &["perBillMonthUsedQuota", "perMonthUsedQuota"]),
        any_i64(q, &["perBillMonthTotalQuota", "perMonthTotalQuota"]),
    ) {
        let reset = any_str(
            q,
            &["perBillMonthQuotaNextRefreshTime", "perMonthQuotaNextRefreshTime"],
        );
        meters.push(QuotaMeter::time_limit(
            "月额度",
            Some(rem_pct(used, total)),
            reset.clone(),
            parse_iso_unix(reset.as_deref()),
        ));
    }

    if meters.is_empty() {
        return Err("无法解析通义 coding plan 额度".into());
    }
    Ok(meters)
}

pub async fn probe_alibaba(settings: &AppSettings) -> Result<Vec<QuotaMeter>, String> {
    let key = resolve_key().ok_or_else(|| {
        "未配置通义 API Key：设置 alibaba Key 或 DASHSCOPE_API_KEY / ALIBABA_API_KEY".to_string()
    })?;
    let (gateway, region_id, commodity) = region_gateway(settings);
    let url = format!(
        "{gateway}/data/api.json?action=zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2&product=broadscope-bailian&api=queryCodingPlanInstanceInfoV2&currentRegionId={region_id}"
    );
    let body = serde_json::json!({
        "queryCodingPlanInstanceInfoRequest": {
            "commodityCode": commodity
        }
    });
    let client = reqwest::Client::new();
    let resp = client
        .post(&url)
        .bearer_auth(&key)
        .header("X-DashScope-API-Key", &key)
        .header("Content-Type", "application/json")
        .header("Accept", "application/json")
        .json(&body)
        .timeout(std::time::Duration::from_secs(20))
        .send()
        .await
        .map_err(|e| format!("通义网络错误: {e}"))?;
    let status = resp.status();
    if status.as_u16() == 401 || status.as_u16() == 403 {
        return Err("通义鉴权失败".into());
    }
    if !status.is_success() {
        return Err(format!("通义 HTTP {status}"));
    }
    let json: Value = resp.json().await.map_err(|e| e.to_string())?;
    parse_response(&json)
}
