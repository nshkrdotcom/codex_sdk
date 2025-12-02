Code.require_file("support/contract_case.ex", __DIR__)
Code.require_file("support/fixture_scripts.ex", __DIR__)

{:ok, _} = Application.ensure_all_started(:erlexec)

ExUnit.configure(exclude: [:pending], max_cases: 1)
ExUnit.start()
