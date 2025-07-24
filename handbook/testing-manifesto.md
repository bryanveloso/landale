# The Landale Testing Manifesto

*Last Updated: 2025-07-24*

After fixing 45+ test failures and deleting all property-based tests, we've learned critical lessons about what makes tests valuable versus worthless. This manifesto captures those hard-won insights to ensure we never write bad tests again.

## Core Philosophy

Tests exist to give us confidence that our code works as users expect. If a test doesn't directly relate to user-facing behavior, it's probably worthless.

## MANDATORY RULES (Never Break These)

### 1. Test Observable Behavior Only

Test WHAT the code does, not HOW it does it.

```elixir
# ✅ GOOD - Tests behavior
assert Process.alive?(event_handler)
assert ConnectionRefactored.get_state(conn) == :ready
assert_receive {:connection_established, %{session_id: ^session_id}}

# ❌ BAD - Tests implementation
assert log =~ "Received malformed OBS event"
assert :sys.get_state(pid).timer_ref != nil
```

### 2. Delete Tests That Test Nothing

If you can't explain what user-facing behavior breaks when this test fails, delete it.

**Questions to ask:**
- What feature stops working if this test fails?
- Does this test give me confidence to refactor?
- Would a user notice if this behavior changed?

If the answer is "no" to any of these, delete the test.

### 3. Mock External Services, Not Your Code

Mock at system boundaries only. Never mock your own modules.

```elixir
# ✅ GOOD - Mock external HTTP client
Mox.defmock(TwitchClient.Mock, for: TwitchClientBehaviour)

# ❌ BAD - Mock your own GenServer
expect(MyGenServer, :call, fn _, _ -> :ok end)  # Don't do this!
```

### 4. No Random Edge Cases

Property tests must use business-valid constraints or be deleted.

```elixir
# ✅ GOOD - Realistic constraints
property "handles valid Twitch subscription IDs" do
  check all sub_id <- string(:alphanumeric, min_length: 20, max_length: 40) do
    # Test with IDs that could actually exist
  end
end

# ❌ BAD - Meaningless randomness
property "handles any string" do
  check all str <- string() do  # Could be 10,000 chars of unicode!
    # This tests nothing useful
  end
end
```

### 5. Tests Are Documentation

Each test should tell a clear story about expected behavior.

```elixir
# ✅ GOOD - Clear story
test "disconnects cleanly when owner process terminates" do
  # Given: A connection with an owner
  {:ok, conn} = start_connection(owner: self())
  
  # When: The owner terminates
  Process.exit(self(), :normal)
  
  # Then: The connection shuts down
  refute Process.alive?(conn)
end

# ❌ BAD - What is this even testing?
test "process state after message" do
  send(pid, {:msg, "data"})
  assert :sys.get_state(pid).counter == 1
end
```

## Best Practices

### DAMP over DRY

**Descriptive And Meaningful Phrases** beat Don't Repeat Yourself in tests.

```elixir
# ✅ GOOD - Self-contained and clear
test "retries failed requests with exponential backoff" do
  # Complete test setup visible in one place
end

# ❌ BAD - Abstracted into confusion
test "retries work" do
  setup_retry_test(:exponential)  # What does this do?
end
```

### Test Names Should Describe Behavior

```elixir
# ✅ GOOD
test "broadcasts scene change event when OBS scene switches"
test "stays connected when receiving malformed JSON"

# ❌ BAD
test "scene change"
test "error handling"
```

### Integration Tests Need Clear Boundaries

Skip integration tests when dependencies aren't available:

```elixir
@moduletag :skip  # ConnectionsSupervisor not started in test env

# Or conditionally:
@tag :integration
test "full OBS connection flow" do
  # Requires real OBS instance
end
```

## Anti-Patterns We've Eliminated

### 1. Log Testing
**Never test log output.** We removed dozens of these:
```elixir
# ❌ DELETED
assert capture_log(fn -> ... end) =~ "some log message"
```

### 2. Property Testing Without Purpose
**We deleted ALL property tests** because they were testing meaningless scenarios:
```elixir
# ❌ DELETED - What value did this provide?
property "handles arbitrary request IDs" do
  check all id <- integer() do
    # Testing with random numbers that would never occur
  end
end
```

### 3. External API Calls in Tests
**Never make real HTTP requests:**
```elixir
# ❌ BEFORE - Caused timeouts and flakiness
test "creates Twitch subscription" do
  TwitchAPI.create_subscription(...)  # Real HTTP call!
end

# ✅ AFTER - Fast and reliable
test "creates Twitch subscription" do
  expect(TwitchClient.Mock, :post, fn _, _, _ -> 
    {:ok, %{status: 202}}
  end)
end
```

## The Testing Trophy

We follow the Testing Trophy model (not pyramid):

```
        🏆 E2E Tests (Few)
      /    \
    /  Integration  \  
  /    Tests (Some)   \
 /  Unit Tests (Many)  \
/______________________\
```

- **Unit Tests**: Fast, isolated, test single behaviors
- **Integration Tests**: Test interactions between modules
- **E2E Tests**: Test full user workflows (sparingly)

## Enforcement

1. **PR Reviews**: Reject tests that violate these principles
2. **CI Hooks**: Linting rules where possible
3. **Lead by Example**: Refactor old tests to show the way
4. **Documentation**: Link to this manifesto in PR templates

## Remember

> "Every bad test we write is technical debt that compounds. A bad test is worse than no test because it gives false confidence and breaks when you need it least."

When in doubt:
- Test behavior, not implementation
- Delete tests that test nothing
- Make tests tell a story
- Keep tests fast and deterministic