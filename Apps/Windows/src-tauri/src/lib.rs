use chrono::Local;
use serde::{Deserialize, Serialize};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager, Runtime,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaCard {
    pub provider_id: String,
    pub display_name: String,
    pub status: String,
    pub session_remaining_percent: Option<f64>,
    pub weekly_remaining_percent: Option<f64>,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotPayload {
    pub updated_at: String,
    pub cards: Vec<QuotaCard>,
}

/// MVP: placeholder cards. Real probes (Codex / MiniMax / Grok) land next.
#[tauri::command]
fn get_usage_snapshot() -> SnapshotPayload {
    SnapshotPayload {
        updated_at: Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
        cards: vec![
            QuotaCard {
                provider_id: "codex".into(),
                display_name: "ChatGPT (Codex)".into(),
                status: "unknown".into(),
                session_remaining_percent: None,
                weekly_remaining_percent: None,
                detail: "将读取 %USERPROFILE%\\.codex\\auth.json".into(),
            },
            QuotaCard {
                provider_id: "minimax".into(),
                display_name: "MiniMax".into(),
                status: "unknown".into(),
                session_remaining_percent: None,
                weekly_remaining_percent: None,
                detail: "设置中配置 API Key 后探测".into(),
            },
            QuotaCard {
                provider_id: "grok".into(),
                display_name: "Grok".into(),
                status: "unknown".into(),
                session_remaining_percent: None,
                weekly_remaining_percent: None,
                detail: "将读取 %USERPROFILE%\\.grok\\auth.json".into(),
            },
        ],
    }
}

fn show_main_window<R: Runtime>(app: &tauri::AppHandle<R>) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![get_usage_snapshot])
        .setup(|app| {
            let quit = MenuItem::with_id(app, "quit", "退出智额", true, None::<&str>)?;
            let show = MenuItem::with_id(app, "show", "打开智额", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &quit])?;

            let mut tray = TrayIconBuilder::new()
                .menu(&menu)
                .tooltip("智额 · SmartQuota");
            if let Some(icon) = app.default_window_icon() {
                tray = tray.icon(icon.clone());
            }
            let _tray = tray
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => {
                        app.exit(0);
                    }
                    "show" => show_main_window(app),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        show_main_window(tray.app_handle());
                    }
                })
                .build(app)?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running 智额");
}
