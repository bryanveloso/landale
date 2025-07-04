# Configure ExUnit with test groups for better parallel execution
ExUnit.start(
  # Configure test groups for better organization and parallel execution
  exclude: [:skip],
  include: [
    unit: [:unit],
    integration: [:integration],
    web: [:web],
    services: [:services],
    database: [:database]
  ]
)

# Define mocks for testing
Mox.defmock(Server.MockOAuthTokenManager, for: Server.OAuthTokenManagerBehaviour)

Ecto.Adapters.SQL.Sandbox.mode(Server.Repo, :manual)
