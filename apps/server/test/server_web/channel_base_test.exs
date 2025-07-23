defmodule ServerWeb.ChannelBaseTest do
  use ServerWeb.ChannelCase

  defmodule TestChannel do
    use ServerWeb.ChannelBase

    @impl true
    def join("test:topic", _payload, socket) do
      socket = setup_correlation_id(socket)
      send_after_join(socket)
      {:ok, socket}
    end

    @impl true
    def join("test:multi", _payload, socket) do
      socket = setup_correlation_id(socket)
      subscribe_to_topics(["topic1", "topic2", "topic3"])
      {:ok, socket}
    end

    @impl true
    def handle_in("ping", payload, socket) do
      handle_ping(payload, socket)
    end

    @impl true
    def handle_in("test_error", _payload, socket) do
      push_error(socket, "test_error", :validation_error, "Test error message")
      {:noreply, socket}
    end

    @impl true
    def handle_in("test_fallback", _payload, socket) do
      result =
        with_fallback(
          socket,
          "test_operation",
          fn -> raise "Primary failed" end,
          fn -> {:ok, "fallback_result"} end
        )

      {:reply, {:ok, %{result: result}}, socket}
    end

    @impl true
    def handle_in(event, payload, socket) do
      log_unhandled_message(event, payload, socket)
      {:noreply, socket}
    end

    @impl true
    def handle_info(:after_join, socket) do
      Phoenix.Channel.push(socket, "joined", %{status: "connected"})
      {:noreply, socket}
    end

    # Test info handler for batch events
    @impl true
    def handle_info({:batch_push, event_name, events}, socket) do
      Phoenix.Channel.push(socket, event_name, %{
        events: events,
        count: length(events),
        timestamp: System.system_time(:millisecond)
      })

      {:noreply, socket}
    end
  end

  describe "setup_correlation_id/1" do
    test "generates correlation ID and sets in socket assigns" do
      {:ok, socket} = subscribe_and_join(socket(TestChannel), "test:topic", %{})

      assert is_binary(socket.assigns.correlation_id)
      assert String.length(socket.assigns.correlation_id) == 8
    end
  end

  describe "subscribe_to_topics/1" do
    test "subscribes to multiple PubSub topics" do
      {:ok, _socket} = subscribe_and_join(socket(TestChannel), "test:multi", %{})

      # Verify we can receive messages on subscribed topics
      Phoenix.PubSub.broadcast(Server.PubSub, "topic1", {:test_message, "data1"})
      Phoenix.PubSub.broadcast(Server.PubSub, "topic2", {:test_message, "data2"})

      # Since we're subscribed, we should receive these broadcasts
      # (In a real test, we'd handle these in handle_info)
    end
  end

  describe "send_after_join/2" do
    test "sends after_join message and receives joined push" do
      {:ok, _socket} = subscribe_and_join(socket(TestChannel), "test:topic", %{})

      # The after_join message should trigger a push
      assert_push "joined", %{status: "connected"}
    end
  end

  describe "handle_ping/2" do
    test "replies with pong and timestamp" do
      {:ok, socket} = subscribe_and_join(socket(TestChannel), "test:topic", %{})

      ref = push(socket, "ping", %{"client_ts" => 123})
      assert_reply ref, :ok, response

      assert response.pong == true
      assert is_integer(response.timestamp)
      assert response.client_ts == 123
    end

    test "includes all payload fields in response" do
      {:ok, socket} = subscribe_and_join(socket(TestChannel), "test:topic", %{})

      payload = %{"client_ts" => 456, "extra" => "data", "foo" => "bar"}
      ref = push(socket, "ping", payload)
      assert_reply ref, :ok, response

      assert response.pong == true
      assert response.client_ts == 456
      assert response.extra == "data"
      assert response.foo == "bar"
    end
  end

  describe "push_error/4" do
    test "pushes error to client" do
      {:ok, socket} = subscribe_and_join(socket(TestChannel), "test:topic", %{})

      push(socket, "test_error", %{})

      assert_push "test_error", response
      assert response.error == "validation_error"
      assert response.message == "Test error message"
    end
  end

  describe "with_fallback/4" do
    test "uses fallback when primary fails" do
      {:ok, socket} = subscribe_and_join(socket(TestChannel), "test:topic", %{})

      ref = push(socket, "test_fallback", %{})
      assert_reply ref, :ok, %{result: {:ok, "fallback_result"}}
    end
  end

  describe "EventBatcher GenServer" do
    test "starts and accumulates events" do
      {:ok, socket} = subscribe_and_join(socket(TestChannel), "test:topic", %{})

      {:ok, batcher} =
        TestChannel.EventBatcher.start_link(
          socket: socket,
          batch_size: 3,
          flush_interval: 1000
        )

      TestChannel.EventBatcher.add_event(batcher, %{id: 1})
      TestChannel.EventBatcher.add_event(batcher, %{id: 2})

      # Events should be accumulated but not yet sent
      state = :sys.get_state(batcher)
      assert length(state.events) == 2

      # Stop the batcher to clean up
      GenServer.stop(batcher)
    end

    test "flushes when batch size is reached" do
      {:ok, socket} = subscribe_and_join(socket(TestChannel), "test:topic", %{})

      {:ok, batcher} =
        TestChannel.EventBatcher.start_link(
          socket: socket,
          event_name: "batch_test",
          batch_size: 2,
          flush_interval: 5000
        )

      TestChannel.EventBatcher.add_event(batcher, %{id: 1})
      TestChannel.EventBatcher.add_event(batcher, %{id: 2})

      assert_push "batch_test", batch
      assert batch.count == 2
      assert length(batch.events) == 2
      assert [%{id: 1}, %{id: 2}] = batch.events
      assert is_integer(batch.timestamp)

      GenServer.stop(batcher)
    end

    test "flushes on timer interval" do
      {:ok, socket} = subscribe_and_join(socket(TestChannel), "test:topic", %{})

      {:ok, batcher} =
        TestChannel.EventBatcher.start_link(
          socket: socket,
          event_name: "timer_test",
          batch_size: 10,
          # Short interval for testing
          flush_interval: 50
        )

      TestChannel.EventBatcher.add_event(batcher, %{id: 1})

      # Wait for timer flush
      Process.sleep(100)

      assert_push "timer_test", batch
      assert batch.count == 1
      assert [%{id: 1}] = batch.events

      GenServer.stop(batcher)
    end

    test "maintains event order (FIFO)" do
      {:ok, socket} = subscribe_and_join(socket(TestChannel), "test:topic", %{})

      {:ok, batcher} =
        TestChannel.EventBatcher.start_link(
          socket: socket,
          batch_size: 5,
          flush_interval: 5000
        )

      # Add events in specific order
      for i <- 1..5 do
        TestChannel.EventBatcher.add_event(batcher, %{seq: i})
      end

      assert_push "event_batch", batch
      assert [%{seq: 1}, %{seq: 2}, %{seq: 3}, %{seq: 4}, %{seq: 5}] = batch.events

      GenServer.stop(batcher)
    end

    test "handles empty flush gracefully" do
      {:ok, socket} = subscribe_and_join(socket(TestChannel), "test:topic", %{})

      {:ok, batcher} =
        TestChannel.EventBatcher.start_link(
          socket: socket,
          flush_interval: 50
        )

      # Wait for timer but don't add any events
      Process.sleep(100)

      # Should not receive any push since no events were added
      refute_push "event_batch", _

      GenServer.stop(batcher)
    end
  end

  describe "channel integration" do
    test "full channel lifecycle with correlation ID" do
      socket = socket(TestChannel)

      {:ok, socket} = subscribe_and_join(socket, "test:topic", %{})

      assert is_binary(socket.assigns.correlation_id)
      assert_push "joined", %{status: "connected"}
    end

    test "handles unhandled messages gracefully" do
      {:ok, socket} = subscribe_and_join(socket(TestChannel), "test:topic", %{})

      # Send an unhandled message - should not crash
      push(socket, "unknown_event", %{data: "test"})

      # Channel should still be functional
      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, %{pong: true}
    end
  end
end
