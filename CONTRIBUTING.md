# Contributing to just_memory

Thank you for your interest in contributing to **just_memory**.

This package provides the shared memory-management foundation for the Just game engine, with a strong focus on performance, deterministic cleanup, and low-allocation runtime behavior.

---

## Code of Conduct

By participating in this project, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

---

## Getting Started

1. Clone the repository:

   ```bash
   git clone https://github.com/just-unknown-dev/just-memory.git
   cd just-memory
   ```

2. Install dependencies:

   ```bash
   dart pub get
   ```

3. Run checks before making changes:

   ```bash
   dart analyze
   dart test
   ```

---

## What to Contribute

Contributions are welcome for:

- performance improvements
- pooling and allocation strategies
- cache eviction and budgeting
- profiling and diagnostics
- test coverage
- documentation improvements

---

## Pull Request Guidelines

Before opening a pull request:

1. Keep changes focused and minimal.
2. Add or update tests for changed behavior.
3. Verify the package locally:

   ```bash
   dart analyze
   dart test
   ```

4. Use clear commit messages.

Example:

```text
feat(memory): add runtime profile snapshots
fix(cache): correct budget eviction ordering
```

---

## Development Notes

This package is a **pure Dart package**.

### Priorities

- performance first
- predictable cleanup
- low allocation churn
- no unnecessary dependencies

### Guidelines

- Prefer simple APIs with cheap hot paths.
- Keep debug/profiling features lightweight and optional in usage.
- Document all public APIs.
- Avoid changes that introduce hidden allocations in critical loops.
- Add benchmarks or tests when changing core memory behavior.

---

## Reporting Issues

When reporting a bug, include:

- what you expected
- what happened instead
- a minimal reproduction
- Dart and Flutter version details if relevant
- any profiling or memory-growth observations

---

## License

By contributing, you agree that your contributions will be licensed under the repository license.
