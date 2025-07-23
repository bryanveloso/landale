defmodule Server.Services.TwitchPropertyTest do
  @moduledoc """
  Property-based tests for the Twitch EventSub service.

  Tests invariants and properties including:
  - State consistency under various operations
  - Subscription limit enforcement
  - Cache TTL behavior
  - Connection state transitions
  - Error handling resilience
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Server.Services.Twitch

  setup do
    # Start PubSub only if not already started
    case Process.whereis(Server.PubSub) do
      nil -> start_supervised!({Phoenix.PubSub, name: Server.PubSub})
      _pid -> :ok
    end

    # Start CircuitBreakerServer if not already started
    case Process.whereis(Server.CircuitBreakerServer) do
      nil -> start_supervised!(Server.CircuitBreakerServer)
      _pid -> :ok
    end

    # Start TaskSupervisor if not already started
    case Process.whereis(Server.TaskSupervisor) do
      nil -> start_supervised!({Task.Supervisor, name: Server.TaskSupervisor})
      _pid -> :ok
    end

    # Start DynamicSupervisor if not already started
    case Process.whereis(Server.DynamicSupervisor) do
      nil -> start_supervised!({DynamicSupervisor, name: Server.DynamicSupervisor, strategy: :one_for_one})
      _pid -> :ok
    end

    # Create cache table if not exists
    if :ets.info(:server_cache) == :undefined do
      :ets.new(:server_cache, [:set, :public, :named_table])
    end

    # Create a test cache table if not exists  
    if :ets.info(:twitch_service) == :undefined do
      :ets.new(:twitch_service, [:set, :public, :named_table])
    end

    :ok
  end

  describe "subscription management properties" do
    property "subscription count never exceeds max limit" do
      check all(
              event_types <- list_of(event_type_gen(), min_length: 1, max_length: 500),
              user_ids <- list_of(user_id_gen(), min_length: 1, max_length: 10)
            ) do
        _pid = ensure_twitch_started()

        # Try to create many subscriptions
        for event_type <- event_types, user_id <- user_ids do
          condition = %{"broadcaster_user_id" => user_id}
          Twitch.create_subscription(event_type, condition)
        end

        # Get metrics
        metrics = Twitch.get_subscription_metrics()

        # Verify count doesn't exceed limit
        assert metrics.subscription_count <= metrics.subscription_max_count
        assert metrics.subscription_total_cost <= metrics.subscription_max_cost
      end
    end

    property "subscription conditions are validated" do
      check all(
              event_type <- event_type_gen(),
              condition <- subscription_condition_gen()
            ) do
        _pid = ensure_twitch_started()

        result = Twitch.create_subscription(event_type, condition)

        # Result should be either ok or error, never crash
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end

  describe "connection state properties" do
    property "connection state remains consistent" do
      check all(num_reads <- integer(1..20)) do
        _pid = ensure_twitch_started()

        # Read state multiple times
        states =
          for _ <- 1..num_reads do
            Twitch.get_connection_state()
          end

        # All states should be valid
        for state <- states do
          assert is_boolean(state.connected)
          assert state.connection_state in ["disconnected", "connecting", "connected", "reconnecting", "error"]
          assert is_binary(state.connection_state)

          # If connected, should have session_id
          if state.connected do
            assert not is_nil(state.session_id)
          end
        end
      end
    end
  end

  describe "cache properties" do
    property "cached values remain consistent within TTL" do
      check all(
              cache_key <- member_of([:full_state, :connection_state, :subscription_metrics]),
              num_reads <- integer(2..10)
            ) do
        _pid = ensure_twitch_started()

        # Clear specific cache
        :ets.delete(:twitch_service, cache_key)

        # Read multiple times quickly
        results =
          for _ <- 1..num_reads do
            case cache_key do
              :full_state -> Twitch.get_state()
              :connection_state -> Twitch.get_connection_state()
              :subscription_metrics -> Twitch.get_subscription_metrics()
            end
          end

        # All results should be identical (same cached value)
        first_result = hd(results)
        assert Enum.all?(results, &(&1 == first_result))
      end
    end
  end

  describe "error handling properties" do
    property "invalid subscription IDs don't crash the service" do
      check all(
              subscription_ids <-
                list_of(string(:alphanumeric, min_length: 1, max_length: 20), min_length: 1, max_length: 10)
            ) do
        _pid = ensure_twitch_started()

        # Try to delete non-existent subscriptions
        for id <- subscription_ids do
          result = Twitch.delete_subscription(id)
          assert match?({:error, _}, result)
        end

        # Service should still be responsive
        assert {:ok, _} = Twitch.get_status()
      end
    end

    property "malformed event types are handled gracefully" do
      check all(
              event_type <- string(:alphanumeric, min_length: 0, max_length: 100),
              condition <- map_of(string(:alphanumeric), string(:alphanumeric))
            ) do
        _pid = ensure_twitch_started()

        result = Twitch.create_subscription(event_type, condition)

        # Should never crash, always return ok or error
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end

  describe "state consistency properties" do
    property "state fields maintain valid types" do
      check all(num_operations <- integer(0..20)) do
        pid = ensure_twitch_started()

        # Perform random read operations
        for _ <- 1..num_operations do
          case :rand.uniform(3) do
            1 -> Twitch.get_state()
            2 -> Twitch.get_connection_state()
            3 -> Twitch.get_subscription_metrics()
          end
        end

        # Get final state
        state = :sys.get_state(pid)

        # Verify state structure
        assert %Twitch{} = state
        assert is_map(state.subscriptions)
        assert is_integer(state.cloudfront_retry_count)
        assert is_boolean(state.default_subscriptions_created)
        assert is_map(state.state)
        assert is_integer(state.state.subscription_count)
        assert is_integer(state.state.subscription_total_cost)
      end
    end
  end

  describe "concurrent operation properties" do
    property "concurrent reads don't interfere" do
      check all(num_concurrent <- integer(2..20)) do
        _pid = ensure_twitch_started()

        # Spawn concurrent read operations
        tasks =
          for _ <- 1..num_concurrent do
            Task.async(fn ->
              case :rand.uniform(4) do
                1 -> {:state, Twitch.get_state()}
                2 -> {:status, Twitch.get_status()}
                3 -> {:connection, Twitch.get_connection_state()}
                4 -> {:metrics, Twitch.get_subscription_metrics()}
              end
            end)
          end

        results = Task.await_many(tasks, 5000)

        # All operations should succeed
        assert Enum.all?(results, fn
                 {:state, state} -> is_map(state)
                 {:status, {:ok, status}} -> is_map(status)
                 {:connection, conn} -> is_map(conn)
                 {:metrics, metrics} -> is_map(metrics)
                 _ -> false
               end)
      end
    end
  end

  # Generator functions

  defp event_type_gen do
    member_of([
      "channel.update",
      "channel.follow",
      "channel.subscribe",
      "channel.subscription.gift",
      "channel.subscription.message",
      "channel.cheer",
      "channel.raid",
      "channel.ban",
      "channel.unban",
      "channel.moderator.add",
      "channel.moderator.remove",
      "stream.online",
      "stream.offline",
      "user.update"
    ])
  end

  defp user_id_gen do
    map(integer(100_000..999_999), &to_string/1)
  end

  defp subscription_condition_gen do
    one_of([
      # Simple condition
      map(user_id_gen(), fn id ->
        %{"broadcaster_user_id" => id}
      end),
      # Complex condition
      map({user_id_gen(), user_id_gen()}, fn {broadcaster_id, moderator_id} ->
        %{
          "broadcaster_user_id" => broadcaster_id,
          "moderator_user_id" => moderator_id
        }
      end),
      # Invalid condition
      constant(%{})
    ])
  end

  # Helper function to ensure Twitch is started
  defp ensure_twitch_started do
    case Process.whereis(Server.Services.Twitch) do
      nil ->
        {:ok, pid} = start_supervised(Twitch)
        pid

      pid when is_pid(pid) ->
        # Service already running, just return the pid
        pid
    end
  end
end
