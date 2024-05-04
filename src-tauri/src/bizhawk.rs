use std::io;

use log::{error, info};
use anyhow::{Error, Result};
use socketioxide::SocketIo;
use tokio::net::{TcpListener, TcpStream};

async fn init() -> Result<TcpListener> {
    // Set up TCP server to listen for incoming connections.
    let listener = TcpListener::bind("0.0.0.0:8080").await?;
    println!("TCP Listening on: {}", listener.local_addr()?);

    Ok(listener)
}

pub async fn handle_events(io: SocketIo) -> Result<()> {
    let listener = match init().await {
        Ok(listener) => listener,
        Err(e) => {
            io.emit("bizhawk:error", e.to_string()).ok();
            return Err(e);
        }
    };

    match listener.accept().await {
        Ok((stream, addr)) => {
            println!("Accepted connection from: {}", addr);
            tokio::spawn(handle_stream(stream, io.clone()));
        }
        Err(e) => {
            error!("Failed to accept connection: {}", e);
        }
    }

    Ok(())
}

async fn handle_stream(stream: TcpStream, io: SocketIo) -> Result<()> {
    loop {
        // Wait for the socket to be readable.
        stream.readable().await?;

        // Creating the buffer **after** the `await` prevents it from
        // being stored in the async task.
        let mut buf = [0; 1024];

        // Try to read data, this may still fail with `WouldBlock`
        // if the readiness event is a false positive.
        match stream.try_read(&mut buf) {
            Ok(0) => continue,
            Ok(n) => {
                let data = &buf[..n];
                let text = std::str::from_utf8(data)?;

                // Data is recieved from the client like so:
                // "<message_length> <message>"
                let mut parts = text.split_whitespace();

                let message_length: usize = parts.next().unwrap().parse().expect("Error parsing message length");
                let message: String = parts.collect::<Vec<&str>>().join(" ");

                println!("Length: {}, Message: {}", message_length, message);
                io.emit("bizhawk:message", message).ok();
                continue;
            }
            Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {
                // The socket wasn't actually ready, spurious event.
                continue;
            }
            Err(e) => {
                return Err(e.into());
            }
        }
    }
}
