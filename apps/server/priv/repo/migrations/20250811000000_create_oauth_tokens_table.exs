defmodule Server.Repo.Migrations.CreateOAuthTokensTable do
  use Ecto.Migration

  def change do
    create table(:oauth_tokens) do
      add :service, :string, null: false
      add :access_token, :text, null: false
      add :refresh_token, :text
      add :expires_at, :utc_datetime
      add :scopes, {:array, :string}, default: []
      add :user_id, :string
      add :client_id, :string
      add :encrypted, :boolean, default: true

      timestamps()
    end

    create unique_index(:oauth_tokens, [:service])
    create index(:oauth_tokens, [:expires_at])
  end
end
