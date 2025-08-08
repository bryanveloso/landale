defmodule Server.TokenVault do
  @moduledoc """
  Secure token encryption vault using AES-256-GCM via Cloak.

  Provides encryption and decryption for OAuth tokens and other sensitive data.
  Implements the security standards mandated for the Landale project.

  ## Security Features
  - AES-256-GCM encryption (authenticated encryption)
  - Environment-based key management
  - Automatic key rotation support
  - Safe error handling (never logs plaintext)

  ## Usage

      # Encrypt a token
      {:ok, encrypted} = Server.TokenVault.encrypt("sensitive_token")

      # Decrypt a token
      {:ok, plaintext} = Server.TokenVault.decrypt(encrypted)

  ## Configuration

  Set the encryption key in your environment:

      export LANDALE_ENCRYPTION_KEY="your-base64-encoded-256-bit-key"

  Generate a key:

      mix phx.gen.secret 64
  """

  use Cloak.Vault, otp_app: :server

  @impl GenServer
  def init(config) do
    # Get encryption key from environment
    config =
      Keyword.put(
        config,
        :ciphers,
        default: {
          Cloak.Ciphers.AES.GCM,
          tag: "AES.GCM.V1", key: decode_key(System.get_env("LANDALE_ENCRYPTION_KEY")), iv_length: 12
        }
      )

    {:ok, config}
  end

  @doc """
  Encrypts a string value using AES-256-GCM.

  ## Parameters
  - `plaintext` - The string to encrypt

  ## Returns
  - `{:ok, encrypted}` - Base64-encoded encrypted value
  - `{:error, reason}` - Encryption failed
  """
  @spec encrypt(String.t()) :: {:ok, String.t()} | {:error, term()}
  def encrypt(plaintext) when is_binary(plaintext) do
    try do
      # Use Cloak's encrypt method directly on our vault module
      encrypted = __MODULE__.encrypt!(plaintext)
      {:ok, Base.encode64(encrypted)}
    rescue
      error ->
        {:error, {:encryption_error, error}}
    end
  end

  def encrypt(nil), do: {:ok, nil}
  def encrypt(_), do: {:error, :invalid_input}

  @doc """
  Decrypts a Base64-encoded encrypted value.

  ## Parameters
  - `encrypted` - Base64-encoded encrypted string

  ## Returns
  - `{:ok, plaintext}` - Decrypted string
  - `{:error, reason}` - Decryption failed
  """
  @spec decrypt(String.t() | nil) :: {:ok, String.t() | nil} | {:error, term()}
  def decrypt(encrypted) when is_binary(encrypted) do
    with {:ok, decoded} <- Base.decode64(encrypted),
         decrypted when is_binary(decrypted) <- __MODULE__.decrypt!(decoded) do
      {:ok, decrypted}
    else
      :error -> {:error, :invalid_base64}
      nil -> {:error, :decryption_failed}
      error -> {:error, error}
    end
  rescue
    error ->
      {:error, {:decryption_error, error}}
  end

  def decrypt(nil), do: {:ok, nil}
  def decrypt(_), do: {:error, :invalid_input}

  @doc """
  Encrypts a map of token data, encrypting only sensitive fields.

  ## Parameters
  - `token_map` - Map containing token data

  ## Returns
  - `{:ok, encrypted_map}` - Map with encrypted sensitive fields
  - `{:error, reason}` - Encryption failed
  """
  @spec encrypt_token_map(map()) :: {:ok, map()} | {:error, term()}
  def encrypt_token_map(token_map) when is_map(token_map) do
    sensitive_fields = [:access_token, :refresh_token, "access_token", "refresh_token"]

    encrypted_map =
      Enum.reduce(token_map, %{}, fn {key, value}, acc ->
        if key in sensitive_fields and is_binary(value) do
          case encrypt(value) do
            {:ok, encrypted} -> Map.put(acc, key, encrypted)
            _ -> Map.put(acc, key, value)
          end
        else
          Map.put(acc, key, value)
        end
      end)

    {:ok, encrypted_map}
  end

  def encrypt_token_map(_), do: {:error, :invalid_input}

  @doc """
  Decrypts a map of token data, decrypting only sensitive fields.

  ## Parameters
  - `encrypted_map` - Map containing encrypted token data

  ## Returns
  - `{:ok, decrypted_map}` - Map with decrypted sensitive fields
  - `{:error, reason}` - Decryption failed
  """
  @spec decrypt_token_map(map()) :: {:ok, map()} | {:error, term()}
  def decrypt_token_map(encrypted_map) when is_map(encrypted_map) do
    sensitive_fields = [:access_token, :refresh_token, "access_token", "refresh_token"]

    decrypted_map =
      Enum.reduce(encrypted_map, %{}, fn {key, value}, acc ->
        if key in sensitive_fields and is_binary(value) do
          case decrypt(value) do
            {:ok, decrypted} -> Map.put(acc, key, decrypted)
            _ -> Map.put(acc, key, value)
          end
        else
          Map.put(acc, key, value)
        end
      end)

    {:ok, decrypted_map}
  end

  def decrypt_token_map(_), do: {:error, :invalid_input}

  @doc """
  Checks if the encryption key is properly configured.

  ## Returns
  - `true` if key is configured
  - `false` if key is missing or invalid
  """
  @spec key_configured?() :: boolean()
  def key_configured? do
    # Check if we can successfully encrypt a test value
    case encrypt("test") do
      {:ok, _} -> true
      _ -> false
    end
  end

  # Private functions

  defp decode_key(nil) do
    # Return nil if no key is set - will cause vault to fail gracefully
    nil
  end

  defp decode_key(key) when is_binary(key) do
    # Decode base64 key or use raw key if decoding fails
    case Base.decode64(key) do
      {:ok, decoded} -> decoded
      :error -> key
    end
  end
end
