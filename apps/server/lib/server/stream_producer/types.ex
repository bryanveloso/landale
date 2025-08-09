defmodule Server.StreamProducer.Types do
  @moduledoc """
  Type definitions for StreamProducer and related modules.

  Centralizes type specifications for better code clarity and reusability.
  """

  @type show_type :: :ironmon | :variety | :coding | :custom

  @type interrupt_type :: :alert | :sub_train | :manual | :raid | :custom

  @type priority_level :: 1..100

  @type content_type ::
          :ticker
          | :alert
          | :sub_train
          | :follow_train
          | :raid
          | :checkpoint
          | :goal
          | :custom

  @type ticker_content :: %{
          type: atom(),
          data: map(),
          weight: pos_integer()
        }

  @type interrupt :: %{
          id: String.t(),
          type: interrupt_type(),
          priority: priority_level(),
          data: map(),
          duration: pos_integer(),
          started_at: DateTime.t()
        }

  @type active_content :: %{
          type: content_type(),
          data: map(),
          source: :interrupt | :ticker | :manual,
          priority: priority_level(),
          started_at: DateTime.t()
        }

  @type stream_metadata :: %{
          last_updated: DateTime.t() | nil,
          state_version: non_neg_integer(),
          show_started_at: DateTime.t() | nil,
          game_id: String.t() | nil,
          game_name: String.t() | nil
        }

  @type state :: %{
          current_show: show_type(),
          active_content: active_content() | nil,
          interrupt_stack: [interrupt()],
          ticker_rotation: [ticker_content()],
          ticker_index: non_neg_integer(),
          timers: %{String.t() => reference()},
          version: non_neg_integer(),
          metadata: stream_metadata()
        }
end
