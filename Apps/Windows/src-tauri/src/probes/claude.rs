//! Claude probe — Mac `ClaudeUsageProbe` parity (CLI `/usage` parse).

use crate::models::QuotaMeter;
use crate::paths::{claude_dir, claude_json_path};
use regex::Regex;
use std::process::Command;

pub fn has_local_login() -> bool {
    claude_json_path().exists() || claude_dir().exists()
}

pub async fn probe_claude() -> Result<Vec<QuotaMeter>, String> {
    tokio::task::spawn_blocking(probe_claude_sync)
        .await
        .map_err(|e| e.to_string())?
}

fn probe_claude_sync() -> Result<Vec<QuotaMeter>, String> {
    let mut cmd = Command::new("claude");
    cmd.args(["/usage", "--allowed-tools", ""]);
    // Strip inference-only token so CLI uses full login credentials (Mac parity)
    cmd.env_remove("CLAUDE_CODE_OAUTH_TOKEN");
    let output = cmd.output().map_err(|_| {
        "未找到 claude CLI。请安装 Claude Code 并执行 claude login。".to_string()
    })?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let text = strip_ansi(&format!("{stdout}\n{stderr}"));

    if text.to_lowercase().contains("only available for subscription") {
        // Fallback: /cost for API billing accounts
        return probe_cost_sync();
    }

    parse_claude_usage_text(&text)
}

fn probe_cost_sync() -> Result<Vec<QuotaMeter>, String> {
    let mut cmd = Command::new("claude");
    cmd.args(["/cost", "--allowed-tools", ""]);
    cmd.env_remove("CLAUDE_CODE_OAUTH_TOKEN");
    let output = cmd
        .output()
        .map_err(|e| format!("claude /cost 失败: {e}"))?;
    let text = strip_ansi(&format!(
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    ));
    // Cost line: "$X.XX spent" as time meter without %
    if let Some(cap) = Regex::new(r"\$?([\d,]+\.?\d*)\s*/\s*\$?([\d,]+\.?\d*)")
        .ok()
        .and_then(|re| re.captures(&text))
    {
        let spent: f64 = cap[1].replace(',', "").parse().unwrap_or(0.0);
        let budget: f64 = cap[2].replace(',', "").parse().unwrap_or(0.0);
        if budget > 0.0 {
            let rem = ((budget - spent) / budget * 100.0).clamp(0.0, 100.0);
            return Ok(vec![QuotaMeter::time_limit(
                "API Cost",
                Some(rem),
                Some(format!("${spent:.2} / ${budget:.2}")),
                None,
            )]);
        }
    }
    Err("API 账单账号无 /usage 额度；/cost 亦无法解析".into())
}

fn strip_ansi(s: &str) -> String {
    Regex::new(r"\x1b\[[0-9;]*[a-zA-Z]")
        .map(|re| re.replace_all(s, "").to_string())
        .unwrap_or_else(|_| s.to_string())
}

/// Mac-style: "Current session" / "Current week" / model bars with "% used|left".
pub fn parse_claude_usage_text(text: &str) -> Result<Vec<QuotaMeter>, String> {
    let clean = strip_ansi(text);
    let mut meters = Vec::new();

    if let Some(pct) = extract_percent("Current session", &clean)
        .or_else(|| extract_percent("session", &clean))
    {
        let reset = extract_reset("Current session", &clean);
        meters.push(QuotaMeter::session(Some(pct), reset, None));
    }
    if let Some(pct) = extract_percent("Current week", &clean)
        .or_else(|| extract_percent("Weekly", &clean))
        .or_else(|| extract_percent("week", &clean))
    {
        let reset = extract_reset("Current week", &clean)
            .or_else(|| extract_reset("Weekly", &clean));
        meters.push(QuotaMeter::weekly(Some(pct), reset, None));
    }
    for model in ["Opus", "Sonnet", "Haiku", "Fable"] {
        if let Some(pct) = extract_percent(model, &clean) {
            meters.push(QuotaMeter::model(
                model,
                Some(pct),
                extract_reset(model, &clean),
                None,
            ));
        }
    }

    // Extra usage cost as meter if present
    if clean.to_lowercase().contains("extra usage") {
        if let Ok(re) = Regex::new(r"\$?([\d,]+\.?\d*)\s*/\s*\$?([\d,]+\.?\d*)\s*spent") {
            if let Some(cap) = re.captures(&clean) {
                let spent: f64 = cap[1].replace(',', "").parse().unwrap_or(0.0);
                let budget: f64 = cap[2].replace(',', "").parse().unwrap_or(0.0);
                if budget > 0.0 {
                    let rem = ((budget - spent) / budget * 100.0).clamp(0.0, 100.0);
                    meters.push(QuotaMeter::time_limit(
                        "Extra usage",
                        Some(rem),
                        Some(format!("${spent:.2} / ${budget:.2}")),
                        None,
                    ));
                }
            }
        }
    }

    if meters.is_empty() {
        // Fallback generic % left/used pairs
        if let Ok(re) = Regex::new(r"(?i)(\d{1,3})\s*%\s*(used|left|remaining)") {
            let mut vals = Vec::new();
            for cap in re.captures_iter(&clean) {
                let raw: f64 = cap[1].parse().unwrap_or(0.0);
                let kind = cap[2].to_lowercase();
                let rem = if kind.contains("used") {
                    (100.0 - raw).max(0.0)
                } else {
                    raw
                };
                vals.push(rem.clamp(0.0, 100.0));
            }
            if let Some(&s) = vals.first() {
                meters.push(QuotaMeter::session(Some(s), None, None));
            }
            if let Some(&w) = vals.get(1) {
                meters.push(QuotaMeter::weekly(Some(w), None, None));
            }
        }
    }

    if meters.is_empty() {
        if has_local_login() {
            return Err(
                "已检测到 Claude 配置，但无法解析 /usage。请在终端运行 claude /usage 核对输出。"
                    .into(),
            );
        }
        return Err("未检测到 Claude 登录。请安装 Claude Code 并登录。".into());
    }
    Ok(meters)
}

fn extract_percent(label: &str, text: &str) -> Option<f64> {
    let lines: Vec<&str> = text.lines().collect();
    let label_l = label.to_lowercase();
    for (idx, line) in lines.iter().enumerate() {
        if !line.to_lowercase().contains(&label_l) {
            continue;
        }
        for candidate in lines.iter().skip(idx).take(12) {
            if let Some(p) = percent_from_line(candidate) {
                return Some(p);
            }
        }
    }
    None
}

fn percent_from_line(line: &str) -> Option<f64> {
    let re = Regex::new(r"(?i)([0-9]{1,3})\s*%\s*(used|left|remaining)").ok()?;
    let cap = re.captures(line)?;
    let raw: f64 = cap[1].parse().ok()?;
    let kind = cap[2].to_lowercase();
    Some(if kind.contains("used") {
        (100.0 - raw).clamp(0.0, 100.0)
    } else {
        raw.clamp(0.0, 100.0)
    })
}

fn extract_reset(label: &str, text: &str) -> Option<String> {
    let lines: Vec<&str> = text.lines().collect();
    let label_l = label.to_lowercase();
    for (idx, line) in lines.iter().enumerate() {
        if !line.to_lowercase().contains(&label_l) {
            continue;
        }
        for candidate in lines.iter().skip(idx).take(14) {
            let lower = candidate.to_lowercase();
            if lower.contains("reset")
                || (lower.contains("in ") && (lower.contains('h') || lower.contains('m')))
            {
                return Some(candidate.trim().to_string());
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_mac_style_output() {
        let text = r#"
Current session
████ 28% used
Resets 4:59pm

Current week
██ 55% used
Resets in 3d

Opus
10% used
"#;
        let m = parse_claude_usage_text(text).unwrap();
        assert!(m.iter().any(|x| x.kind == "session" && x.remaining_percent == Some(72.0)));
        assert!(m.iter().any(|x| x.kind == "weekly" && x.remaining_percent == Some(45.0)));
        assert!(m.iter().any(|x| x.label == "Opus" && x.remaining_percent == Some(90.0)));
    }
}
