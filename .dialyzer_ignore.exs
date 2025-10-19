[
  # Pre-existing warnings in codex_sdk - not related to approval hooks feature
  {"lib/codex/exec.ex", :pattern_match},
  {"lib/codex/exec.ex", :pattern_match_cov},
  {"lib/codex/options.ex", :pattern_match_cov},
  {"lib/codex/thread.ex", :pattern_match},
  {"lib/codex/thread.ex", :pattern_match_cov},
  {"lib/codex/tools.ex", :extra_range},
  {"lib/codex/tools.ex", :contract_supertype},
  # Mix task warnings - Mix.Task behaviour not available in dev/test
  {"lib/mix/tasks/codex.parity.ex", :callback_info_missing},
  {"lib/mix/tasks/codex.parity.ex", :unknown_function},
  {"lib/mix/tasks/codex.verify.ex", :callback_info_missing},
  {"lib/mix/tasks/codex.verify.ex", :unknown_function}
]
