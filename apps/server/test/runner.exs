#!/usr/bin/env elixir

# Simple test runner for pure domain logic tests
# Avoids starting the full Phoenix application

ExUnit.start()

# Load the domain modules
Code.compile_file("lib/server/domains/stream_state.ex")
Code.compile_file("lib/server/domains/layer_coordination.ex")
Code.compile_file("lib/server/domains/alert_prioritization.ex")

# Load and run the tests
Code.compile_file("test/server/domains/stream_state_test.exs")
Code.compile_file("test/server/domains/layer_coordination_test.exs")
Code.compile_file("test/server/domains/alert_prioritization_test.exs")

ExUnit.run()
