defmodule Server.Test.MockEventSubManager do
  @moduledoc """
  Mock EventSubManager for testing that doesn't make actual HTTP requests.
  """

  @doc """
  Mock version that returns success without making HTTP calls.
  """
  def create_default_subscriptions(_state) do
    # Return success count and failure count
    # Simulate creating 3 subscriptions successfully
    {3, 0}
  end

  @doc """
  Mock version for creating individual subscriptions.
  """
  def create_subscription(_event_type, _condition, _state, _opts \\ []) do
    {:ok,
     %{
       "id" => "mock-subscription-#{:rand.uniform(1000)}",
       "status" => "enabled",
       "type" => "mock.subscription",
       "version" => "1",
       "created_at" => DateTime.to_iso8601(DateTime.utc_now())
     }}
  end
end
