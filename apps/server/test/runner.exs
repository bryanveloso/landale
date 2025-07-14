#!/usr/bin/env elixir

# Simple test runner for pure domain logic tests
# Avoids starting the full Phoenix application

ExUnit.start()

# Load the domain module
Code.compile_file("lib/server/domains/stream_state.ex")

# Load and run the test
Code.compile_file("test/server/domains/stream_state_test.exs")

ExUnit.run()