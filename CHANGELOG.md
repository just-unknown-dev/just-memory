# Changelog

## [0.2.0] - 2026-11-24

An audit's worth of fixes, the whole public API documented, an example and
a much larger test suite. Nothing is removed, but several behaviours change;
read "Changed" before upgrading.

### Fixed

- `TypedVec2.length`, `distanceTo` and `normalize` used a ten-step Newton
  square root seeded at `x / 2`, which was wrong outside roughly 0.01–10⁴
  (a vector of length 1000 measured 1033.8, one of length 10⁵ measured
  4.9 million). They now use `dart:math`'s `sqrt`.
- `ObjectPool` and `PriorityPool` tracked objects with `==`/`hashCode`. Pooled
  types with value equality could not be released after being mutated
  (`StateError`), and equal objects in use at the same time were counted
  once and leaked. Both pools now track objects by identity.
- `ObjectPool.acquireScoped`: when the object was released by hand and handed
  to someone else, disposing the scope released the new holder's object. The
  scope now only releases its own lease.
- `RefCountedRegistry`:
  - a handle held across `dispose()` could release, and free, the value
    loaded again for the same key afterwards; such handles are now inert;
  - a load still running during `dispose()` put its value back into the
    registry, where nothing would free it; it now stays out and is freed
    when its handles are released;
  - a reference is counted when `acquire` is called, not when its load
    finishes, so a value can no longer be freed between the two (for
    example when another holder releases the last handle meanwhile);
  - callers joining a load share the loader's entry instead of possibly
    getting an untracked copy.
- `BudgetedCache`: storing a value costing more than `maxCost` evicted every
  other entry before evicting itself. It is now rejected on its own.
- `MemoryArena`: with fewer than 8 components per slot, the named transform
  accessors silently wrote into the next slot. Debug builds now assert that
  slot and offset are in range.
- `ObjectPool.shrink` with a negative target threw a `RangeError` after
  emptying the pool; negative targets now count as zero.
- `LeakTracker` keyed objects by `==`, merging equal objects; it now tracks
  identity.

### Changed

- `BudgetedCache.onEvict` now receives every value that leaves the cache
  except through `remove`: a value replaced by a different one under the same
  key, a value too large to cache, and every entry dropped by `clear()` (the
  cache is already empty when the callbacks run). Before, replaced and
  cleared values were dropped silently.
- `BudgetedCache` throws an `ArgumentError` when `estimateCost` returns a
  negative cost.
- `ObjectPool` throws a `RangeError` for a negative `maxSize`;
  `RoundRobinPool` throws a `RangeError` for a `size` below 1 (it used to
  fail on the first `next()`).
- `MemoryProfiler.cleanupGlobalResources` no longer swallows errors: it
  returns an empty result only when the shared `PoolManager` is disposed,
  and errors from pool reset callbacks propagate.
- `MemoryScope` error messages include the scope's `debugLabel`.

### Added

- `PriorityPool.onReclaim`, called with an in-use object before `acquire`
  takes it back from its holder.
- `RefCountedRegistry.isLoading`.
- `MemoryArena.componentsPerEntity`.
- Dartdoc for the whole public API (`public_member_api_docs` is now on), an
  example in `example/example.dart`, and tests for every module (line
  coverage 28% → 94%).

## [0.1.0] - 2026-04-18

Initial release of Just Memory, a performance-focused shared memory management package for the Just Game Engine ecosystem.

### Added

- Object pooling utilities for high-churn runtime objects.
- Memory scopes for deterministic scene and subsystem cleanup.
- Reference-counted shared resource management.
- Budgeted caches with predictable eviction behavior.
- Arena-style contiguous storage for hot simulation loops.
- Runtime memory profiling snapshots and debug-oriented leak tracking.
