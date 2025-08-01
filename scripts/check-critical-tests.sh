#!/bin/bash
# Check for critical protocol tests that must never be skipped

set -e

echo "🔍 Checking for critical protocol tests..."

# Define critical test files and their expected test modules
CRITICAL_TESTS="
test/server/services/obs/supervisor_test.exs:Server.Services.OBS.SupervisorTest
test/server/services/obs/connections_supervisor_test.exs:Server.Services.OBS.ConnectionsSupervisorTest
test/server/services/obs/connection_test.exs:Server.Services.OBS.ConnectionTest
test/server/oauth_token_manager_test.exs:Server.OAuthTokenManagerTest
test/server/services/twitch/eventsub_manager_test.exs:Server.Services.Twitch.EventSubManagerTest
"

FAILED=0

# Check each critical test file
echo "$CRITICAL_TESTS" | while IFS=: read -r TEST_FILE MODULE_NAME; do
  # Skip empty lines
  [ -z "$TEST_FILE" ] && continue

  if [ ! -f "$TEST_FILE" ]; then
    echo "❌ ERROR: Critical test file missing: $TEST_FILE"
    FAILED=1
    continue
  fi

  # Check if the module is defined
  if ! grep -q "defmodule $MODULE_NAME" "$TEST_FILE"; then
    echo "❌ ERROR: Test module $MODULE_NAME not found in $TEST_FILE"
    FAILED=1
    continue
  fi

  # Check if the module is skipped
  if grep -B2 "defmodule $MODULE_NAME" "$TEST_FILE" | grep -q "@moduletag :skip"; then
    echo "❌ ERROR: Critical test module $MODULE_NAME is skipped!"
    FAILED=1
    continue
  fi

  # Count actual test cases (excluding setup blocks)
  TEST_COUNT=$(grep -c "^\s*test\s" "$TEST_FILE" || true)
  if [ "$TEST_COUNT" -lt 3 ]; then
    echo "⚠️  WARNING: $MODULE_NAME has only $TEST_COUNT tests - consider adding more coverage"
  else
    echo "✅ $MODULE_NAME: $TEST_COUNT tests found"
  fi
done

# Check for @moduletag :skip in any test file
echo ""
echo "🔍 Checking for skipped test modules..."
if grep -r "@moduletag :skip" test/ --include="*.exs" | grep -v "test_helper.exs"; then
  echo "❌ ERROR: Found test modules marked with @moduletag :skip"
  echo "Skipping entire test modules is not allowed."
  FAILED=1
else
  echo "✅ No skipped test modules found"
fi

# Check for individual skipped tests (warning only)
echo ""
echo "🔍 Checking for individually skipped tests..."
SKIP_COUNT=$(grep -r "@tag :skip" test/ --include="*.exs" | grep -cv "test_helper.exs" || true)
if [ "$SKIP_COUNT" -gt 0 ]; then
  echo "⚠️  WARNING: Found $SKIP_COUNT individually skipped tests"
  echo "Consider fixing these tests:"
  grep -r "@tag :skip" test/ --include="*.exs" | grep -v "test_helper.exs" | head -10
  if [ "$SKIP_COUNT" -gt 10 ]; then
    echo "... and $(($SKIP_COUNT - 10)) more"
  fi
else
  echo "✅ No individually skipped tests found"
fi

# Note: We can't easily propagate FAILED from the subshell, so we re-check critical conditions
if grep -r "@moduletag :skip" test/ --include="*.exs" | grep -v "test_helper.exs" > /dev/null; then
  echo ""
  echo "❌ Critical test validation failed!"
  exit 1
fi

# Check if critical files exist
for entry in $CRITICAL_TESTS; do
  [ -z "$entry" ] && continue
  TEST_FILE=$(echo "$entry" | cut -d: -f1)
  if [ ! -f "$TEST_FILE" ]; then
    echo ""
    echo "❌ Critical test validation failed! Missing: $TEST_FILE"
    exit 1
  fi
done

echo ""
echo "✅ All critical tests are present and enabled"
