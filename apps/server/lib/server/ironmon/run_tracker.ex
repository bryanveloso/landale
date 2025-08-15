defmodule Server.Ironmon.RunTracker do
  @moduledoc """
  Tracks the current IronMON run (seed) and provides run statistics.

  Uses the existing seeds/results schema:
  - Each seed is an attempt
  - Latest seed is the current/active attempt
  - Checkpoint results determine progress
  """

  use GenServer
  require Logger

  alias Server.Repo
  alias Server.Ironmon.{Checkpoint, Result, Seed}
  import Ecto.Query

  @name __MODULE__

  defstruct [:current_seed_id, :challenge_id]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc """
  Get the current seed (latest attempt).
  """
  def current_seed do
    GenServer.call(@name, :current_seed)
  end

  @doc """
  Get stats for the current run.
  """
  def current_stats do
    GenServer.call(@name, :current_stats)
  end

  @doc """
  Create a new seed (start a new attempt).
  """
  def new_seed(challenge_id, seed_count) do
    GenServer.call(@name, {:new_seed, challenge_id, seed_count})
  end

  @doc """
  Record a checkpoint result.
  """
  def record_checkpoint(checkpoint_name, passed) do
    GenServer.call(@name, {:record_checkpoint, checkpoint_name, passed})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Load the latest seed from DB
    state = load_current_seed()

    Logger.info("IronMON RunTracker started",
      service: :ironmon_run_tracker,
      current_seed_id: state.current_seed_id,
      challenge_id: state.challenge_id
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:current_seed, _from, state) do
    {:reply, state.current_seed_id, state}
  end

  @impl true
  def handle_call(:current_stats, _from, state) do
    stats =
      if state.current_seed_id do
        calculate_stats(state.current_seed_id)
      else
        %{seed_id: nil, checkpoints_cleared: 0, total_checkpoints: 0, last_checkpoint: nil}
      end

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:new_seed, challenge_id, seed_count}, _from, state) do
    case create_seed(challenge_id, seed_count) do
      {:ok, seed} ->
        new_state = %__MODULE__{
          current_seed_id: seed.id,
          challenge_id: challenge_id
        }

        Logger.info("New IronMON run started",
          seed_id: seed.id,
          challenge_id: challenge_id
        )

        # Broadcast new run event through unified system
        case Server.Events.process_event("ironmon.run_started", %{
               seed_id: seed.id,
               challenge_id: challenge_id
             }) do
          :ok -> Logger.debug("IronMON new run routed through unified system")
          {:error, reason} -> Logger.warning("Unified routing failed", reason: reason)
        end

        {:reply, {:ok, seed.id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:record_checkpoint, checkpoint_name, passed}, _from, state) do
    if state.current_seed_id do
      # Find checkpoint by name
      checkpoint = Repo.get_by(Checkpoint, name: checkpoint_name)

      if checkpoint do
        # Create or update result
        result_attrs = %{
          seed_id: state.current_seed_id,
          checkpoint_id: checkpoint.id,
          result: passed
        }

        _result =
          %Result{}
          |> Result.changeset(result_attrs)
          |> Repo.insert!(
            on_conflict: {:replace, [:result]},
            conflict_target: [:seed_id, :checkpoint_id]
          )

        Logger.debug("Checkpoint recorded",
          seed_id: state.current_seed_id,
          checkpoint: checkpoint_name,
          passed: passed
        )

        # Broadcast checkpoint event through unified system
        case Server.Events.process_event("ironmon.run_checkpoint", %{
               seed_id: state.current_seed_id,
               checkpoint: checkpoint_name,
               passed: passed
             }) do
          :ok -> Logger.debug("IronMON checkpoint routed through unified system")
          {:error, reason} -> Logger.warning("Unified routing failed", reason: reason)
        end

        {:reply, :ok, state}
      else
        {:reply, {:error, :checkpoint_not_found}, state}
      end
    else
      {:reply, {:error, :no_active_run}, state}
    end
  end

  # Private functions

  defp load_current_seed do
    # Get the latest seed
    seed =
      Seed
      |> order_by(desc: :id)
      |> limit(1)
      |> Repo.one()

    if seed do
      %__MODULE__{
        current_seed_id: seed.id,
        challenge_id: seed.challenge_id
      }
    else
      %__MODULE__{current_seed_id: nil, challenge_id: nil}
    end
  end

  defp create_seed(challenge_id, seed_count) do
    %Seed{}
    |> Seed.changeset(%{id: seed_count, challenge_id: challenge_id})
    |> Repo.insert()
  end

  defp calculate_stats(seed_id) do
    # Get all checkpoints for this seed's challenge
    seed = Repo.get!(Seed, seed_id)

    checkpoints =
      Checkpoint
      |> where(challenge_id: ^seed.challenge_id)
      |> order_by(:order)
      |> Repo.all()

    # Get results for this seed
    results =
      Result
      |> where(seed_id: ^seed_id)
      |> preload(:checkpoint)
      |> Repo.all()

    # Calculate stats
    passed_checkpoints = Enum.filter(results, & &1.result)

    last_checkpoint =
      passed_checkpoints
      |> Enum.max_by(& &1.checkpoint.order, fn -> nil end)

    %{
      seed_id: seed_id,
      checkpoints_cleared: length(passed_checkpoints),
      total_checkpoints: length(checkpoints),
      last_checkpoint: last_checkpoint && last_checkpoint.checkpoint.name,
      all_checkpoints_cleared: length(passed_checkpoints) == length(checkpoints)
    }
  end
end
