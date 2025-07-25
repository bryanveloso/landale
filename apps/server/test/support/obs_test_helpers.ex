defmodule Server.OBSTestHelpers do
  @moduledoc """
  Common test helpers and factories for OBS WebSocket testing.

  Provides message factories, state builders, and mock utilities
  for testing the OBS service modules.
  """

  @doc """
  Creates a hello message from OBS WebSocket server.
  """
  def hello_message(rpc_version \\ "1", auth_required \\ false) do
    %{
      "op" => 0,
      "d" => %{
        "obsWebSocketVersion" => "5.1.0",
        "rpcVersion" => rpc_version,
        "authentication" =>
          if(auth_required,
            do: %{
              "challenge" => "test_challenge",
              "salt" => "test_salt"
            },
            else: nil
          )
      }
    }
  end

  @doc """
  Creates an identified message indicating successful connection.
  """
  def identified_message(negotiated_version \\ "1") do
    %{
      "op" => 2,
      "d" => %{
        "negotiatedRpcVersion" => negotiated_version
      }
    }
  end

  @doc """
  Creates an event message with the specified type and data.
  """
  def event_message(event_type, event_data, metadata \\ %{}) do
    %{
      "op" => 5,
      "d" => %{
        "eventType" => event_type,
        "eventIntent" => determine_intent(event_type),
        "eventData" => event_data
      }
    }
    |> maybe_add_metadata(metadata)
  end

  @doc """
  Creates a request response message.
  """
  def request_response_message(request_id, status \\ "success", data \\ %{}) do
    base = %{
      "op" => 7,
      "d" => %{
        "requestType" => "TestRequest",
        "requestId" => request_id,
        "requestStatus" => %{
          "result" => status == "success",
          "code" => if(status == "success", do: 100, else: 501),
          "comment" => status
        }
      }
    }

    if status == "success" do
      put_in(base, ["d", "responseData"], data)
    else
      base
    end
  end

  @doc """
  Creates a scene state for testing SceneManager.
  """
  def scene_state(scenes \\ ["Scene 1", "Scene 2"], current \\ "Scene 1") do
    %{
      scene_list: Enum.map(scenes, &scene_item/1),
      current_scene: current,
      preview_scene: nil,
      studio_mode: false
    }
  end

  @doc """
  Creates a scene item structure.
  """
  def scene_item(name) do
    %{
      "sceneName" => name,
      "sceneIndex" => :rand.uniform(100),
      "sceneUuid" => UUID.uuid4()
    }
  end

  @doc """
  Creates a stream state for testing StreamManager.
  """
  def stream_state(opts \\ []) do
    %{
      streaming_active: Keyword.get(opts, :streaming_active, false),
      streaming_timecode: Keyword.get(opts, :streaming_timecode, "00:00:00.000"),
      streaming_duration: Keyword.get(opts, :streaming_duration, 0),
      streaming_congestion: Keyword.get(opts, :streaming_congestion, 0.0),
      streaming_bytes: Keyword.get(opts, :streaming_bytes, 0),
      streaming_skipped_frames: Keyword.get(opts, :streaming_skipped_frames, 0),
      streaming_total_frames: Keyword.get(opts, :streaming_total_frames, 0),
      recording_active: Keyword.get(opts, :recording_active, false),
      recording_paused: Keyword.get(opts, :recording_paused, false),
      recording_timecode: Keyword.get(opts, :recording_timecode, "00:00:00.000"),
      recording_duration: Keyword.get(opts, :recording_duration, 0),
      recording_bytes: Keyword.get(opts, :recording_bytes, 0),
      virtual_cam_active: Keyword.get(opts, :virtual_cam_active, false)
    }
  end

  @doc """
  Creates a mock WebSocket connection process.
  """
  def mock_websocket_connection do
    parent = self()

    spawn(fn ->
      receive do
        {:gun_ws, _conn, _stream, {:text, message}} ->
          send(parent, {:websocket_message, message})

        {:gun_ws, _conn, _stream, :close} ->
          send(parent, :websocket_closed)

        {:gun_down, _conn, _protocol, _reason, _streams} ->
          send(parent, :connection_down)
      end
    end)
  end

  @doc """
  Creates a connection state for testing.
  """
  def connection_state(state \\ :ready, opts \\ []) do
    %{
      state: state,
      conn: Keyword.get(opts, :conn),
      stream: Keyword.get(opts, :stream),
      session_id: Keyword.get(opts, :session_id, "test_session"),
      rpc_version: Keyword.get(opts, :rpc_version, "1"),
      reconnect_attempts: Keyword.get(opts, :reconnect_attempts, 0),
      requests: Keyword.get(opts, :requests, %{})
    }
  end

  @doc """
  Creates a request tracking entry.
  """
  def tracked_request(request_id, request_type, from \\ nil) do
    %{
      id: request_id,
      type: request_type,
      from: from || {self(), make_ref()},
      timestamp: System.system_time(:millisecond),
      timeout_ref: make_ref()
    }
  end

  @doc """
  Simulates OBS event sequences for testing.
  """
  def simulate_event_sequence(events) do
    Enum.map(events, fn {type, data} ->
      event_message(type, data)
    end)
  end

  @doc """
  Creates a stats collector state.
  """
  def stats_state(opts \\ []) do
    %{
      connection_attempts: Keyword.get(opts, :connection_attempts, 0),
      successful_connections: Keyword.get(opts, :successful_connections, 0),
      failed_connections: Keyword.get(opts, :failed_connections, 0),
      messages_sent: Keyword.get(opts, :messages_sent, 0),
      messages_received: Keyword.get(opts, :messages_received, 0),
      events_processed: Keyword.get(opts, :events_processed, 0),
      requests_sent: Keyword.get(opts, :requests_sent, 0),
      requests_completed: Keyword.get(opts, :requests_completed, 0),
      requests_failed: Keyword.get(opts, :requests_failed, 0),
      last_error: Keyword.get(opts, :last_error),
      started_at: Keyword.get(opts, :started_at, System.system_time(:second))
    }
  end

  # Private helpers

  defp determine_intent(event_type) do
    cond do
      String.starts_with?(event_type, "Scene") -> 1
      String.starts_with?(event_type, "Input") -> 2
      String.starts_with?(event_type, "Stream") -> 32
      String.starts_with?(event_type, "Record") -> 64
      true -> 0
    end
  end

  defp maybe_add_metadata(message, metadata) when map_size(metadata) > 0 do
    update_in(message, ["d"], &Map.merge(&1, metadata))
  end

  defp maybe_add_metadata(message, _), do: message
end
