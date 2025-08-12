defmodule Mix.Tasks.Twitch.Token do
  @moduledoc """
  Twitch OAuth token generator for Landale.

  ## Usage

      mix twitch.token      # Generate OAuth tokens
      mix twitch.token help # Show help

  ## Workflow

  1. Run `mix twitch.token` to start OAuth flow
  2. Authorize in your browser
  3. Copy the JSON output
  4. Paste in dashboard OAuth page
  5. Click "Save Tokens"

  ## Required Environment Variables

  - TWITCH_CLIENT_ID: Your Twitch application client ID
  - TWITCH_CLIENT_SECRET: Your Twitch application client secret

  Get these from: https://dev.twitch.tv/console/apps

  ## Features

  ✅ Interactive OAuth flow with browser integration
  ✅ Outputs JSON for dashboard upload
  ✅ No file storage - just copy/paste
  ✅ Clean, simple workflow
  """

  use Mix.Task
  require Logger

  @shortdoc "Create and configure Twitch OAuth tokens interactively"

  # Required scopes for Landale functionality
  @required_scopes [
    # Stream/channel management
    "channel:read:subscriptions",
    "channel:read:redemptions",
    "channel:read:polls",
    "channel:read:predictions",
    "channel:read:hype_train",
    "channel:read:goals",
    "channel:read:charity",
    "channel:read:vips",
    "channel:read:ads",
    "channel:manage:broadcast",
    "channel:manage:redemptions",
    "channel:manage:videos",
    "channel:manage:ads",
    "channel:edit:commercial",
    "channel:bot",

    # Moderation and chat
    "moderator:read:followers",
    "moderator:read:shoutouts",
    "moderator:read:chat_settings",
    "moderator:manage:announcements",
    "user:read:chat",
    "user:write:chat",
    "user:bot",
    "chat:read",
    "chat:edit",

    # Monetization
    "bits:read",

    # Content
    "clips:edit"
  ]

  # Twitch OAuth URLs
  @auth_url "https://id.twitch.tv/oauth2/authorize"
  @token_url "https://id.twitch.tv/oauth2/token"
  @validate_url "https://id.twitch.tv/oauth2/validate"

  def run(args) do
    # Parse command line arguments
    case parse_args(args) do
      {:interactive} ->
        run_interactive_flow()

      {:help} ->
        display_help()

      {:error, reason} ->
        display_error("Invalid arguments: #{reason}")
        display_quick_help()
        System.halt(1)
    end
  end

  defp run_interactive_flow do
    # Display professional welcome banner
    display_welcome_banner()

    # Load environment and start minimal apps
    start_minimal_app()

    # Quick environment check after loading .env
    if not environment_ready?() do
      display_environment_help()
      System.halt(1)
    end

    case validate_environment() do
      {:ok, config} ->
        create_token_interactive(config)

      {:error, reason} ->
        display_error("Configuration Error: #{reason}")
        System.halt(1)
    end
  end

  defp validate_environment do
    client_id = System.get_env("TWITCH_CLIENT_ID")
    client_secret = System.get_env("TWITCH_CLIENT_SECRET")

    case {client_id, client_secret} do
      {nil, _} ->
        {:error, "TWITCH_CLIENT_ID environment variable is required"}

      {_, nil} ->
        {:error, "TWITCH_CLIENT_SECRET environment variable is required"}

      {"", _} ->
        {:error, "TWITCH_CLIENT_ID cannot be empty"}

      {_, ""} ->
        {:error, "TWITCH_CLIENT_SECRET cannot be empty"}

      {client_id, client_secret} ->
        display_success("Environment configuration validated")
        IO.puts("#{dim("  Client ID:")} #{String.slice(client_id, 0..7)}#{dim("...")}")
        IO.puts("#{dim("  Client Secret:")} #{String.slice(client_secret, 0..3)}#{dim("...")}")
        IO.puts("")

        {:ok,
         %{
           client_id: client_id,
           client_secret: client_secret
         }}
    end
  end

  defp create_token_interactive(config) do
    display_section_header("Security Information")

    IO.puts(dim("  • This will open Twitch in your browser for authorization"))
    IO.puts(dim("  • You'll authorize the application with your Twitch account"))
    IO.puts(dim("  • Tokens will be outputted as JSON for dashboard upload"))
    IO.puts(dim("  • Never share these tokens or commit them to version control"))
    IO.puts("")

    if prompt_continue("Ready to continue?") do
      step_1_generate_auth_url(config)
    else
      display_info("Token creation cancelled")
    end
  end

  defp step_1_generate_auth_url(config) do
    display_step_header(1, "Browser Authorization")

    # Generate a secure state parameter
    state = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    # Build authorization URL
    scopes_string = Enum.join(@required_scopes, " ")

    auth_params = %{
      "client_id" => config.client_id,
      "redirect_uri" => "http://localhost:3000",
      "response_type" => "code",
      "scope" => scopes_string,
      "state" => state
    }

    query_string = URI.encode_query(auth_params)
    full_auth_url = "#{@auth_url}?#{query_string}"

    display_info("Opening Twitch authorization page in your browser...")
    IO.puts("")

    display_subsection("Permissions being requested:")

    Enum.each(@required_scopes, fn scope ->
      description = scope_description(scope)
      IO.puts("  #{bright("•")} #{scope} #{dim("- #{description}")}")
    end)

    IO.puts("")
    display_subsection("Authorization URL:")
    IO.puts("  #{dim(full_auth_url)}")
    IO.puts("")

    # Try to open browser with better feedback
    case System.cmd("open", [full_auth_url], stderr_to_stdout: true) do
      {_, 0} ->
        display_success("Browser opened successfully")

      {_, _} ->
        display_warning("Could not open browser automatically")
        IO.puts("  #{dim("Please manually copy the URL above into your browser")})")
    end

    IO.puts("")
    step_2_get_authorization_code(config, state)
  end

  defp step_2_get_authorization_code(config, expected_state) do
    display_step_header(2, "Authorization Code")

    IO.puts("After authorizing in your browser:")
    IO.puts("")
    IO.puts("  #{bright("1.")} You'll be redirected to: #{bright("http://localhost:3000?code=...")}")
    IO.puts("  #{bright("2.")} Copy the #{bright("entire URL")} from your browser's address bar")
    IO.puts("  #{bright("3.")} Paste it below")
    IO.puts("")
    IO.puts("#{warning_icon()} #{dim("The redirect will show an error page (this is normal)")}")
    IO.puts("#{dim("We only need the URL containing the authorization code.")}")
    IO.puts("")

    case get_user_input("#{bright("Paste the full redirect URL:")} ") do
      {:ok, url} ->
        case parse_authorization_response(url, expected_state) do
          {:ok, code} ->
            display_success("Authorization code extracted successfully")
            step_3_exchange_tokens(config, code)

          {:error, reason} ->
            display_error("Authorization failed: #{reason}")

            if prompt_continue("Try again?") do
              step_2_get_authorization_code(config, expected_state)
            end
        end

      {:error, :cancelled} ->
        display_info("Token creation cancelled")
    end
  end

  defp step_3_exchange_tokens(config, auth_code) do
    display_step_header(3, "Token Exchange")

    display_info("Exchanging authorization code for access tokens...")
    IO.puts("")

    # Make direct HTTP call for CLI context (no circuit breaker needed)
    params = %{
      "client_id" => config.client_id,
      "client_secret" => config.client_secret,
      "code" => auth_code,
      "grant_type" => "authorization_code",
      "redirect_uri" => "http://localhost:3000"
    }

    case make_direct_token_request(@token_url, params) do
      {:ok, token_data} ->
        step_4_validate_and_store(config, token_data)

      {:error, reason} ->
        display_error("Token exchange failed: #{format_oauth_error(reason)}")
    end
  end

  defp step_4_validate_and_store(config, token_data) do
    access_token = token_data["access_token"]
    expires_in = token_data["expires_in"]

    scopes =
      case token_data["scope"] do
        scope when is_binary(scope) -> String.split(scope, " ")
        scope when is_list(scope) -> scope
        _ -> []
      end
      |> Enum.sort()

    display_success("Tokens received successfully")
    IO.puts("  #{dim("Expires in:")} #{expires_in} seconds #{dim("(#{Float.round(expires_in / 3_600, 1)} hours)")})")
    IO.puts("  #{dim("Scopes granted:")} #{Enum.join(scopes, ", ")}")
    IO.puts("")

    # Validate token with Twitch API
    display_info("Validating token with Twitch API...")

    case validate_token_with_twitch(access_token) do
      {:ok, user_info} ->
        display_success("Token validation successful")
        IO.puts("  #{dim("User:")} #{user_info["login"]} #{dim("(ID: #{user_info["user_id"]})")})")
        IO.puts("")

        step_5_store_tokens(config, token_data, user_info)

      {:error, reason} ->
        display_error("Token validation failed: #{reason}")
    end
  end

  defp step_5_store_tokens(_config, token_data, user_info) do
    display_step_header(5, "Token Output")

    # Prepare token data for JSON output

    scopes =
      case token_data["scope"] do
        scope when is_binary(scope) -> String.split(scope, " ")
        scope when is_list(scope) -> scope
        _ -> []
      end

    token_json = %{
      access_token: token_data["access_token"],
      refresh_token: token_data["refresh_token"],
      expires_in: token_data["expires_in"],
      scopes: scopes,
      user_id: user_info["user_id"]
    }

    display_success("Token generation complete!")
    IO.puts("")
    IO.puts("#{bright("Copy this JSON and paste it in the dashboard:")}")
    IO.puts("")
    IO.puts(bright("─────────────────────────────────────────────"))
    IO.puts(JSON.encode!(token_json, pretty: true))
    IO.puts(bright("─────────────────────────────────────────────"))
    IO.puts("")
    IO.puts("#{bright("Next Steps:")}")
    IO.puts("  #{bright("1.")} Copy the JSON above")
    IO.puts("  #{bright("2.")} Go to your dashboard OAuth page")
    IO.puts("  #{bright("3.")} Paste the JSON in the token field")
    IO.puts("  #{bright("4.")} Click 'Save Tokens'")
    IO.puts("")
    IO.puts("#{info_icon()} #{dim("Tokens will be encrypted and stored in the database.")}")
    IO.puts("#{dim("Automatic refresh will keep your connection active.")}")
    IO.puts("")
  end

  # Default to interactive mode
  defp parse_args([]), do: {:interactive}
  defp parse_args(["--help"]), do: {:help}
  defp parse_args(["help"]), do: {:help}
  defp parse_args(["-h"]), do: {:help}
  defp parse_args(args), do: {:error, "Unknown arguments: #{Enum.join(args, " ")}"}

  defp display_quick_help do
    IO.puts("")
    IO.puts("#{bright("Available commands:")}")
    IO.puts("  #{bright("mix twitch.token")}      #{dim("# Generate OAuth tokens")}")
    IO.puts("  #{bright("mix twitch.token help")} #{dim("# Show help")}")
    IO.puts("")
  end

  defp display_help do
    IO.puts("")
    IO.puts(bright("┌─────────────────────────────────────────────┐"))
    IO.puts(bright("│           ") <> cyan("Twitch Token Generator") <> bright("            │"))
    IO.puts(bright("│          ") <> dim("Simple OAuth Flow for Landale") <> bright("        │"))
    IO.puts(bright("└─────────────────────────────────────────────┘"))
    IO.puts("")

    IO.puts("#{bright("🎯 USAGE:")}")
    IO.puts("")
    IO.puts("  #{bright("mix twitch.token")}     #{dim("Generate OAuth tokens")}")
    IO.puts("  #{bright("mix twitch.token help")} #{dim("Show this help")}")
    IO.puts("")

    IO.puts("#{bright("📋 WORKFLOW:")}")
    IO.puts("")
    IO.puts("  #{bright("1.")} Run #{bright("mix twitch.token")}")
    IO.puts("  #{bright("2.")} Authorize in browser")
    IO.puts("  #{bright("3.")} Copy the JSON output")
    IO.puts("  #{bright("4.")} Paste in dashboard OAuth page")
    IO.puts("  #{bright("5.")} Click 'Save Tokens'")
    IO.puts("")

    IO.puts("#{bright("🔑 ENVIRONMENT SETUP:")}")
    IO.puts("")
    IO.puts("  #{bright("TWITCH_CLIENT_ID")}     #{dim("Your Twitch app client ID")}")
    IO.puts("  #{bright("TWITCH_CLIENT_SECRET")} #{dim("Your Twitch app client secret")}")
    IO.puts("")
    IO.puts("  Get these from: #{bright("https://dev.twitch.tv/console/apps")}")
    IO.puts("")

    IO.puts("#{bright("🔐 SECURITY:")}")
    IO.puts("")
    IO.puts("  #{warning_icon()} #{bright("Never commit tokens to version control")}")
    IO.puts("  #{success_icon()} #{bright("Tokens are encrypted in database")}")
    IO.puts("  #{success_icon()} #{bright("Auto-refresh keeps connection active")}")
    IO.puts("")
  end

  # Helper functions

  defp start_minimal_app do
    # Load .env file if it exists
    if File.exists?(".env") do
      load_dot_env_file()
    end

    # Start Gun for HTTP requests (JSON is now built-in)
    # Application.ensure_all_started(:jason) # No longer needed - JSON is built-in to Elixir 1.18
    Application.ensure_all_started(:gun)
    Application.ensure_all_started(:crypto)
  end

  defp load_dot_env_file do
    ".env"
    |> File.read!()
    |> String.split("\n")
    |> Enum.each(fn line ->
      line = String.trim(line)

      if !(String.starts_with?(line, "#") or line == "") do
        case String.split(line, "=", parts: 2) do
          [key, value] ->
            # Remove quotes if present
            clean_value = String.trim(value, "\"")
            System.put_env(key, clean_value)

          _ ->
            :ok
        end
      end
    end)
  rescue
    # Ignore file read errors
    _ -> :ok
  end

  # Professional CLI styling helpers
  defp display_welcome_banner do
    IO.puts("")
    IO.puts(bright("┌─────────────────────────────────────────────┐"))
    IO.puts(bright("│          ") <> cyan("Twitch Token Generator") <> bright("             │"))
    IO.puts(bright("│         ") <> dim("Landale Streaming System") <> bright("            │"))
    IO.puts(bright("└─────────────────────────────────────────────┘"))
    IO.puts("")
    IO.puts("This utility will help you create OAuth tokens for Twitch integration.")
    IO.puts("")
  end

  defp environment_ready? do
    client_id = System.get_env("TWITCH_CLIENT_ID")
    client_secret = System.get_env("TWITCH_CLIENT_SECRET")

    not is_nil(client_id) and not is_nil(client_secret) and
      client_id != "" and client_secret != ""
  end

  defp display_environment_help do
    display_error("Missing required environment variables")
    IO.puts("")
    IO.puts(bright("Required environment variables:"))
    IO.puts("  • TWITCH_CLIENT_ID     - Your Twitch application client ID")
    IO.puts("  • TWITCH_CLIENT_SECRET - Your Twitch application client secret")
    IO.puts("")
    IO.puts(bright("How to get these values:"))
    IO.puts("  1. Go to #{bright("https://dev.twitch.tv/console/apps")}")
    IO.puts("  2. Create a new application or select existing one")
    IO.puts("  3. Copy the Client ID and generate a Client Secret")
    IO.puts("  4. Set them in your environment:")
    IO.puts("")
    IO.puts(dim("     export TWITCH_CLIENT_ID=\"your_client_id_here\""))
    IO.puts(dim("     export TWITCH_CLIENT_SECRET=\"your_client_secret_here\""))
    IO.puts("")
    IO.puts("Then run #{bright("mix twitch.token")} again.")
    IO.puts("")
  end

  defp display_step_header(step, title) do
    IO.puts(bright("#{step}/5") <> dim(" ─ ") <> bright(title))
    IO.puts("")
  end

  defp display_section_header(title) do
    IO.puts(bright(title))
    IO.puts("")
  end

  defp display_subsection(text) do
    IO.puts(bright(text))
  end

  defp display_success(message) do
    IO.puts("#{success_icon()} #{message}")
  end

  defp display_error(message) do
    IO.puts("#{error_icon()} #{message}")
  end

  defp display_warning(message) do
    IO.puts("#{warning_icon()} #{message}")
  end

  defp display_info(message) do
    IO.puts("#{info_icon()} #{message}")
  end

  # Styling helpers
  defp bright(text), do: IO.ANSI.bright() <> text <> IO.ANSI.reset()
  defp dim(text), do: IO.ANSI.faint() <> text <> IO.ANSI.reset()
  defp cyan(text), do: IO.ANSI.cyan() <> text <> IO.ANSI.reset()
  defp green(text), do: IO.ANSI.green() <> text <> IO.ANSI.reset()
  defp red(text), do: IO.ANSI.red() <> text <> IO.ANSI.reset()
  defp yellow(text), do: IO.ANSI.yellow() <> text <> IO.ANSI.reset()

  # Icon helpers
  defp success_icon, do: green("✓")
  defp error_icon, do: red("✗")
  defp warning_icon, do: yellow("⚠")
  defp info_icon, do: cyan("ℹ")

  defp format_oauth_error({:http_error, status, body}) when is_non_struct_map(body) do
    error_msg = Map.get(body, "error", "Unknown error")
    error_desc = Map.get(body, "error_description", "")
    "HTTP #{status}: #{error_msg}#{if error_desc != "", do: " - #{error_desc}", else: ""}"
  end

  defp format_oauth_error({:http_error, status, body}) when is_binary(body) do
    "HTTP #{status}: #{body}"
  end

  defp format_oauth_error({:network_error, reason}) do
    "Network error: #{inspect(reason)}"
  end

  defp format_oauth_error(reason) do
    "#{inspect(reason)}"
  end

  defp scope_description("channel:read:subscriptions"), do: "Read subscription events"
  defp scope_description("moderator:read:followers"), do: "Read follower events"
  defp scope_description("channel:read:redemptions"), do: "Read channel point redemptions"
  defp scope_description(scope), do: scope

  defp prompt_continue(message) do
    case get_user_input("#{message} (y/N): ") do
      {:ok, response} -> String.downcase(String.trim(response)) in ["y", "yes"]
      {:error, :cancelled} -> false
    end
  end

  defp get_user_input(prompt) do
    IO.write(prompt)

    case IO.read(:stdio, :line) do
      :eof -> {:error, :cancelled}
      {:error, _} -> {:error, :cancelled}
      data -> {:ok, String.trim(data)}
    end
  end

  defp parse_authorization_response(url, expected_state) do
    case URI.parse(url) do
      %URI{query: query} when is_binary(query) ->
        params = URI.decode_query(query)

        cond do
          params["error"] ->
            {:error, "Authorization denied: #{params["error"]} - #{params["error_description"]}"}

          params["state"] != expected_state ->
            {:error, "State parameter mismatch - possible security issue"}

          is_binary(params["code"]) and params["code"] != "" ->
            {:ok, params["code"]}

          true ->
            {:error, "No authorization code found in URL"}
        end

      _ ->
        {:error, "Invalid URL format"}
    end
  end

  defp validate_token_with_twitch(access_token) do
    case make_direct_validate_request(@validate_url, access_token) do
      {:ok, user_info} -> {:ok, user_info}
      {:error, reason} -> {:error, format_oauth_error(reason)}
    end
  end

  # Direct HTTP request helpers for CLI context (no circuit breaker)

  # Helper to handle HTTP response body and status codes
  defp handle_response_body(conn, stream_ref, status, timeout) do
    case :gun.await_body(conn, stream_ref, timeout) do
      {:ok, response_body} ->
        :gun.close(conn)
        decode_json_response(response_body, status)

      {:error, reason} ->
        :gun.close(conn)
        {:error, {:network_error, reason}}
    end
  end

  defp decode_json_response(response_body, status) do
    case JSON.decode(response_body) do
      {:ok, json} when status >= 200 and status < 300 ->
        {:ok, json}

      {:ok, json} ->
        {:error, {:http_error, status, json}}

      {:error, _} ->
        {:error, {:http_error, status, response_body}}
    end
  end

  defp make_direct_token_request(url, params) do
    uri = URI.parse(url)

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"accept", "application/json"}
    ]

    body = URI.encode_query(params)

    case :gun.open(String.to_charlist(uri.host), uri.port, %{protocols: [:http2], transport: :tls}) do
      {:ok, conn} ->
        stream_ref = :gun.post(conn, String.to_charlist(uri.path || "/"), headers, body)

        case :gun.await(conn, stream_ref, 15_000) do
          {:response, :fin, status, _headers} ->
            :gun.close(conn)
            {:error, {:http_error, status, "No response body"}}

          {:response, :nofin, status, _headers} ->
            handle_response_body(conn, stream_ref, status, 15_000)

          {:error, reason} ->
            :gun.close(conn)
            {:error, {:network_error, reason}}
        end

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp make_direct_validate_request(url, access_token) do
    uri = URI.parse(url)

    headers = [
      {"authorization", "Bearer #{access_token}"},
      {"accept", "application/json"}
    ]

    case :gun.open(String.to_charlist(uri.host), uri.port, %{protocols: [:http2], transport: :tls}) do
      {:ok, conn} ->
        stream_ref = :gun.get(conn, String.to_charlist(uri.path || "/"), headers)

        case :gun.await(conn, stream_ref, 10_000) do
          {:response, :fin, status, _headers} ->
            :gun.close(conn)
            {:error, {:http_error, status, "No response body"}}

          {:response, :nofin, status, _headers} ->
            handle_response_body(conn, stream_ref, status, 10_000)

          {:error, reason} ->
            :gun.close(conn)
            {:error, {:network_error, reason}}
        end

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end
end
