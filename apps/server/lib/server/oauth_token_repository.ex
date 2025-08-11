defmodule Server.OAuthTokenRepository do
  @moduledoc """
  Repository for OAuth token database operations.

  Provides a clean API for storing, retrieving, and managing OAuth tokens
  in PostgreSQL with automatic encryption/decryption.
  """

  import Ecto.Query
  alias Server.{OAuthAuditLog, OAuthToken, Repo}
  require Logger

  @doc """
  Gets a token for a specific service.
  """
  def get_token(service) when is_atom(service) do
    get_token(Atom.to_string(service))
  end

  def get_token(service) when is_binary(service) do
    case Repo.get_by(OAuthToken, service: service) do
      nil ->
        {:error, :not_found}

      token ->
        OAuthToken.decrypt(token)
    end
  end

  @doc """
  Saves or updates a token for a service.
  """
  def save_token(service, token_data) when is_atom(service) do
    save_token(Atom.to_string(service), token_data)
  end

  def save_token(service, token_data) when is_binary(service) do
    attrs = Map.merge(token_data, %{service: service})

    # Use transaction to ensure atomicity
    Repo.transaction(fn ->
      case Repo.get_by(OAuthToken, service: service) do
        nil ->
          %OAuthToken{}
          |> OAuthToken.changeset(attrs)
          |> Repo.insert!()

        existing ->
          existing
          |> OAuthToken.changeset(attrs)
          |> Repo.update!()
      end
    end)
  end

  @doc """
  Deletes a token for a service.
  """
  def delete_token(service) when is_atom(service) do
    delete_token(Atom.to_string(service))
  end

  def delete_token(service) when is_binary(service) do
    case Repo.get_by(OAuthToken, service: service) do
      nil ->
        {:error, :not_found}

      token ->
        Repo.delete(token)
    end
  end

  @doc """
  Gets all expired tokens.
  """
  def get_expired_tokens do
    now = DateTime.utc_now()

    query =
      from t in OAuthToken,
        where: not is_nil(t.expires_at) and t.expires_at < ^now

    Repo.all(query)
  end

  @doc """
  Gets tokens that will expire soon (within the given seconds).
  """
  def get_expiring_tokens(seconds_until_expiry \\ 300) do
    threshold = DateTime.add(DateTime.utc_now(), seconds_until_expiry, :second)

    query =
      from t in OAuthToken,
        where: not is_nil(t.expires_at) and t.expires_at < ^threshold

    Repo.all(query)
  end

  @doc """
  Migrates tokens from DETS to database.
  """
  def migrate_from_dets(dets_path \\ "./data/twitch_tokens.dets") do
    Logger.info("Starting OAuth token migration from DETS to PostgreSQL", path: dets_path)

    case read_dets_tokens(dets_path) do
      {:ok, token_data} ->
        Logger.info("Found tokens in DETS, migrating to database")

        result =
          save_token("twitch", %{
            access_token: token_data.access_token,
            refresh_token: token_data.refresh_token,
            expires_at: token_data.expires_at,
            scopes: if(token_data.scopes, do: MapSet.to_list(token_data.scopes), else: []),
            user_id: token_data.user_id,
            client_id: token_data.client_id
          })

        case result do
          {:ok, _token} ->
            Logger.info("Successfully migrated tokens to database")

            # Audit log the migration
            OAuthAuditLog.log_event(:migration_completed, %{
              service: "twitch",
              source: "DETS",
              destination: "PostgreSQL",
              user_id: token_data.user_id
            })

            # Optionally rename DETS file to indicate it's been migrated
            backup_path = dets_path <> ".migrated"
            File.rename(dets_path, backup_path)
            Logger.info("Renamed DETS file to indicate migration complete", backup: backup_path)
            {:ok, :migrated}

          {:error, reason} ->
            Logger.error("Failed to migrate tokens to database", error: inspect(reason))
            {:error, reason}
        end

      {:error, :no_tokens} ->
        Logger.info("No tokens found in DETS to migrate")
        {:ok, :no_tokens}

      {:error, reason} ->
        Logger.error("Failed to read DETS file", error: inspect(reason))
        {:error, reason}
    end
  end

  defp read_dets_tokens(dets_path) do
    dets_charlist = String.to_charlist(dets_path)

    case :dets.open_file(:temp_migration, file: dets_charlist) do
      {:ok, table} ->
        result =
          case :dets.lookup(table, :token) do
            [{:token, token_data}] when is_map(token_data) ->
              # Try to decrypt if encrypted
              decrypted =
                case Server.TokenVault.decrypt_token_map(token_data) do
                  {:ok, decrypted_map} -> decrypted_map
                  {:error, _} -> token_data
                end

              # Parse the data safely using Map.get
              token_info = %{
                access_token: Map.get(decrypted, :access_token) || Map.get(decrypted, "access_token"),
                refresh_token: Map.get(decrypted, :refresh_token) || Map.get(decrypted, "refresh_token"),
                expires_at: parse_datetime(Map.get(decrypted, :expires_at) || Map.get(decrypted, "expires_at")),
                scopes: parse_scopes(Map.get(decrypted, :scopes) || Map.get(decrypted, "scopes")),
                user_id: Map.get(decrypted, :user_id) || Map.get(decrypted, "user_id"),
                client_id: Map.get(decrypted, :client_id) || Map.get(decrypted, "client_id")
              }

              {:ok, token_info}

            [] ->
              {:error, :no_tokens}

            _ ->
              {:error, :invalid_format}
          end

        :dets.close(table)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(datetime), do: datetime

  defp parse_scopes(nil), do: nil
  defp parse_scopes(scopes) when is_list(scopes), do: MapSet.new(scopes)
  defp parse_scopes(%MapSet{} = scopes), do: scopes
  defp parse_scopes(_), do: nil
end
