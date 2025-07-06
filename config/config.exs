# Configuration for the Landale streaming system

import Config

# Game ID to show mapping configuration
config :server, :game_show_mapping, %{
  # Pokemon FireRed/LeafGreen for IronMON
  "13332" => :ironmon,
  # Software and Game Development
  "1469308723" => :coding,
  # Just Chatting
  "509658" => :variety
}

# StreamProducer timing configuration (milliseconds)
config :server,
  ticker_interval: 15_000,        # 15 seconds - ticker rotation
  sub_train_duration: 300_000,    # 5 minutes - sub train duration
  cleanup_interval: 600_000,      # 10 minutes - cleanup stale data
  max_timers: 100,                # Maximum active timers
  alert_duration: 10_000,         # 10 seconds - alert display time
  manual_override_duration: 30_000 # 30 seconds - manual override time

# StreamProducer cleanup configuration
config :server, :cleanup_settings,
  max_interrupt_stack_size: 50,        # Max interrupts before cleanup
  interrupt_stack_keep_count: 25       # How many to keep after cleanup

# Import environment specific config
if config_env() != :test do
  import_config "#{config_env()}.exs"
end
