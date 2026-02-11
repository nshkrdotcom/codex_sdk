Code.require_file("support/contract_case.ex", __DIR__)
Code.require_file("support/app_server_subprocess.ex", __DIR__)
Code.require_file("support/fixture_scripts.ex", __DIR__)
Code.require_file("support/parity_matrix.ex", __DIR__)
Code.require_file("support/mock_websocket.ex", __DIR__)
Code.require_file("support/model_fixtures.ex", __DIR__)

{:ok, _} = Application.ensure_all_started(:erlexec)

ExUnit.configure(exclude: [:pending, :live], max_cases: 1, capture_log: false)
ExUnit.start()
