ExUnit.start()

# Define mocks for testing
Mox.defmock(Server.MockOAuthTokenManager, for: Server.OAuthTokenManagerBehaviour)

Ecto.Adapters.SQL.Sandbox.mode(Server.Repo, :manual)
