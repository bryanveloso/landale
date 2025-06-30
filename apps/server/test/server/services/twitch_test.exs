defmodule Server.Services.TwitchTest do
  use ExUnit.Case, async: false

  setup do
    # Set test environment variables
    System.put_env("TWITCH_CLIENT_ID", "test_client_id")
    System.put_env("TWITCH_CLIENT_SECRET", "test_client_secret")

    on_exit(fn ->
      # Clean up test DETS files
      test_dets_path = "./data/twitch_tokens.dets"

      if File.exists?(test_dets_path) do
        File.rm!(test_dets_path)
      end

      # Clean up environment variables
      System.delete_env("TWITCH_CLIENT_ID")
      System.delete_env("TWITCH_CLIENT_SECRET")
    end)
  end

  # TODO: Replace with proper unit tests using mocks
  # - Mock Twitch API responses and test business logic
  # - Add contract tests for API response parsing
  # - Test retry strategies with simulated failures
  # - Test subscription management with mocked WebSocket events
  # 
  # Current integration tests removed as they test environmental connectivity
  # rather than actual functionality. See: https://github.com/bryanveloso/landale/issues/xxx
end