defmodule ServerWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use ServerWeb.ChannelCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import ServerWeb.ChannelCase

      # The default endpoint for testing
      @endpoint ServerWeb.Endpoint
    end
  end

  setup tags do
    Server.DataCase.setup_sandbox(tags)

    # Start cache for tests that need it
    if !Process.whereis(Server.Cache) do
      {:ok, _} = Server.Cache.start_link([])
    end

    # Verify mocks are properly stubbed before each test
    import Hammox
    verify_on_exit!()

    :ok
  end
end
