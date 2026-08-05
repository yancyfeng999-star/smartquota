//! Kiro — interactive CLI `/usage` (Mac KiroUsageProbe).

use crate::models::QuotaMeter;
use regex::Regex;
use std::process::Command;

pub fn available() -> bool {
    Command::new("kiro-cli").arg("--help").output().is_ok()
        || Command::new("kiro").arg("--help").output().is_ok()
}

pub async fn probe_kiro() -> Result<Vec<QuotaMeter>, String> {
    tokio::task::spawn_blocking(|| {
        let bin = if Command::new("kiro-cli").arg("--help").output().is_ok() {
            "kiro-cli"
        } else {
            "kiro"
        };
        let output = Command::new(bin)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .and_then(|mut child| {
                use std::io::Write;
                if let Some(mut stdin) = child.stdin.take() {
                    let _ = stdin.write_all(b"/usage\n/quit\n");
                }
                child.wait_with_output()
            })
            .map_err(|_| "未找到 kiro-cli / kiro".to_string())?;
        let text = strip_ansi(&format!(
            "{}\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        ));
        parse_kiro(&text)
    })
    .await
    .map_err(|e| e.to_string())?
}

fn strip_ansi(s: &str) -> String {
    Regex::new(r"\x1b\[[0-9;]*[a-zA-Z]")
        .map(|re| re.replace_all(s, "").to_string())
        .unwrap_or_else(|_| s.to_string())
}

pub fn parse_kiro(text: &str) -> Result<Vec<QuotaMeter>, String> {
    let mut meters = Vec::new();
    // Bonus credits: 122.54/500 credits used
    if let Ok(re) = Regex::new(r"(?i)Bonus credits:\s*([\d.]+)/([\d.]+)") {
        if let Some(cap) = re.captures(text) {
            let used: f64 = cap[1].parse().unwrap_or(0.0);
            let total: f64 = cap[2].parse().unwrap_or(0.0);
            if total > 0.0 {
                let rem = ((total - used) / total * 100.0).clamp(0.0, 100.0);
                let days = Regex::new(r"expires in (\d+) days")
                    .ok()
                    .and_then(|r| r.captures(text))
                    .and_then(|c| c[1].parse::<i64>().ok());
                let reset_unix = days.map(|d| {
                    chrono::Utc::now().timestamp() + d * 86400
                });
                let reset_text = days.map(|d| format!("Expires in {d} days"));
                meters.push(QuotaMeter::weekly(Some(rem), reset_text, reset_unix));
            }
        }
    }
    // Credits (0.00 of 50 covered in plan)
    if let Ok(re) = Regex::new(r"(?i)Credits\s*\(([\d.]+)\s+of\s+([\d.]+)") {
        if let Some(cap) = re.captures(text) {
            let used: f64 = cap[1].parse().unwrap_or(0.0);
            let total: f64 = cap[2].parse().unwrap_or(0.0);
            if total > 0.0 {
                let rem = ((total - used) / total * 100.0).clamp(0.0, 100.0);
                meters.push(QuotaMeter::time_limit(
                    "Credits",
                    Some(rem),
                    Some(format!("{used} of {total}")),
                    None,
                ));
            }
        }
    }
    // Progress bar percent
    if meters.is_empty() {
        if let Ok(re) = Regex::new(r"(\d{1,3})\s*%") {
            if let Some(cap) = re.captures(text) {
                let used: f64 = cap[1].parse().unwrap_or(0.0);
                meters.push(QuotaMeter::time_limit(
                    "Usage",
                    Some((100.0 - used).clamp(0.0, 100.0)),
                    None,
                    None,
                ));
            }
        }
    }
    if meters.is_empty() {
        return Err("无法解析 kiro /usage 输出".into());
    }
    Ok(meters)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_sample() {
        let t = "Bonus credits: 100/500 credits used, expires in 10 days\nCredits (5.00 of 50 covered in plan)\n";
        let m = parse_kiro(t).unwrap();
        assert!(m.len() >= 1);
    }
}
