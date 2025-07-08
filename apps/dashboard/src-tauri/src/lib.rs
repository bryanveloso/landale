use tauri::{
  menu::{Menu, MenuItem},
  tray::TrayIconBuilder,
  Manager, WindowEvent
};

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
        .on_menu_event(|app, event| {
          match event.id.as_ref() {
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
          }
        })
        .build(app)?;

      // Configure main window behavior
      if let Some(window) = app.get_webview_window("main") {
        // Handle window close event to minimize to tray instead of closing
        let window_handle = window.clone();
        window.on_window_event(move |event| {
          match event {
            WindowEvent::CloseRequested { api, .. } => {
              let _ = window_handle.hide();
              api.prevent_close();
            }
            _ => {}
          }
        });
      }

      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
