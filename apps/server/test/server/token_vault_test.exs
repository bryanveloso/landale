defmodule Server.TokenVaultTest do
  use ExUnit.Case, async: true

  alias Server.TokenVault

  describe "encrypt/1 and decrypt/1" do
    test "successfully encrypts and decrypts a string" do
      plaintext = "super_secret_token_12345"

      assert {:ok, encrypted} = TokenVault.encrypt(plaintext)
      assert is_binary(encrypted)
      assert encrypted != plaintext

      assert {:ok, decrypted} = TokenVault.decrypt(encrypted)
      assert decrypted == plaintext
    end

    test "handles nil values" do
      assert {:ok, nil} = TokenVault.encrypt(nil)
      assert {:ok, nil} = TokenVault.decrypt(nil)
    end

    test "returns error for invalid input to encrypt" do
      assert {:error, :invalid_input} = TokenVault.encrypt(123)
      assert {:error, :invalid_input} = TokenVault.encrypt(%{})
    end

    test "returns error for invalid base64 in decrypt" do
      assert {:error, :invalid_base64} = TokenVault.decrypt("not-valid-base64!@#")
    end
  end

  describe "encrypt_token_map/1 and decrypt_token_map/1" do
    test "encrypts and decrypts token fields in a map" do
      token_map = %{
        access_token: "secret_access_token",
        refresh_token: "secret_refresh_token",
        expires_at: "2024-12-31T23:59:59Z",
        user_id: "12345",
        scopes: ["read", "write"]
      }

      assert {:ok, encrypted_map} = TokenVault.encrypt_token_map(token_map)

      # Sensitive fields should be encrypted
      assert encrypted_map.access_token != token_map.access_token
      assert encrypted_map.refresh_token != token_map.refresh_token

      # Non-sensitive fields should remain unchanged
      assert encrypted_map.expires_at == token_map.expires_at
      assert encrypted_map.user_id == token_map.user_id
      assert encrypted_map.scopes == token_map.scopes

      # Decrypt the map
      assert {:ok, decrypted_map} = TokenVault.decrypt_token_map(encrypted_map)

      # All fields should match original
      assert decrypted_map.access_token == token_map.access_token
      assert decrypted_map.refresh_token == token_map.refresh_token
      assert decrypted_map.expires_at == token_map.expires_at
      assert decrypted_map.user_id == token_map.user_id
      assert decrypted_map.scopes == token_map.scopes
    end

    test "handles maps with string keys" do
      token_map = %{
        "access_token" => "secret_access_token",
        "refresh_token" => "secret_refresh_token",
        "expires_at" => "2024-12-31T23:59:59Z",
        "user_id" => "12345"
      }

      assert {:ok, encrypted_map} = TokenVault.encrypt_token_map(token_map)
      assert encrypted_map["access_token"] != token_map["access_token"]
      assert encrypted_map["refresh_token"] != token_map["refresh_token"]

      assert {:ok, decrypted_map} = TokenVault.decrypt_token_map(encrypted_map)
      assert decrypted_map["access_token"] == token_map["access_token"]
      assert decrypted_map["refresh_token"] == token_map["refresh_token"]
    end

    test "handles maps with nil token values" do
      token_map = %{
        access_token: "secret_access_token",
        refresh_token: nil,
        expires_at: "2024-12-31T23:59:59Z"
      }

      assert {:ok, encrypted_map} = TokenVault.encrypt_token_map(token_map)
      assert encrypted_map.access_token != token_map.access_token
      assert encrypted_map.refresh_token == nil

      assert {:ok, decrypted_map} = TokenVault.decrypt_token_map(encrypted_map)
      assert decrypted_map.access_token == token_map.access_token
      assert decrypted_map.refresh_token == nil
    end
  end

  describe "key_configured?/0" do
    test "returns true when key is configured" do
      # Key should be configured in test environment
      assert TokenVault.key_configured?()
    end
  end
end
