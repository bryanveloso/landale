defmodule Server.StreamProducer.InterruptManager do
  @moduledoc """
  Manages priority-based interrupt queue for StreamProducer.

  Handles alerts, sub trains, and other priority content that interrupts
  the normal ticker rotation. Maintains a priority queue with automatic
  expiration and cleanup.
  """

  require Logger

  # Priority levels
  @priority_alert 100
  @priority_sub_train 50
  @priority_ticker 10

  @type interrupt_type :: :alert | :sub_train | :manual | :custom

  @type interrupt :: %{
          id: String.t(),
          type: interrupt_type(),
          priority: integer(),
          data: map(),
          expires_at: DateTime.t() | nil,
          created_at: DateTime.t()
        }

  @type t :: %{
          stack: [interrupt()],
          active: interrupt() | nil
        }

  @doc """
  Creates a new interrupt manager state.
  """
  @spec new() :: t()
  def new do
    %{
      stack: [],
      active: nil
    }
  end

  @doc """
  Adds an interrupt to the priority queue.

  Options:
  - `:priority` - Override default priority for the type
  - `:duration` - How long the interrupt should be active (ms)
  - `:expires_at` - Specific expiration time
  """
  @spec add_interrupt(t(), interrupt_type(), map(), keyword()) :: {t(), interrupt()}
  def add_interrupt(state, type, data, opts \\ []) do
    interrupt = %{
      id: generate_interrupt_id(type),
      type: type,
      priority: opts[:priority] || default_priority(type),
      data: data,
      expires_at: calculate_expiration(opts),
      created_at: DateTime.utc_now()
    }

    new_stack =
      [interrupt | state.stack]
      |> Enum.sort_by(& &1.priority, :desc)
      |> Enum.take(max_stack_size())

    new_state = %{state | stack: new_stack}

    # Check if this interrupt should become active
    new_state = maybe_activate_interrupt(new_state)

    {new_state, interrupt}
  end

  @doc """
  Removes an interrupt by ID.
  """
  @spec remove_interrupt(t(), String.t()) :: t()
  def remove_interrupt(state, interrupt_id) do
    new_stack = Enum.reject(state.stack, &(&1.id == interrupt_id))
    new_active = if state.active && state.active.id == interrupt_id, do: nil, else: state.active

    %{state | stack: new_stack, active: new_active}
    |> maybe_activate_interrupt()
  end

  @doc """
  Removes expired interrupts from the queue.
  """
  @spec cleanup_expired(t()) :: t()
  def cleanup_expired(state) do
    now = DateTime.utc_now()

    new_stack =
      Enum.filter(state.stack, fn interrupt ->
        interrupt.expires_at == nil || DateTime.compare(interrupt.expires_at, now) == :gt
      end)

    new_active =
      if state.active && state.active.expires_at && DateTime.compare(state.active.expires_at, now) == :lt do
        nil
      else
        state.active
      end

    %{state | stack: new_stack, active: new_active}
    |> maybe_activate_interrupt()
  end

  @doc """
  Gets the currently active interrupt.
  """
  @spec get_active(t()) :: interrupt() | nil
  def get_active(state), do: state.active

  @doc """
  Checks if there's an active interrupt.
  """
  @spec has_active?(t()) :: boolean()
  def has_active?(state), do: state.active != nil

  @doc """
  Gets the next interrupt in the queue (highest priority).
  """
  @spec get_next(t()) :: interrupt() | nil
  def get_next(state) do
    case state.stack do
      [next | _] -> next
      [] -> nil
    end
  end

  # Private functions

  defp maybe_activate_interrupt(state) do
    cond do
      # Already have active interrupt
      state.active != nil ->
        state

      # No interrupts in stack
      state.stack == [] ->
        state

      # Activate the highest priority interrupt
      true ->
        [next | rest] = state.stack
        %{state | active: next, stack: rest}
    end
  end

  defp default_priority(:alert), do: @priority_alert
  defp default_priority(:sub_train), do: @priority_sub_train
  defp default_priority(:manual), do: @priority_alert
  defp default_priority(_), do: @priority_ticker

  defp calculate_expiration(opts) do
    cond do
      opts[:expires_at] ->
        opts[:expires_at]

      opts[:duration] ->
        DateTime.add(DateTime.utc_now(), opts[:duration], :millisecond)

      true ->
        nil
    end
  end

  defp generate_interrupt_id(type) do
    "#{type}_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp max_stack_size do
    Application.get_env(:server, :max_interrupt_stack_size, 50)
  end
end
