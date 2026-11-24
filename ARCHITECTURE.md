# Just Memory Architecture

## Overview

just_memory is a lightweight memory-management package for allocation-sensitive Dart and Flutter workloads.

It is designed for game loops, simulation systems, tooling, and long-running runtime sessions where the main goals are:

- reducing allocation churn
- making ownership explicit
- bounding memory growth
- improving cleanup determinism
- exposing diagnostics for tuning

The package does **not** replace the Dart garbage collector or provide unsafe manual memory management. Instead, it adds reusable patterns that help callers structure memory-sensitive code safely and predictably.

---

## Design Principles

### 1. Performance-first, but safe-by-default
The package favors reusable objects, bounded storage, and contiguous numeric buffers while keeping the API idiomatic for normal Dart applications.

### 2. Explicit ownership
Resources should have a clear lifetime. The package models this through scoped cleanup, pooled reuse, and reference-counted sharing.

### 3. Small composable primitives
Each module solves one memory-related problem well rather than forcing a single global memory subsystem.

### 4. Instrument before tuning
Profiling and leak-tracking utilities are built in so systems can be measured before limits or budgets are increased.

---

## Package Layers

The public barrel in `lib/just_memory.dart` exports the package as a set of focused modules:

| Layer | Responsibility | Main Types |
| --- | --- | --- |
| core | Shared stats/value objects | `MemoryStats` |
| pool | Reuse frequently created objects | `ObjectPool`, `RoundRobinPool`, `PriorityPool`, `PoolManager` |
| scope | Group cleanup by lifetime | `MemoryScope` |
| resource | Share loaded resources safely | `RefCountedRegistry`, `ResourceHandle` |
| cache | Keep memoized data within budget | `BudgetedCache`, `CacheBudgetStats` |
| arena | Store hot numeric state contiguously | `MemoryArena`, `TypedVec2`, `TypedTransform`, `TypedBuffer` |
| diagnostics | Observe runtime memory behavior | `MemoryProfiler`, `LeakTracker`, `SystemMemorySnapshot` |

---

## High-Level Dependency Flow

```text
just_memory.dart
 ├─ core/
 ├─ pool/ ───────┐
 ├─ scope/ ───┐  │
 ├─ resource/ │  │
 ├─ cache/    │  │
 ├─ arena/    │  │
 └─ diagnostics/
        ├─ reads pool stats
        ├─ reads cache stats
        └─ probes host system memory
```

The modules are intentionally loosely coupled:

- `MemoryScope` can be used independently for cleanup orchestration.
- `ObjectPool` is standalone and does not require the profiler.
- `RefCountedRegistry` optionally integrates with `MemoryScope`.
- `MemoryProfiler` observes pools and caches without owning them.

---

## Core Runtime Building Blocks

### Object reuse layer
The pooling layer exists for short-lived, high-churn objects such as particles, bullets, buffers, temporary commands, and event payloads.

#### `ObjectPool<T>`
Primary general-purpose pool.

Responsibilities:
- create new values on demand
- reuse returned values
- track in-use and available counts
- optionally reset or recycle values on release
- support scoped ownership through `acquireScoped()`

Important behavior:
- values must be acquired before they are released
- values are tracked by identity, so value-equality types are safe to pool and mutate
- releasing a foreign value throws a `StateError`; releasing a free value again is ignored
- a scoped acquisition is a lease: the scope only releases the value if that lease is still current
- prewarming can reduce first-use allocation spikes

#### `RoundRobinPool<T>`
Useful when a fixed-size rotating buffer is enough and exact acquire/release semantics are not needed.

#### `PriorityPool<T>`
Supports reclaiming or reusing lower-priority objects when availability is constrained.

#### `PoolManager`
An optional registry/singleton convenience layer for coordinating named pools and arenas across a larger system.

---

### Lifetime ownership layer
The scope layer is the package’s deterministic cleanup primitive.

#### `MemoryScope`
A `MemoryScope` stores cleanup callbacks and runs them in LIFO order when the scope is disposed.

Use cases:
- scene teardown
- subsystem shutdown
- temporary ownership of pooled or loaded resources
- grouping multiple cleanup steps into one lifetime

Cleanup modes:
- `dispose()` for synchronous cleanup
- `disposeAsync()` when owned callbacks return `Future`s and must be awaited

This distinction matters for resources such as async disposers, file handles, or delayed unload operations.

---

### Shared resource layer
The resource layer handles assets or values that may be used by multiple systems at the same time.

#### `RefCountedRegistry<K, V>`
Responsibilities:
- load a value once per key
- coalesce concurrent loads for the same key
- keep a reference count per loaded value
- call the configured disposer when the final consumer releases the value
- on `dispose()`, free every loaded value at once and make outstanding handles inert

Typical uses:
- textures
- audio buffers
- compiled or parsed definitions
- expensive runtime metadata

A returned `ResourceHandle` exposes the value and its release path. When integrating with `MemoryScope`, prefer `disposeAsync()` if cleanup must fully complete before continuing.

---

### Bounded memoization layer
The cache layer prevents unbounded growth in derived or expensive-to-recompute data.

#### `BudgetedCache<K, V>`
Responsibilities:
- estimate the cost of each entry using caller-defined logic
- store entries in access order
- evict least-recently-used items when total cost exceeds the configured budget
- pass every value that leaves the cache (eviction, replacement, oversize rejection, `clear()`) to `onEvict`, so resources can be freed in one place

The cache is budget-based rather than count-based, so callers can define cost in bytes, complexity units, decoded size, or any other useful metric.

---

### Contiguous data layer
The arena layer is for the hottest loops where boxed object graphs can become costly.

#### `MemoryArena`
Stores entity-like numeric state inside a contiguous `Float64List`.

It is optimized for transform-style data such as:
- position
- rotation
- scale
- velocity
- extra per-slot numeric values

Benefits:
- better locality than many separate objects
- fewer short-lived allocations in update loops
- direct indexed access for simulation-style workloads

#### `TypedVec2`, `TypedTransform`, and `TypedBuffer`
These provide typed, ergonomic access over arena-backed or typed-list-backed storage without losing the low-allocation layout.

---

## Diagnostics Layer

### `MemoryProfiler`
The profiler tracks pools and caches and can capture snapshots for inspection.

It supports:
- per-pool statistics
- per-cache budget statistics
- tracked cleanup helpers
- system memory snapshots through platform probes

### `LeakTracker`
A simple debug utility for tracking live objects by label and surfacing leak summaries.

### `SystemMemorySnapshot`
Represents host/process memory information gathered through platform-specific probing.

---

## Typical Usage Patterns

### Pattern 1: High-churn object reuse
Use `ObjectPool` when objects are created and destroyed frequently within a frame or simulation step.

### Pattern 2: Scene or subsystem ownership
Use `MemoryScope` to group cleanup work for a scene, mode, or subsystem lifetime.

### Pattern 3: Shared assets with deterministic unload
Use `RefCountedRegistry` when multiple consumers may share the same resource and unload should happen only after the final release.

### Pattern 4: Bounded derived data
Use `BudgetedCache` when expensive computed values should be cached but memory usage must remain controlled.

### Pattern 5: Hot numeric loops
Use `MemoryArena` and typed buffers when transform-style simulation data becomes a bottleneck due to allocation or layout overhead.

---

## Error Handling and Safety Notes

- The package is built for single-isolate usage patterns unless callers add their own synchronization layer.
- `ObjectPool` assumes ownership discipline: acquire first, then release.
- `MemoryScope.disposeAsync()` should be preferred whenever a registered cleanup callback is asynchronous.
- `RefCountedRegistry` handles duplicate loads for the same key, but callers are still responsible for releasing acquired handles.
- `BudgetedCache` depends on a sensible cost model supplied by the caller.

---

## Trade-offs

The package intentionally prefers simplicity over implementing a full custom allocator.

This means:
- it works with normal Dart objects and GC behavior
- it avoids unsafe memory tricks
- it relies on caller discipline for correct ownership
- it targets practical engine/runtime ergonomics rather than VM-level control

That trade-off keeps the package portable, testable, and easy to integrate across the Just workspace.

---

## Recommended Evolution

Good next steps for the package include:

- adding more examples for async scope cleanup
- documenting performance guidance for when to choose pools vs arenas
- a real free-memory figure on macOS and iOS (today it is total minus the process's resident set)

Every public symbol is documented (`public_member_api_docs` is enabled) and each module has its own test file.

---

## Summary

just_memory is best understood as a toolkit of memory-aware runtime primitives:

- pools for reuse
- scopes for lifetime management
- registries for shared ownership
- caches for bounded growth
- arenas for hot numeric state
- diagnostics for visibility

Together these pieces provide a practical memory architecture for performance-sensitive Dart systems without leaving the safety of normal managed code.
