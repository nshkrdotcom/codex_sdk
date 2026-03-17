Code.require_file("support/contract_case.ex", __DIR__)
Code.require_file("support/app_server_subprocess.ex", __DIR__)
Code.require_file("support/auth_env.ex", __DIR__)
Code.require_file("support/fixture_scripts.ex", __DIR__)
Code.require_file("support/parity_matrix.ex", __DIR__)
Code.require_file("support/mock_websocket.ex", __DIR__)
Code.require_file("support/model_fixtures.ex", __DIR__)

{:ok, _} = Application.ensure_all_started(:erlexec)

ExUnit.configure(
  exclude: [:pending, :live],
  max_cases: 1,
  capture_log: false,
  # Many transport tests coordinate Task/GenServer/mock-subprocess hops before
  # asserting on mailbox traffic. The default 100ms receive window is too tight
  # on slower CI/dev boxes and causes suite-only flakiness.
  assert_receive_timeout: 500
)

ExUnit.start()
