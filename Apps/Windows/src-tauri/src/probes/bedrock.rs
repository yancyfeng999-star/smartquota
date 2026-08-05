//! AWS Bedrock — CloudWatch-style cost summary via AWS CLI if available.

use crate::models::QuotaMeter;
use serde_json::Value;
use std::process::Command;

pub fn available() -> bool {
    home_aws_exists() || Command::new("aws").arg("--version").output().is_ok()
}

fn home_aws_exists() -> bool {
    dirs::home_dir()
        .map(|h| h.join(".aws").join("credentials").exists())
        .unwrap_or(false)
}

pub async fn probe_bedrock() -> Result<Vec<QuotaMeter>, String> {
    tokio::task::spawn_blocking(|| {
        if !Command::new("aws").arg("--version").output().is_ok() {
            return Err(
                "未找到 AWS CLI。请安装并配置 ~/.aws/credentials 后重试。".into(),
            );
        }
        // List foundation models as connectivity check + optional cost explorer is heavy
        let output = Command::new("aws")
            .args([
                "bedrock",
                "list-foundation-models",
                "--query",
                "length(modelSummaries)",
                "--output",
                "json",
            ])
            .output()
            .map_err(|e| e.to_string())?;
        if !output.status.success() {
            let err = String::from_utf8_lossy(&output.stderr);
            return Err(format!("aws bedrock 调用失败: {err}"));
        }
        let count_text = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let count: i64 = count_text.parse().unwrap_or(0);

        let mut meters = vec![QuotaMeter::time_limit(
            "Models",
            Some(100.0),
            Some(format!("可访问 {count} 个 foundation models")),
            None,
        )];

        // Cost Explorer optional (permissions often missing)
        let today = chrono::Utc::now().format("%Y-%m-%d").to_string();
        let month_start = chrono::Utc::now().format("%Y-%m-01").to_string();
        if let Ok(cost_out) = Command::new("aws")
            .args([
                "ce",
                "get-cost-and-usage",
                "--time-period",
                &format!("Start={month_start},End={today}"),
                "--granularity",
                "MONTHLY",
                "--metrics",
                "UnblendedCost",
                "--filter",
                r#"{"Dimensions":{"Key":"SERVICE","Values":["Amazon Bedrock"]}}"#,
                "--output",
                "json",
            ])
            .output()
        {
            if cost_out.status.success() {
                if let Ok(json) = serde_json::from_slice::<Value>(&cost_out.stdout) {
                    if let Some(amount) = json
                        .pointer("/ResultsByTime/0/Total/UnblendedCost/Amount")
                        .and_then(|v| v.as_str())
                        .and_then(|s| s.parse::<f64>().ok())
                    {
                        meters.push(QuotaMeter::time_limit(
                            "本月费用",
                            None,
                            Some(format!("${amount:.2}")),
                            None,
                        ));
                    }
                }
            }
        }

        Ok(meters)
    })
    .await
    .map_err(|e| e.to_string())?
}
