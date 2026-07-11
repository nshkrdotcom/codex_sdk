# Atom Safety

**Rule:** never create an atom from external or unbounded input at runtime.
The BEAM atom table is capped (about 1,048,576 entries by default) and atoms
are never garbage-collected. Turning CLI-, JSON-, environment-, registry-, or
model-derived strings into atoms can exhaust the table and terminate the VM.

## Banned on untrusted input

- runtime atom-conversion helpers from `String`, `List`, or `:erlang`
- interpolated atom syntax built from runtime values
- `Jason.decode!(json, keys: :atoms)` and equivalent decoder options

## Safe patterns

1. Use an explicit static map or `case` from known strings to literal atoms,
   with the original string as the fallback. Unknown wire values must remain
   strings. The app-server parameter normalizers and `Codex.Events` follow
   this pattern.
2. Use an existing-atoms-only conversion only when the atom is provably
   predefined. A static lookup is usually clearer and avoids exceptions.
3. Decode JSON with string keys. `keys: :atoms!` is safe only when atom keys
   are genuinely required because it resolves existing atoms only.
4. Keep opaque values such as model IDs, event types, plugin keys, and tool
   names as strings unless the SDK has a finite, declared atom vocabulary.

## Guardrails

Two independent checks run in `mix ci`:

- `Credo.Check.Warning.UnsafeToAtom`, scoped to `lib/` in `.credo.exs`.
- `scripts/atom_guard.sh`, an `rg` backstop that rejects dynamic-atom patterns
  in `lib/**/*.ex` unless a reviewed same-line `# atom-safe:` annotation is
  present.

Bounded compile-time module-name construction may be annotated with both
`# atom-safe:` and `credo:disable-for-next-line` when Credo cannot infer that
the values come only from source declarations.
