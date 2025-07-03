defmodule Server.Repo do
  @moduledoc "Ecto repository for database operations."

  use Ecto.Repo,
    otp_app: :server,
    adapter: Ecto.Adapters.Postgres
end
