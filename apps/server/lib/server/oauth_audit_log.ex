defmodule Server.OAuthAuditLog do
  @moduledoc """
  Audit logging for OAuth operations.

  Provides security compliance logging for all OAuth token operations,
  including access, refresh, validation, and storage events.
  """

  require Logger

  @audit_events [
    :token_accessed,
    :token_refreshed,
    :token_validated,
    :token_stored,
    :token_deleted,
    :refresh_failed,
    :validation_failed,
    :encryption_failed,
    :decryption_failed,
    :migration_completed
  ]

  @doc """
  Logs an OAuth audit event.
  """
  def log_event(event, metadata \\ %{}) when event in @audit_events do
    log_entry = build_log_entry(event, metadata)

    # Log to application logger with audit tag
    Logger.info("[OAUTH_AUDIT] #{format_event(event)}", log_entry)

    # Store in database for compliance (if needed)
    if should_persist?(event) do
      persist_audit_log(event, log_entry)
    end

    :ok
  end

  @doc """
  Logs a security violation.
  """
  def log_security_violation(violation_type, metadata \\ %{}) do
    log_entry = build_log_entry(:security_violation, Map.put(metadata, :type, violation_type))

    # Security violations are always logged at warning level
    Logger.warning("[OAUTH_SECURITY] #{violation_type}", log_entry)

    # Always persist security violations
    persist_audit_log(:security_violation, log_entry)

    :ok
  end

  # Private functions

  defp build_log_entry(event, metadata) do
    %{
      event: event,
      timestamp: DateTime.utc_now(),
      service: Map.get(metadata, :service),
      user_id: Map.get(metadata, :user_id),
      client_id: Map.get(metadata, :client_id),
      ip_address: Map.get(metadata, :ip_address),
      correlation_id: get_correlation_id(),
      metadata: sanitize_metadata(metadata)
    }
  end

  defp get_correlation_id do
    # Generate a unique ID for this audit event
    "audit_#{:erlang.unique_integer([:positive])}_#{System.system_time(:microsecond)}"
  end

  defp sanitize_metadata(metadata) do
    # Remove sensitive data from metadata
    metadata
    |> Map.drop([:access_token, :refresh_token, :client_secret])
    |> Map.update(:error, nil, &sanitize_error/1)
  end

  defp sanitize_error(error) when is_binary(error), do: error
  defp sanitize_error(error), do: inspect(error)

  defp format_event(event) do
    event
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.upcase()
  end

  defp should_persist?(event) do
    # Persist important security events
    event in [
      :token_stored,
      :token_deleted,
      :refresh_failed,
      :validation_failed,
      :encryption_failed,
      :decryption_failed,
      :migration_completed
    ]
  end

  defp persist_audit_log(_event, _log_entry) do
    # Store in database for compliance
    # This would write to an audit_logs table
    Task.start(fn ->
      try do
        # Placeholder for actual database persistence
        # Server.Repo.insert!(%Server.AuditLog{
        #   event: Atom.to_string(event),
        #   service: log_entry.service,
        #   user_id: log_entry.user_id,
        #   metadata: Jason.encode!(log_entry.metadata),
        #   created_at: log_entry.timestamp
        # })
        :ok
      rescue
        error ->
          Logger.error("Failed to persist audit log", error: inspect(error))
      end
    end)

    :ok
  end
end
