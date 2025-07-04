defmodule Server.Ironmon do
  @moduledoc """
  The Ironmon context for managing Pokemon IronMON challenges and results.
  """

  import Ecto.Query, warn: false
  alias Server.Repo
  alias Server.Ironmon.{Challenge, Checkpoint, Result, Seed}

  @typedoc "Statistics for a checkpoint"
  @type checkpoint_stats :: %{
          wins: integer(),
          losses: integer(),
          total: integer(),
          win_rate: float()
        }

  @typedoc "Recent result with joined data"
  @type recent_result :: %{
          id: integer(),
          seed_id: integer(),
          checkpoint_name: String.t(),
          trainer: String.t(),
          challenge_name: String.t(),
          result: boolean()
        }

  @typedoc "Active challenge information"
  @type active_challenge :: %{
          seed_id: integer(),
          challenge_name: String.t(),
          completed_checkpoints: integer(),
          last_result: boolean() | nil
        }

  ## Challenges

  @doc """
  Lists all challenges in the database.

  ## Returns
  - List of `Challenge` structs
  """
  @spec list_challenges() :: [Challenge.t()]
  def list_challenges do
    Repo.all(Challenge)
  end

  @doc """
  Gets a challenge by ID, raising if not found.

  ## Parameters
  - `id` - The challenge ID

  ## Returns
  - `Challenge` struct

  ## Raises
  - `Ecto.NoResultsError` if challenge not found
  """
  @spec get_challenge!(integer()) :: Challenge.t()
  def get_challenge!(id), do: Repo.get!(Challenge, id)

  @doc """
  Gets a challenge by name.

  ## Parameters
  - `name` - The challenge name

  ## Returns
  - `Challenge` struct or `nil` if not found
  """
  @spec get_challenge_by_name(String.t()) :: Challenge.t() | nil
  def get_challenge_by_name(name) do
    Repo.get_by(Challenge, name: name)
  end

  @doc """
  Creates a new challenge.

  ## Parameters
  - `attrs` - Map of challenge attributes (optional)

  ## Returns
  - `{:ok, challenge}` on success
  - `{:error, changeset}` on validation error
  """
  @spec create_challenge(map()) :: {:ok, Challenge.t()} | {:error, Ecto.Changeset.t()}
  def create_challenge(attrs \\ %{}) do
    %Challenge{}
    |> Challenge.changeset(attrs)
    |> Repo.insert()
  end

  ## Checkpoints

  @doc """
  Lists all checkpoints for a specific challenge, ordered by order field.

  ## Parameters
  - `challenge_id` - The ID of the challenge

  ## Returns
  - List of `Checkpoint` structs ordered by order field
  """
  @spec list_checkpoints_for_challenge(integer()) :: [Checkpoint.t()]
  def list_checkpoints_for_challenge(challenge_id) do
    from(c in Checkpoint,
      where: c.challenge_id == ^challenge_id,
      order_by: [asc: c.order]
    )
    |> Repo.all()
  end

  @doc """
  Gets a checkpoint by ID, raising if not found.

  ## Parameters
  - `id` - The checkpoint ID

  ## Returns
  - `Checkpoint` struct

  ## Raises
  - `Ecto.NoResultsError` if checkpoint not found
  """
  @spec get_checkpoint!(integer()) :: Checkpoint.t()
  def get_checkpoint!(id), do: Repo.get!(Checkpoint, id)

  @doc """
  Creates a new checkpoint.

  ## Parameters
  - `attrs` - Map of checkpoint attributes (optional)

  ## Returns
  - `{:ok, checkpoint}` on success
  - `{:error, changeset}` on validation error
  """
  @spec create_checkpoint(map()) :: {:ok, Checkpoint.t()} | {:error, Ecto.Changeset.t()}
  def create_checkpoint(attrs \\ %{}) do
    %Checkpoint{}
    |> Checkpoint.changeset(attrs)
    |> Repo.insert()
  end

  ## Seeds

  @doc """
  Lists all seeds for a specific challenge.

  ## Parameters
  - `challenge_id` - The ID of the challenge

  ## Returns
  - List of `Seed` structs
  """
  @spec list_seeds_for_challenge(integer()) :: [Seed.t()]
  def list_seeds_for_challenge(challenge_id) do
    from(s in Seed,
      where: s.challenge_id == ^challenge_id
    )
    |> Repo.all()
  end

  @doc """
  Gets a seed by ID, raising if not found.

  ## Parameters
  - `id` - The seed ID

  ## Returns
  - `Seed` struct

  ## Raises
  - `Ecto.NoResultsError` if seed not found
  """
  @spec get_seed!(integer()) :: Seed.t()
  def get_seed!(id), do: Repo.get!(Seed, id)

  @doc """
  Creates a new seed.

  ## Parameters
  - `attrs` - Map of seed attributes (optional)

  ## Returns
  - `{:ok, seed}` on success
  - `{:error, changeset}` on validation error
  """
  @spec create_seed(map()) :: {:ok, Seed.t()} | {:error, Ecto.Changeset.t()}
  def create_seed(attrs \\ %{}) do
    %Seed{}
    |> Seed.changeset(attrs)
    |> Repo.insert()
  end

  ## Results

  @doc """
  Gets a result for a specific seed and checkpoint combination.

  ## Parameters
  - `seed_id` - The ID of the seed
  - `checkpoint_id` - The ID of the checkpoint

  ## Returns
  - `Result` struct or `nil` if not found
  """
  @spec get_result(integer(), integer()) :: Result.t() | nil
  def get_result(seed_id, checkpoint_id) do
    Repo.get_by(Result, seed_id: seed_id, checkpoint_id: checkpoint_id)
  end

  @doc """
  Creates a new result or updates an existing one.

  ## Parameters
  - `seed_id` - The ID of the seed
  - `checkpoint_id` - The ID of the checkpoint
  - `result_value` - The result value (boolean)

  ## Returns
  - `{:ok, result}` on success
  - `{:error, changeset}` on validation error
  """
  @spec create_or_update_result(integer(), integer(), boolean()) :: {:ok, Result.t()} | {:error, Ecto.Changeset.t()}
  def create_or_update_result(seed_id, checkpoint_id, result_value) do
    case get_result(seed_id, checkpoint_id) do
      nil ->
        %Result{}
        |> Result.changeset(%{
          seed_id: seed_id,
          checkpoint_id: checkpoint_id,
          result: result_value
        })
        |> Repo.insert()

      existing_result ->
        existing_result
        |> Result.changeset(%{result: result_value})
        |> Repo.update()
    end
  end

  ## Statistics

  @doc """
  Gets statistics for a specific checkpoint.

  ## Parameters
  - `checkpoint_id` - The ID of the checkpoint

  ## Returns
  - Map containing wins, losses, total, and win_rate
  """
  @spec get_checkpoint_stats(integer()) :: checkpoint_stats()
  def get_checkpoint_stats(checkpoint_id) do
    from(r in Result,
      where: r.checkpoint_id == ^checkpoint_id,
      group_by: r.result,
      select: {r.result, count(r.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})
    |> then(fn stats ->
      wins = Map.get(stats, true, 0)
      losses = Map.get(stats, false, 0)
      total = wins + losses

      %{
        wins: wins,
        losses: losses,
        total: total,
        win_rate: if(total > 0, do: wins / total, else: 0.0)
      }
    end)
  end

  @doc """
  Gets recent results with pagination support.

  ## Parameters
  - `limit` - Maximum number of results to return (default: 10)
  - `cursor` - ID to start pagination from (optional)

  ## Returns
  - List of result maps with joined challenge/checkpoint data
  """
  @spec get_recent_results(integer(), integer() | nil) :: [recent_result()]
  def get_recent_results(limit \\ 10, cursor \\ nil) do
    query =
      from(r in Result,
        join: s in Seed,
        on: r.seed_id == s.id,
        join: c in Checkpoint,
        on: r.checkpoint_id == c.id,
        join: ch in Challenge,
        on: s.challenge_id == ch.id,
        select: %{
          id: r.id,
          seed_id: s.id,
          checkpoint_name: c.name,
          trainer: c.trainer,
          challenge_name: ch.name,
          result: r.result
        },
        order_by: [desc: r.id],
        limit: ^limit
      )

    query =
      if cursor do
        from(q in query, where: q.id < ^cursor)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets active challenge information for a specific seed.

  ## Parameters
  - `seed_id` - The ID of the seed

  ## Returns
  - `{:ok, challenge_info}` if found
  - `{:error, message}` if not found
  """
  @spec get_active_challenge(integer()) :: {:ok, active_challenge()} | {:error, String.t()}
  def get_active_challenge(seed_id) do
    case from(s in Seed,
           join: ch in Challenge,
           on: s.challenge_id == ch.id,
           left_join: r in Result,
           on: r.seed_id == s.id,
           left_join: c in Checkpoint,
           on: r.checkpoint_id == c.id,
           where: s.id == ^seed_id,
           select: %{
             seed_id: s.id,
             challenge_name: ch.name,
             completed_checkpoints: count(r.id, :distinct),
             last_result: fragment("bool_or(?)", r.result)
           },
           group_by: [s.id, ch.name]
         )
         |> Repo.one() do
      nil -> {:error, "No active challenge found"}
      challenge -> {:ok, challenge}
    end
  end
end
