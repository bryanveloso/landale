defmodule ServerWeb.Endpoint do
  @moduledoc "Phoenix endpoint configuration for the server application."

  use Phoenix.Endpoint, otp_app: :server

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_server_key",
    signing_salt: "Hd846dm2",
    same_site: "Lax"
  ]

  # socket "/live", Phoenix.LiveView.Socket,
  #   websocket: [connect_info: [session: @session_options]],
  #   longpoll: [connect_info: [session: @session_options]]

  # WebSocket endpoint for dashboard and event clients
  socket "/socket", ServerWeb.UserSocket,
    websocket: [
      # 90 seconds (3x client heartbeat of 30s)
      timeout: 90_000,
      # Enable transport debugging to see heartbeats
      transport_log: :debug,
      compress: true,
      check_origin: [
        # Local development
        "http://localhost:5173",
        "http://localhost:5174",
        "http://127.0.0.1:5173",
        "http://127.0.0.1:5174",
        # Overlays app (port 8008)
        "http://localhost:8008",
        "http://saya:8008",
        # Tailscale network machines (correct domain format)
        "https://saya.tailnet-dffc.ts.net:5173",
        "https://zelan.tailnet-dffc.ts.net:5173",
        "https://demi.tailnet-dffc.ts.net:5173",
        "https://alys.tailnet-dffc.ts.net:5173",
        # Local machine names for development
        "http://saya.local:5173",
        "http://zelan.local:5173",
        "http://demi.local:5173",
        "http://alys.local:5173"
      ]
    ],
    longpoll: false

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :server,
    gzip: false,
    only: ServerWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :server
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # SSL enforcement in production only
  if Application.compile_env(:server, :env) == :prod do
    plug Plug.SSL,
      rewrite_on: [:x_forwarded_proto],
      host: nil,
      hsts: true,
      preload: true
  end

  # Additional security headers
  plug :put_secure_headers

  # CORS support for OpenAPI/Swagger and dashboard
  plug Corsica,
    origins: [
      "http://localhost:5173",
      "http://localhost:5174",
      "http://localhost:3000",
      "http://localhost:8008",
      "http://saya:8008",
      "http://zelan:3000",
      "http://zelan:5173",
      "http://zelan:5174",
      "https://saya.tailnet-dffc.ts.net:5173",
      "https://zelan.tailnet-dffc.ts.net:5173",
      "https://demi.tailnet-dffc.ts.net:5173",
      "https://alys.tailnet-dffc.ts.net:5173"
    ],
    allow_headers: ["content-type", "authorization", "x-correlation-id"],
    allow_methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_credentials: true,
    max_age: 86_400

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ServerWeb.Router

  # Add security headers to all responses
  defp put_secure_headers(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_header("x-frame-options", "DENY")
    |> Plug.Conn.put_resp_header("x-content-type-options", "nosniff")
    |> Plug.Conn.put_resp_header("x-xss-protection", "1; mode=block")
    |> Plug.Conn.put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> Plug.Conn.put_resp_header(
      "content-security-policy",
      "default-src 'self'; " <>
        "script-src 'self' 'unsafe-inline' 'unsafe-eval'; " <>
        "style-src 'self' 'unsafe-inline'; " <>
        "img-src 'self' data: https:; " <>
        "font-src 'self'; " <>
        "connect-src 'self' ws: wss:; " <>
        "frame-ancestors 'none'"
    )
  end
end
