# Test support modules would be loaded here if needed

# Configure ExUnit with test groups for better parallel execution
ExUnit.start(
  # Configure test groups for better organization and parallel execution
  exclude: [:skip],
  include: [
    unit: true,
    integration: true,
    web: true,
    services: true,
    database: true
  ]
)

# Define mocks for testing
Mox.defmock(Server.MockOAuthTokenManager, for: Server.OAuthTokenManagerBehaviour)

Ecto.Adapters.SQL.Sandbox.mode(Server.Repo, :manual)
