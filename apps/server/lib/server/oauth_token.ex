defmodule Server.OAuthToken do
  @moduledoc """
  Ecto schema for OAuth tokens stored in PostgreSQL.

  Provides database-backed token storage with encryption support.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Server.TokenVault

  schema "oauth_tokens" do
    field :service, :string
    field :access_token, :string
    field :refresh_token, :string
    field :expires_at, :utc_datetime
    field :scopes, {:array, :string}, default: []
    field :user_id, :string
    field :client_id, :string
    field :encrypted, :boolean, default: true

    timestamps()
  end

  @doc """
  Creates a changeset for an OAuth token.
  """
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:service, :access_token, :refresh_token, :expires_at, :scopes, :user_id, :client_id, :encrypted])
    |> validate_required([:service, :access_token])
    |> unique_constraint(:service)
    |> encrypt_tokens()
  end

  # Encrypts sensitive token fields before saving to database
  defp encrypt_tokens(changeset) do
    case get_change(changeset, :encrypted) do
      false ->
        changeset

      _ ->
        changeset
        |> encrypt_field(:access_token)
        |> encrypt_field(:refresh_token)
    end
  end

  defp encrypt_field(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      value ->
        case TokenVault.encrypt(value) do
          {:ok, encrypted} ->
            put_change(changeset, field, encrypted)

          {:error, reason} ->
            # CRITICAL: Never store unencrypted tokens - fail fast
            add_error(changeset, field, "encryption failed: #{inspect(reason)}")
        end
    end
  end

  @doc """
  Decrypts token fields after loading from database.
  """
  def decrypt(%__MODULE__{encrypted: false} = token), do: {:ok, token}

  def decrypt(%__MODULE__{encrypted: true} = token) do
    with {:ok, access_token} <- TokenVault.decrypt(token.access_token),
         {:ok, refresh_token} <- decrypt_optional_field(token.refresh_token) do
      {:ok, %{token | access_token: access_token, refresh_token: refresh_token}}
    else
      {:error, reason} ->
        {:error, {:decryption_failed, reason}}
    end
  end

  # Handle optional fields that might be nil
  defp decrypt_optional_field(nil), do: {:ok, nil}
  defp decrypt_optional_field(value), do: TokenVault.decrypt(value)
end
