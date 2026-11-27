# HandDraw Studio Engineering Rules

- Treat every change as product work for paying users: protect correctness,
  visual quality, performance, accessibility, and backward compatibility.
- Inspect the current implementation and existing tests before editing. Preserve
  working behavior and unrelated user changes; never fix one flow by regressing
  another.
- Prefer feature-first, reusable, SOLID modules with one clear responsibility.
  Extract a shared abstraction when it removes real duplication or creates a
  useful product extension point; avoid speculative layers and overengineering.
- Use Cubit plus immutable states and `copyWith` for mutable application or view
  state. Keep pure geometry, formatting, and derived values as stateless,
  testable services instead of creating ceremonial Cubits.
- Keep Preview, canvas interaction, and MOV export on shared geometry and timing
  calculations whenever they represent the same product behavior.
- For visual or animation fixes, identify the root cause, add a focused
  regression test, then run the existing suite. Always run `flutter analyze`
  and relevant tests; run the full suite and a Release build for broad changes.
- Keep Arabic RTL, English LTR, light/dark themes, and responsive layouts working
  together. Avoid raw UI colors outside the central palette.
- If investigation reveals a proportionate architectural improvement, accuracy
  improvement, or proven library that benefits future product development,
  surface it explicitly. Do not add dependencies without a concrete benefit.
- Update version/build and What’s New for user-visible releases.
