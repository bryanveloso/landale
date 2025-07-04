# ElixirLS project configuration for better IDE integration
# This file configures compiler locks and LSP listeners for Elixir 1.18

use Mix.Config

# Enable compiler locks for better concurrent compilation
config :elixir, :ansi_enabled, true

# Configure LSP-specific settings
config :elixir_ls,
  dialyzer_enabled: true,
  dialyzer_format: "short",
  suggest_specs: true,
  auto_insert_required_alias: false,
  preferred_test_file_patterns: [
    "{test,spec}/**/*_{test,spec}.{ex,exs}",
    "{test,spec}/**/test_*.{ex,exs}"
  ]

# Enable enhanced pattern matching and type inference
config :elixir, :dbg_callback, {IEx, :inspect_with_label, []}

# Configure compiler options for better LSP integration
config :elixir,
  :compiler_options,
  docs: true,
  debug_info: true,
  warnings_as_errors: false

# Enable telemetry for LSP performance monitoring
config :telemetry, :disable_default_telemetry, false
