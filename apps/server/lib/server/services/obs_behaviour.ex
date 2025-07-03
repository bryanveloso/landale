defmodule Server.Services.OBSBehaviour do
  @moduledoc """
  Behaviour for OBS service to enable mocking in tests.
  """

  @callback get_status() :: {:ok, map()} | {:error, term()}
  @callback get_stats() :: {:ok, map()} | {:error, term()}
  @callback get_version() :: {:ok, map()} | {:error, term()}
  @callback get_scene_list() :: {:ok, map()} | {:error, term()}
  @callback get_stream_status() :: {:ok, map()} | {:error, term()}
  @callback get_record_status() :: {:ok, map()} | {:error, term()}
  @callback get_virtual_cam_status() :: {:ok, map()} | {:error, term()}
  @callback get_output_list() :: {:ok, map()} | {:error, term()}
end
