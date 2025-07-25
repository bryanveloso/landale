defmodule Server.Services.OBSBehaviour do
  @moduledoc """
  Behaviour definition for OBS service interface.

  This defines the public API that both the original monolithic OBS service
  and the new decomposed facade must implement, ensuring backward compatibility.
  """

  # Common service interface (duplicated from ServiceBehaviour)
  @callback start_link(opts :: keyword()) :: GenServer.on_start()
  @callback get_status() :: {:ok, map()} | {:error, term()}
  @callback get_health() :: {:ok, map()} | {:error, term()}
  @callback get_info() :: map()

  # OBS-specific methods
  @callback get_state() :: {:ok, map()} | {:error, term()}
  @callback get_stats() :: {:ok, map()} | {:error, term()}
  @callback get_version() :: {:ok, map()} | {:error, term()}

  # Scene management
  @callback set_current_scene(scene_name :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback set_preview_scene(scene_name :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_scene_list() :: {:ok, map()} | {:error, term()}
  @callback set_studio_mode_enabled(enabled :: boolean()) :: {:ok, map()} | {:error, term()}

  # Streaming and recording
  @callback start_streaming() :: {:ok, map()} | {:error, term()}
  @callback stop_streaming() :: {:ok, map()} | {:error, term()}
  @callback toggle_stream() :: {:ok, map()} | {:error, term()}
  @callback start_recording() :: {:ok, map()} | {:error, term()}
  @callback stop_recording() :: {:ok, map()} | {:error, term()}
  @callback pause_recording() :: {:ok, map()} | {:error, term()}
  @callback resume_recording() :: {:ok, map()} | {:error, term()}
  @callback toggle_record() :: {:ok, map()} | {:error, term()}
  @callback toggle_record_pause() :: {:ok, map()} | {:error, term()}

  # Input management
  @callback get_input_list(kind :: String.t() | nil) :: {:ok, map()} | {:error, term()}
  @callback refresh_browser_source(source_name :: String.t()) :: {:ok, map()} | {:error, term()}

  # Output management
  @callback get_output_list() :: {:ok, map()} | {:error, term()}
  @callback get_output_status(output_name :: String.t()) :: {:ok, map()} | {:error, term()}

  # Batch requests
  @callback send_batch_request(requests :: list(), options :: map()) :: {:ok, list()} | {:error, term()}
end
