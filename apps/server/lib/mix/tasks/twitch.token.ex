defmodule Mix.Tasks.Twitch.Token do
  @moduledoc """
  Professional Twitch OAuth token management CLI with production Docker support.

  ## Quick Start

      mix twitch.token                # Interactive token creation
      mix twitch.token refresh         # Refresh tokens (Docker-friendly)
      mix twitch.token status          # Check token status
      mix twitch.token help            # Full help guide

  ## Production Docker Workflows

  ### Initial Setup (One-time)
  1. Create tokens on dev machine: `mix twitch.token`
  2. Copy to production: `rsync ./data/twitch_tokens* server:/app/data/`

  ### Ongoing Maintenance
      # Check token status
      docker exec landale-server mix twitch.token status

      # Refresh expired tokens
      docker exec landale-server mix twitch.token refresh

  ## Features

  ✅ Interactive OAuth flow with browser integration
  ✅ Docker-friendly non-interactive token refresh
  ✅ Token status monitoring and expiration warnings
  ✅ Automatic DETS + JSON backup storage
  ✅ Professional CLI styling (Astro/Vite quality)
  ✅ Comprehensive error handling and recovery
  ✅ Environment-aware storage paths (dev vs prod)

  ## Required Environment Variables

  - TWITCH_CLIENT_ID: Your Twitch application client ID
  - TWITCH_CLIENT_SECRET: Your Twitch application client secret

  Get these from: https://dev.twitch.tv/console/apps

  ## Scopes Included

  - channel:read:subscriptions (subscription events)
  - moderator:read:followers (follow events)
  - channel:read:redemptions (channel point redemptions)

  ## Security & Storage

  - Tokens stored in ./data/ (dev) or /app/data/ (Docker)
  - Automatic refresh prevents expiration
  - JSON backup created alongside DETS storage
  - All operations logged for debugging

  Run `mix twitch.token help` for complete usage guide.
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
      {:refresh} ->
        run_token_refresh()

      {:interactive} ->
        run_interactive_flow()

      {:status} ->
        run_token_status()

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
    IO.puts(dim("  • Tokens will be stored securely in your data directory"))
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
      IO.puts("  #{bright("•")} #{scope} #{dim("- #{description}")})")
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
    display_step_header(5, "Token Storage")

    display_info("Storing tokens in application data directory...")
    IO.puts("")

    # Store tokens directly in DETS for CLI context
    storage_path = get_storage_path()
    storage_dir = Path.dirname(storage_path)
    File.mkdir_p!(storage_dir)

    # Prepare token data for storage
    expires_at = DateTime.utc_now() |> DateTime.add(token_data["expires_in"], :second)

    scopes =
      case token_data["scope"] do
        scope when is_binary(scope) -> String.split(scope, " ")
        scope when is_list(scope) -> scope
        _ -> []
      end

    token_info = %{
      access_token: token_data["access_token"],
      refresh_token: token_data["refresh_token"],
      expires_at: DateTime.to_iso8601(expires_at),
      scopes: scopes,
      user_id: user_info["user_id"]
    }

    # Store in DETS directly
    case :dets.open_file(:twitch_tokens, file: String.to_charlist(storage_path)) do
      {:ok, table} ->
        case :dets.insert(table, {:token, token_info}) do
          :ok ->
            :dets.sync(table)
            :dets.close(table)

            # Also create JSON backup
            create_json_backup(storage_dir, token_info)

            display_success("Tokens stored successfully")
            IO.puts("  #{dim("Storage location:")} #{storage_path}")
            IO.puts("")

            display_success_summary(user_info, token_data)

          {:error, reason} ->
            :dets.close(table)
            display_error("Failed to store tokens: #{inspect(reason)}")
        end

      {:error, reason} ->
        display_error("Failed to open token storage: #{inspect(reason)}")
    end
  end

  defp display_success_summary(user_info, token_data) do
    scopes =
      case token_data["scope"] do
        scope when is_binary(scope) -> String.split(scope, " ")
        scope when is_list(scope) -> scope
        _ -> []
      end
      |> Enum.sort()

    IO.puts("#{success_icon()} #{bright("Token Creation Complete!")}")
    IO.puts("")
    IO.puts("#{bright("Summary:")}")
    IO.puts("  #{bright("•")} User: #{user_info["login"]} #{dim("(ID: #{user_info["user_id"]})")}")
    IO.puts("  #{bright("•")} Scopes: #{Enum.join(scopes, ", ")}")
    IO.puts("  #{bright("•")} Auto-refresh: #{bright("Enabled")}")
    IO.puts("  #{bright("•")} Storage: #{bright("Persistent")} #{dim("(survives server restarts)")}")
    IO.puts("")
    IO.puts("#{bright("Next Steps:")}")
    IO.puts("  #{bright("1.")} Start/restart your Landale server")
    IO.puts("  #{bright("2.")} Check logs for #{bright("\"Twitch service starting\"")}")
    IO.puts("  #{bright("3.")} Verify EventSub subscriptions are created")
    IO.puts("  #{bright("4.")} Test stream events in your dashboard")
    IO.puts("")
    IO.puts("#{info_icon()} #{dim("Tokens will automatically refresh before expiration.")}")
    IO.puts("#{dim("No manual intervention needed for normal operation.")}")
    IO.puts("")
  end

  # Production-friendly token refresh functions

  defp run_token_refresh do
    start_minimal_app()

    display_info("🔄 Attempting to refresh existing Twitch tokens...")
    IO.puts("")

    # Load existing tokens
    storage_path = get_storage_path()

    case load_existing_tokens(storage_path) do
      {:ok, token_info} ->
        case refresh_stored_tokens(token_info) do
          {:ok, new_token_info} ->
            store_refreshed_tokens(storage_path, new_token_info)
            display_success("Token refresh completed successfully")
            display_token_summary(new_token_info)

          {:error, reason} ->
            display_error("Token refresh failed: #{reason}")
            display_refresh_help()
            System.halt(1)
        end

      {:error, reason} ->
        display_error("Could not load existing tokens: #{reason}")
        display_refresh_help()
        System.halt(1)
    end
  end

  defp run_token_status do
    start_minimal_app()

    display_info("📊 Checking Twitch token status...")
    IO.puts("")

    storage_path = get_storage_path()

    case load_existing_tokens(storage_path) do
      {:ok, token_info} ->
        display_token_status(token_info)

      {:error, reason} ->
        display_error("No tokens found: #{reason}")
        IO.puts("")
        IO.puts("#{dim("To create new tokens, run:")} #{bright("mix twitch.token")}")
        System.halt(1)
    end
  end

  # Default to interactive mode
  defp parse_args([]), do: {:interactive}
  defp parse_args(["--refresh"]), do: {:refresh}
  defp parse_args(["refresh"]), do: {:refresh}
  defp parse_args(["--status"]), do: {:status}
  defp parse_args(["status"]), do: {:status}
  defp parse_args(["--help"]), do: {:help}
  defp parse_args(["help"]), do: {:help}
  defp parse_args(["-h"]), do: {:help}
  defp parse_args(args), do: {:error, "Unknown arguments: #{Enum.join(args, " ")}"}

  defp display_quick_help do
    IO.puts("")
    IO.puts("#{bright("Available commands:")}")
    IO.puts("  #{bright("mix twitch.token")}         #{dim("# Interactive token creation")}")
    IO.puts("  #{bright("mix twitch.token refresh")} #{dim("# Refresh existing tokens (Docker)")}")
    IO.puts("  #{bright("mix twitch.token status")}  #{dim("# Check token status")}")
    IO.puts("  #{bright("mix twitch.token help")}    #{dim("# Full help & guide")}")
    IO.puts("")
  end

  defp display_help do
    IO.puts("")
    IO.puts(bright("┌─────────────────────────────────────────────┐"))
    IO.puts(bright("│           ") <> cyan("Twitch Token Generator") <> bright("            │"))
    IO.puts(bright("│             ") <> dim("Help & Usage Guide") <> bright("             │"))
    IO.puts(bright("└─────────────────────────────────────────────┘"))
    IO.puts("")

    IO.puts("#{bright("🎯 COMMANDS:")}")
    IO.puts("")
    IO.puts("  #{bright("mix twitch.token")}                 #{dim("Interactive token creation")}")
    IO.puts("    #{dim("• Creates new OAuth tokens with browser")}")
    IO.puts("    #{dim("• Use for initial setup or when refresh fails")}")
    IO.puts("")
    IO.puts("  #{bright("mix twitch.token refresh")}         #{dim("Refresh existing tokens")}")
    IO.puts("    #{dim("• No browser required - uses refresh token")}")
    IO.puts("    #{dim("• Perfect for Docker/production environments")}")
    IO.puts("")
    IO.puts("  #{bright("mix twitch.token status")}          #{dim("Check token status")}")
    IO.puts("    #{dim("• Shows expiration time and warnings")}")
    IO.puts("    #{dim("• Use for monitoring and diagnostics")}")
    IO.puts("")
    IO.puts("  #{bright("mix twitch.token help")}            #{dim("Show this help")}")
    IO.puts("")

    IO.puts("#{bright("🐳 PRODUCTION DOCKER WORKFLOWS:")}")
    IO.puts("")
    IO.puts("#{bright("Initial Setup (One-time):")}")
    IO.puts("  #{dim("1. On development machine:")}")
    IO.puts("     #{bright("mix twitch.token")}  #{dim("# Interactive setup")}")
    IO.puts("")
    IO.puts("  #{dim("2. Copy tokens to production:")}")
    IO.puts("     #{bright("rsync ./data/twitch_tokens* server:/app/data/")}")
    IO.puts("")

    IO.puts("#{bright("Ongoing Maintenance:")}")
    IO.puts("  #{dim("# Check if tokens are expiring soon")}")
    IO.puts("  #{bright("docker exec landale-server mix twitch.token status")}")
    IO.puts("")
    IO.puts("  #{dim("# Refresh tokens when they expire")}")
    IO.puts("  #{bright("docker exec landale-server mix twitch.token refresh")}")
    IO.puts("")

    IO.puts("#{bright("Automated Monitoring (Crontab):")}")
    IO.puts("  #{dim("# Check every 30 minutes and auto-refresh if needed")}")
    IO.puts("  #{bright("*/30 * * * * docker exec landale-server \\")}")
    IO.puts("  #{bright("  bash -c \"mix twitch.token status | grep -q 'expires soon' && \\")}")
    IO.puts("  #{bright("  mix twitch.token refresh\"")}")
    IO.puts("")

    IO.puts("#{bright("📋 ENVIRONMENT SETUP:")}")
    IO.puts("")
    IO.puts("#{bright("Required Environment Variables:")}")
    IO.puts("  #{bright("TWITCH_CLIENT_ID")}       #{dim("- Your Twitch app client ID")}")
    IO.puts("  #{bright("TWITCH_CLIENT_SECRET")}   #{dim("- Your Twitch app client secret")}")
    IO.puts("")
    IO.puts("#{bright("Get Twitch Credentials:")}")
    IO.puts("  #{dim("1. Go to:")} #{bright("https://dev.twitch.tv/console/apps")}")
    IO.puts("  #{dim("2. Create new application or select existing")}")
    IO.puts("  #{dim("3. Copy Client ID and generate Client Secret")}")
    IO.puts("  #{dim("4. Set environment variables or add to .env file")}")
    IO.puts("")

    IO.puts("#{bright("🔧 TROUBLESHOOTING:")}")
    IO.puts("")
    IO.puts("#{error_icon()} #{bright("Refresh fails?")}")
    IO.puts("  #{dim("• Refresh tokens can expire (usually after 6 months)")}")
    IO.puts("  #{dim("• Solution: Create new tokens interactively")}")
    IO.puts("  #{dim("• Run:")} #{bright("mix twitch.token")} #{dim("then copy to production")}")
    IO.puts("")
    IO.puts("#{error_icon()} #{bright("No browser in Docker?")}")
    IO.puts("  #{dim("• This is expected - use refresh command instead")}")
    IO.puts("  #{dim("• Or run interactive mode on dev machine")}")
    IO.puts("")
    IO.puts("#{error_icon()} #{bright("Environment variables missing?")}")
    IO.puts("  #{dim("• Check .env file exists and has correct values")}")
    IO.puts("  #{dim("• In Docker: ensure environment is passed to container")}")
    IO.puts("")

    IO.puts("#{bright("📁 FILE LOCATIONS:")}")
    IO.puts("")
    IO.puts("#{bright("Development:")}")
    IO.puts("  #{dim("Tokens:")} ./data/twitch_tokens.dets")
    IO.puts("  #{dim("Backup:")} ./data/twitch_tokens_backup.json")
    IO.puts("")
    IO.puts("#{bright("Production (Docker):")}")
    IO.puts("  #{dim("Tokens:")} /app/data/twitch_tokens.dets")
    IO.puts("  #{dim("Backup:")} /app/data/twitch_tokens_backup.json")
    IO.puts("")

    IO.puts("#{bright("🔐 SECURITY NOTES:")}")
    IO.puts("")
    IO.puts("  #{warning_icon()} #{bright("Never commit tokens to version control")}")
    IO.puts("  #{warning_icon()} #{bright("Keep environment variables secure")}")
    IO.puts("  #{warning_icon()} #{bright("Tokens auto-refresh - no manual intervention needed")}")
    IO.puts("  #{success_icon()} #{bright("Tokens are stored locally and backed up as JSON")}")
    IO.puts("")

    IO.puts("#{info_icon()} #{dim("For more help, see the Landale documentation or contact support.")}")
    IO.puts("")
  end

  defp load_existing_tokens(storage_path) do
    case :dets.open_file(:twitch_tokens_check, file: String.to_charlist(storage_path)) do
      {:ok, table} ->
        case :dets.lookup(table, :token) do
          [{:token, token_data}] ->
            :dets.close(table)
            {:ok, deserialize_stored_token(token_data)}

          [] ->
            :dets.close(table)
            {:error, "No tokens stored"}
        end

      {:error, reason} ->
        {:error, "Cannot open token storage: #{inspect(reason)}"}
    end
  end

  defp refresh_stored_tokens(token_info) do
    case token_info.refresh_token do
      nil ->
        {:error, "No refresh token available - need to create new tokens interactively"}

      refresh_token ->
        params = %{
          "client_id" => System.get_env("TWITCH_CLIENT_ID"),
          "client_secret" => System.get_env("TWITCH_CLIENT_SECRET"),
          "grant_type" => "refresh_token",
          "refresh_token" => refresh_token
        }

        case make_direct_token_request(@token_url, params) do
          {:ok, token_data} ->
            new_expires_at = DateTime.utc_now() |> DateTime.add(token_data["expires_in"], :second)

            updated_token_info = %{
              access_token: token_data["access_token"],
              # Keep old refresh token if not provided
              refresh_token: token_data["refresh_token"] || refresh_token,
              expires_at: new_expires_at,
              scopes: token_info.scopes,
              user_id: token_info.user_id
            }

            {:ok, updated_token_info}

          {:error, reason} ->
            {:error, format_oauth_error(reason)}
        end
    end
  end

  defp store_refreshed_tokens(storage_path, token_info) do
    storage_dir = Path.dirname(storage_path)
    File.mkdir_p!(storage_dir)

    # Prepare token data for storage
    serialized_token = %{
      access_token: token_info.access_token,
      refresh_token: token_info.refresh_token,
      expires_at: DateTime.to_iso8601(token_info.expires_at),
      scopes: token_info.scopes,
      user_id: token_info.user_id
    }

    # Store in DETS
    case :dets.open_file(:twitch_tokens_refresh, file: String.to_charlist(storage_path)) do
      {:ok, table} ->
        case :dets.insert(table, {:token, serialized_token}) do
          :ok ->
            :dets.sync(table)
            :dets.close(table)

            # Create JSON backup
            create_json_backup(storage_dir, serialized_token)
            :ok

          {:error, reason} ->
            :dets.close(table)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp display_token_status(token_info) do
    now = DateTime.utc_now()
    time_until_expiry = DateTime.diff(token_info.expires_at, now, :second)

    if time_until_expiry > 0 do
      hours_left = Float.round(time_until_expiry / 3_600, 1)

      status_icon =
        cond do
          # > 24 hours
          time_until_expiry > 86_400 -> success_icon()
          # > 1 hour
          time_until_expiry > 3_600 -> warning_icon()
          # < 1 hour
          true -> error_icon()
        end

      IO.puts("#{status_icon} Token Status: #{bright("Valid")}")
      IO.puts("  #{dim("Expires in:")} #{time_until_expiry} seconds #{dim("(#{hours_left} hours)")}")
      IO.puts("  #{dim("User ID:")} #{token_info.user_id}")
      IO.puts("  #{dim("Scopes:")} #{Enum.join(token_info.scopes, ", ")}")

      if time_until_expiry < 3_600 do
        IO.puts("")
        IO.puts("#{warning_icon()} #{bright("Token expires soon!")}")
        IO.puts("  #{dim("Run refresh command:")} #{bright("mix twitch.token refresh")}")
      end
    else
      IO.puts("#{error_icon()} Token Status: #{bright("Expired")}")
      IO.puts("  #{dim("Expired:")} #{abs(time_until_expiry)} seconds ago")
      IO.puts("")
      IO.puts("#{bright("Action required:")}")
      IO.puts("  #{dim("Try refresh:")} #{bright("mix twitch.token refresh")}")
      IO.puts("  #{dim("Or recreate:")} #{bright("mix twitch.token")}")
    end

    IO.puts("")
  end

  defp display_token_summary(token_info) do
    time_until_expiry = DateTime.diff(token_info.expires_at, DateTime.utc_now(), :second)
    hours_left = Float.round(time_until_expiry / 3_600, 1)

    IO.puts("")
    IO.puts("#{bright("Updated Token Summary:")}")
    IO.puts("  #{bright("•")} User ID: #{token_info.user_id}")
    IO.puts("  #{bright("•")} Valid for: #{hours_left} hours")
    IO.puts("  #{bright("•")} Scopes: #{Enum.join(token_info.scopes, ", ")}")
    IO.puts("  #{bright("•")} Auto-refresh: #{bright("Enabled")}")
    IO.puts("")
    IO.puts("#{info_icon()} #{dim("Token will be automatically used by the running application.")}")
    IO.puts("")
  end

  defp display_refresh_help do
    IO.puts("")
    IO.puts("#{bright("Token Refresh Options:")}")
    IO.puts("  #{bright("1.")} If you have a refresh token, it may have expired")
    IO.puts("  #{bright("2.")} Create new tokens interactively: #{bright("mix twitch.token")}")
    IO.puts("  #{bright("3.")} Or run on dev machine and copy tokens to production")
    IO.puts("")
  end

  defp deserialize_stored_token(token_data) do
    %{
      access_token: token_data.access_token,
      refresh_token: token_data.refresh_token,
      expires_at: parse_stored_datetime(token_data.expires_at),
      scopes: token_data.scopes || [],
      user_id: token_data.user_id
    }
  end

  defp parse_stored_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      # Fallback to now if parse fails
      {:error, _reason} -> DateTime.utc_now()
    end
  end

  defp parse_stored_datetime(_), do: DateTime.utc_now()

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

  defp get_storage_path do
    case Application.get_env(:server, :env, :dev) do
      :prod -> "/app/data/twitch_tokens.dets"
      _ -> "./data/twitch_tokens.dets"
    end
  end

  defp create_json_backup(storage_dir, token_info) do
    backup_data = Map.put(token_info, :backup_timestamp, DateTime.utc_now() |> DateTime.to_iso8601())
    backup_file = Path.join(storage_dir, "twitch_tokens_backup.json")

    try do
      json_data = JSON.encode!(backup_data)
      File.write!(backup_file, json_data)
    rescue
      _error ->
        # Backup failure is not critical, just continue
        :ok
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
