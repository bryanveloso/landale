use std::{env, time::Duration};

use anyhow::{anyhow, Result};
use dotenvy::dotenv;
use futures_util::{pin_mut, StreamExt};
use obws::{events::Event, Client};
use socketioxide::SocketIo;
use tokio::time;
use tokio_stream::wrappers::IntervalStream;

#[derive(Clone, serde::Serialize)]
struct MicrophoneStatus {
    muted: bool,
}

async fn init() -> Result<Client> {
    // Authenticate and attempt to connect to OBS.
    dotenv().ok();
    let password = env::var("OBS_WEBSOCKET_PASSWORD")
        .map_err(|_| anyhow!("OBS_WEBSOCKET_PASSWORD not set in .env file."))?;
    let client = Client::connect("demi.local", 4455, Some(password)).await?;

    Ok(client)
}

pub async fn handle_events(io: SocketIo) -> Result<()> {
    let client = match init().await {
        Ok(client) => client,
        Err(e) => {
            io.emit("obs:error", e.to_string()).ok();
            return Err(e);
        }
    };

    // Listen for events.
    let events = client.events()?;
    pin_mut!(events);

    while let Some(event) = events.next().await {
        println!("{event:#?}");

        match event {
            Event::InputMuteStateChanged { name, muted } => {
                if name == "[🎙️] RE20" {
                    io.emit("obs:microphone", MicrophoneStatus { muted }).ok();
                }
            }

            _ => {}
        }
    }

    Ok(())
}

pub async fn handle_status(io: SocketIo) -> Result<()> {
    let client = match init().await {
        Ok(client) => client,
        Err(e) => {
            io.emit("obs:error", e.to_string()).ok();
            return Err(e);
        }
    };

    // Put GetStreamStatus on a timer and send the result to the client every second.
    let mut stream = IntervalStream::new(time::interval(Duration::from_secs(1)));
    while let Some(_timer) = stream.next().await {
        let status = client.streaming().status().await?;
        io.emit("obs:status", status).ok();
    }

    Ok(())
}

pub async fn handle_scenes() -> Result<()> {
    let client = match init().await {
        Ok(client) => client,
        Err(e) => return Err(e) 
    };

    client.inputs().press_properties_button("[🌎] Omnywidget", "refreshnocache").await.ok();
    client.inputs().press_properties_button("[🌎] Introduction Background", "refreshnocache").await.ok();
    client.inputs().press_properties_button("[🌎] Kaizo Background", "refreshnocache").await.ok();

    Ok(())
}
