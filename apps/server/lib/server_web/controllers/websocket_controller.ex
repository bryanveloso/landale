defmodule ServerWeb.WebSocketController do
  @moduledoc """
  HTTP endpoints for WebSocket API introspection and documentation.

  Provides machine-readable schema and examples for all available WebSocket channels,
  commands, and events. Enables self-documenting WebSocket APIs that never go stale.
  """

  use ServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias ServerWeb.{ChannelRegistry, Schemas}

  operation(:schema,
    summary: "Get WebSocket API schema",
    description: "Returns complete WebSocket API documentation including all channels, commands, events, and examples",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse}
    }
  )

  def schema(conn, _params) do
    schema = ChannelRegistry.generate_websocket_schema()
    json(conn, %{success: true, data: schema})
  end

  operation(:channels,
    summary: "List available WebSocket channels",
    description: "Returns a list of all available Phoenix channels with their topic patterns",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse}
    }
  )

  def channels(conn, _params) do
    channels = ChannelRegistry.list_channels()

    channel_info =
      channels
      |> Enum.map(fn channel_module ->
        {:ok, info} = ChannelRegistry.get_channel_info(channel_module)

        %{
          module: Atom.to_string(info.module),
          topic_pattern: info.topic_pattern,
          description: info.description,
          command_count: length(info.commands),
          event_count: length(info.events)
        }
      end)

    json(conn, %{success: true, data: channel_info})
  end

  operation(:channel_details,
    summary: "Get detailed channel information",
    description: "Returns complete information about a specific WebSocket channel including all commands and events",
    parameters: [
      module: [
        in: :path,
        description: "Channel module name (e.g., 'ServerWeb.OverlayChannel')",
        type: :string,
        example: "ServerWeb.OverlayChannel"
      ]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      404 => {"Channel not found", "application/json", Schemas.ErrorResponse}
    }
  )

  def channel_details(conn, %{"module" => module_string}) do
    try do
      channel_module = String.to_existing_atom(module_string)

      case ChannelRegistry.get_channel_info(channel_module) do
        {:ok, info} ->
          # Convert module atoms to strings for JSON serialization
          serializable_info = %{
            module: Atom.to_string(info.module),
            topic_pattern: info.topic_pattern,
            description: info.description,
            commands: info.commands,
            events: info.events,
            examples: info.examples
          }

          json(conn, %{success: true, data: serializable_info})

        {:error, :not_a_channel_module} ->
          conn
          |> put_status(:not_found)
          |> json(%{success: false, error: %{message: "Module is not a Phoenix channel"}})
      end
    rescue
      ArgumentError ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: %{message: "Module not found"}})
    end
  end

  operation(:examples,
    summary: "Get WebSocket usage examples",
    description: "Returns practical WebSocket client examples for all channels and commands",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse}
    }
  )

  def examples(conn, _params) do
    examples = %{
      connection: %{
        javascript: %{
          description: "Connect using Phoenix JavaScript client",
          code: """
          import {Socket} from "phoenix"

          const socket = new Socket("/socket", {
            params: {},
            logger: (kind, msg, data) => console.log(`${kind}: ${msg}`, data)
          })

          socket.connect()
          """
        },
        websocat: %{
          description: "Connect using websocat CLI tool",
          code: """
          # Connect to WebSocket
          websocat ws://localhost:7175/socket/websocket

          # Join a channel (send this JSON message)
          ["1","1","overlay:obs","phx_join",{}]

          # Send a command
          ["2","2","overlay:obs","obs:status",{}]
          """
        }
      },
      channels: generate_channel_examples(),
      message_format: %{
        description: "Phoenix channels use a specific message format",
        outgoing: %{
          format: "[ref, join_ref, topic, event, payload]",
          example: ["1", "1", "overlay:obs", "obs:status", %{}]
        },
        incoming: %{
          format: "[ref, join_ref, topic, event, payload]",
          reply_example: ["1", "1", "overlay:obs", "phx_reply", %{status: "ok", response: %{}}],
          event_example: ["null", "1", "overlay:obs", "obs_event", %{type: "streaming_started"}]
        }
      }
    }

    json(conn, %{success: true, data: examples})
  end

  # Private helper functions

  defp generate_channel_examples do
    channels = ChannelRegistry.list_channels()

    channels
    |> Enum.map(fn channel_module ->
      {:ok, info} = ChannelRegistry.get_channel_info(channel_module)

      {info.module,
       %{
         topic_pattern: info.topic_pattern,
         description: info.description,
         join_example: %{
           description: "Join this channel",
           message: ["1", "1", String.replace(info.topic_pattern, "*", "obs"), "phx_join", %{}]
         },
         command_examples: info.examples
       }}
    end)
    |> Map.new(fn {module, data} -> {Atom.to_string(module), data} end)
  end
end
