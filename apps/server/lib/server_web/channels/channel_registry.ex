defmodule ServerWeb.ChannelRegistry do
  @moduledoc """
  Runtime registry and introspection system for Phoenix channels.

  Provides self-documenting capabilities by extracting channel information,
  available commands, and message schemas from running code.

  ## Features

  - Auto-discovery of all Phoenix channels
  - Runtime extraction of handle_in/3 functions (commands)
  - Runtime extraction of handle_info/2 functions (events)
  - Message schema generation
  - Command usage examples

  ## Usage

      # Get all available channels
      channels = ChannelRegistry.list_channels()
      
      # Get specific channel info
      {:ok, info} = ChannelRegistry.get_channel_info(ServerWeb.OverlayChannel)
      
      # Get WebSocket API schema
      schema = ChannelRegistry.generate_websocket_schema()
  """

  require Logger

  @type channel_info :: %{
          module: module(),
          topic_pattern: binary(),
          description: binary(),
          commands: [command_info()],
          events: [event_info()],
          examples: [example()]
        }

  @type command_info :: %{
          name: binary(),
          arity: integer(),
          description: binary(),
          payload_schema: map(),
          response_schema: map()
        }

  @type event_info :: %{
          name: binary(),
          pattern: binary(),
          description: binary(),
          payload_schema: map()
        }

  @type example :: %{
          command: binary(),
          payload: map(),
          description: binary()
        }

  # Cache the computed channels in a module attribute at compile time
  @cached_channels :code.all_loaded()
                   |> Enum.map(&elem(&1, 0))
                   |> Enum.filter(fn module ->
                     try do
                       case module.__info__(:attributes) do
                         attributes when is_list(attributes) ->
                           # Check if module uses Phoenix.Channel behavior
                           behaviours = Keyword.get_values(attributes, :behaviour)
                           Phoenix.Channel in behaviours

                         _ ->
                           false
                       end
                     rescue
                       _ -> false
                     end
                   end)
                   |> Enum.sort()

  @doc """
  Lists all available Phoenix channels in the application.

  Uses runtime introspection to find all modules that implement Phoenix.Channel.
  Cached at application startup to avoid runtime overhead.
  """
  @spec list_channels() :: [module()]
  def list_channels do
    @cached_channels
  end

  @doc """
  Gets detailed information about a specific channel.

  Extracts commands, events, and metadata from the channel module.
  """
  @spec get_channel_info(module()) :: {:ok, channel_info()} | {:error, term()}
  def get_channel_info(channel_module) do
    if channel_module?(channel_module) do
      info = %{
        module: channel_module,
        topic_pattern: get_topic_pattern(channel_module),
        description: get_module_doc(channel_module),
        commands: extract_commands(channel_module),
        events: extract_events(channel_module),
        examples: get_command_examples(channel_module)
      }

      {:ok, info}
    else
      {:error, :not_a_channel_module}
    end
  end

  @doc """
  Generates a complete WebSocket API schema.

  Returns a structured map containing all channels, commands, events,
  and examples suitable for API documentation or client generation.
  """
  @spec generate_websocket_schema() :: map()
  def generate_websocket_schema do
    channels = list_channels()

    channel_schemas =
      channels
      |> Enum.map(fn module ->
        {:ok, info} = get_channel_info(module)
        {module, info}
      end)
      |> Map.new()

    %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      websocket_endpoint: "/socket/websocket",
      channels: channel_schemas,
      connection_info: %{
        url: "ws://localhost:7175/socket/websocket",
        transport: "websocket",
        protocol: "phoenix_channels"
      },
      message_format: %{
        outgoing: %{
          topic: "string",
          event: "string",
          payload: "object",
          ref: "string"
        },
        incoming: %{
          topic: "string",
          event: "string",
          payload: "object",
          ref: "string"
        }
      }
    }
  end

  # Private helper functions

  defp channel_module?(module) do
    try do
      case module.__info__(:attributes) do
        attributes when is_list(attributes) ->
          # Check if module uses Phoenix.Channel behavior
          behaviours = Keyword.get_values(attributes, :behaviour)
          Phoenix.Channel in behaviours

        _ ->
          false
      end
    rescue
      _ -> false
    end
  end

  defp get_topic_pattern(channel_module) do
    # Try to extract topic pattern from module attributes
    case get_module_attribute(channel_module, :topic_pattern) do
      nil ->
        # Fallback: infer from module name
        module_name = module_to_string(channel_module)
        String.downcase(String.replace(module_name, ~r/Channel$/, "")) <> ":*"

      pattern ->
        pattern
    end
  end

  defp get_module_doc(channel_module) do
    case Code.fetch_docs(channel_module) do
      {:docs_v1, _, :elixir, _, %{"en" => module_doc}, _, _} ->
        module_doc

      _ ->
        "No documentation available"
    end
  end

  defp extract_commands(channel_module) do
    channel_module.__info__(:functions)
    |> Enum.filter(fn {function_name, arity} ->
      # Look for handle_in/3 functions
      function_name == :handle_in and arity == 3
    end)
    |> Enum.map(fn {function_name, arity} ->
      %{
        name: Atom.to_string(function_name),
        arity: arity,
        description: get_function_doc(channel_module, function_name, arity),
        payload_schema: %{type: "object", description: "Command payload"},
        response_schema: %{type: "object", description: "Command response"}
      }
    end)
  end

  defp extract_events(channel_module) do
    channel_module.__info__(:functions)
    |> Enum.filter(fn {function_name, arity} ->
      # Look for handle_info/2 functions
      function_name == :handle_info and arity == 2
    end)
    |> Enum.map(fn {function_name, arity} ->
      %{
        name: Atom.to_string(function_name),
        pattern: "handle_info/2",
        description: get_function_doc(channel_module, function_name, arity),
        payload_schema: %{type: "object", description: "Event payload"}
      }
    end)
  end

  defp get_command_examples(channel_module) do
    # Try to get examples from module attributes
    case get_module_attribute(channel_module, :channel_examples) do
      nil -> []
      examples when is_list(examples) -> examples
      _ -> []
    end
  end

  defp get_module_attribute(module, attribute_name) do
    try do
      case module.__info__(:attributes) do
        attributes when is_list(attributes) ->
          case Keyword.get(attributes, attribute_name) do
            [value] -> value
            _ -> nil
          end

        _ ->
          nil
      end
    rescue
      _ -> nil
    end
  end

  defp get_function_doc(module, function_name, arity) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, :elixir, _, _, _, function_docs} ->
        case Enum.find(function_docs, fn {{type, name, a}, _, _, _, _} ->
               type == :function and name == function_name and a == arity
             end) do
          {_, _, _, %{"en" => doc}, _} -> doc
          _ -> "No documentation available"
        end

      _ ->
        "No documentation available"
    end
  end

  defp module_to_string(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
  end
end
