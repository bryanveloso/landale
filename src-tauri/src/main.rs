/*
NOTE:

While we want to handle most of the event logic in Rust, we cannot use any
Tauri macros in this application, since the overlays aren't run in the context
of the Tauri application, but rather a separate Node instance.

We'll be instead using WebSockets to communicate between the two.
*/

// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::{
    env,
    net::{IpAddr, Ipv4Addr, SocketAddr},
};

use axum::{Router, Server};
use dotenvy::dotenv;
use env_logger;
use log::{error, info};
use serde_json::Value;
use socketioxide::{
    extract::{Data, SocketRef},
    SocketIo,
};
use tauri::{CustomMenuItem, SystemTray, SystemTrayMenu};
use tower::ServiceBuilder;
use tower_http::cors::CorsLayer;

mod obs;

// Initialize Socketoxide.
const DEFAULT_SOCKET_PORT: u16 = 7177;

async fn socket_init() {
    dotenv().ok();

    let (layer, io) = SocketIo::new_layer();

    io.ns("/", |s: SocketRef, Data::<Value>(data)| {
        info!("Received data: {:?}", data);
        s.emit("Welcome", data).ok();
    });

    tokio::spawn(obs::handle_events(io.clone()));
    tokio::spawn(obs::handle_status(io.clone()));

    let app: Router = axum::Router::new().layer(
        ServiceBuilder::new()
            .layer(CorsLayer::permissive())
            .layer(layer),
    );

    let port: u16 = env::var("SOCKET_PORT")
        .unwrap_or_else(|_| DEFAULT_SOCKET_PORT.to_string())
        .parse()
        .unwrap_or(DEFAULT_SOCKET_PORT);

    let addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), port);

    info!("Local socket server listening on: http://{}", addr);

    let server = Server::bind(&addr).serve(app.into_make_service());

    if let Err(e) = server.await {
        error!("Server error: {}", e);
    }
}

fn main() {
    env_logger::init();

    let tray = create_tray();

    tauri::async_runtime::spawn(socket_init());
    tauri::Builder::default()
        .system_tray(tray)
        .on_window_event(|event| match event.event() {
            tauri::WindowEvent::CloseRequested { api, .. } => {
                event.window().hide().unwrap();
                api.prevent_close();
            }
            _ => {}
        })
        .build(tauri::generate_context!())
        .expect("error while running tauri application")
        .run(|_app_handle, event| match event {
            tauri::RunEvent::ExitRequested { api, .. } => {
                api.prevent_exit();
            }
            _ => {}
        })
}

fn create_tray() -> SystemTray {
    let quit = CustomMenuItem::new("quit".to_string(), "Quit");
    let tray_menu = SystemTrayMenu::new().add_item(quit);

    SystemTray::new().with_menu(tray_menu)
}
