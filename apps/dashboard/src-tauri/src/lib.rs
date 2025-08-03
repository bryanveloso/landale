use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    Manager, WindowEvent, WebviewWindowBuilder, WebviewUrl,
};

#[tauri::command]
async fn create_telemetry_window(app: tauri::AppHandle) -> Result<(), String> {
    // Check if telemetry window already exists
    if app.get_webview_window("telemetry").is_some() {
        // If it exists, just focus it
        if let Some(window) = app.get_webview_window("telemetry") {
            let _ = window.show();
            let _ = window.set_focus();
        }
        return Ok(());
    }

    // Create new telemetry window
    let telemetry_window = WebviewWindowBuilder::new(
        &app,
        "telemetry",
        WebviewUrl::App("#/telemetry".into())
    )
    .title("Landale Telemetry")
    .inner_size(1200.0, 800.0)
    .min_inner_size(800.0, 600.0)
    .resizable(true)
    .build()
    .map_err(|e| e.to_string())?;

    // Show and focus the new window
    let _ = telemetry_window.show();
    let _ = telemetry_window.set_focus();

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .plugin(tauri_plugin_positioner::init())
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }

            // Create system tray menu
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let show = MenuItem::with_id(app, "show", "Show Dashboard", true, None::<&str>)?;
            let hide = MenuItem::with_id(app, "hide", "Hide Dashboard", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &hide, &quit])?;

            // Create system tray
            let _tray = TrayIconBuilder::new()
                .menu(&menu)
                .icon(app.default_window_icon().unwrap().clone())
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => {
                        app.exit(0);
                    }
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    "hide" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.hide();
                        }
                    }
                    _ => {}
                })
                .build(app)?;

            // Configure main window behavior
            if let Some(window) = app.get_webview_window("main") {
                // Handle window close event to minimize to tray instead of closing
                let window_handle = window.clone();
                window.on_window_event(move |event| match event {
                    WindowEvent::CloseRequested { api, .. } => {
                        let _ = window_handle.hide();
                        api.prevent_close();
                    }
                    _ => {}
                });
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![create_telemetry_window])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
