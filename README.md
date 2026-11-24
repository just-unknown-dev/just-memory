# Just Memory

High-performance shared memory management for the Just Game Engine ecosystem.

This package is built for performance-first workloads such as games, real-time simulation, reactive systems, and long-running sessions where reducing allocation churn matters.
For a deeper design overview, see [ARCHITECTURE.md](ARCHITECTURE.md). A runnable tour of every part is in [example/example.dart](example/example.dart).

## Features

- Object pooling for high-churn objects
- Scene and subsystem cleanup scopes
- Reference-counted shared resources
- Budgeted caches with eviction
- Arena-style contiguous memory storage
- Leak tracking for debug builds
- Runtime profiling snapshots for tuning

## Why this package exists

The goal of just_memory is to:

- reduce garbage collection pressure
- keep hot paths allocation-light
- make resource release deterministic
- provide simple profiling hooks for tuning memory budgets

It does not directly control the Dart VM or force OS-level RAM cleanup. Instead, it helps your code release references and reuse memory efficiently.

## Installation

```yaml
dependencies:
  just_memory: ^0.2.0
```

It is pure Dart (no Flutter dependency) and runs on every platform, including the web.

Then import it:

```dart
import 'package:just_memory/just_memory.dart';
```

## Quick start

### Object pooling

```dart
final bulletPool = ObjectPool<Bullet>(
  create: () => Bullet(),
  reset: (bullet) => bullet.reset(),
  initialSize: 128,
  maxSize: 256,
);

final bullet = bulletPool.acquire();
// use bullet
bulletPool.release(bullet);
```

### Cleanup scopes

```dart
final scope = MemoryScope(debugLabel: 'battle-scene');

final tempList = scope.ownValue(<String>[], (list) => list.clear());

scope.own(() {
  print('scene cleanup complete');
});

scope.dispose();
```

### Reference-counted resources

```dart
final registry = RefCountedRegistry<String, String>(
  loader: (key) async => 'loaded:$key',
  disposer: (value) {
    // cleanup
  },
);

final handle = await registry.acquire('player-texture');
print(handle.value);
await handle.release();
```

### Budgeted cache

```dart
final cache = BudgetedCache<String, String>(
  maxCost: 100,
  estimateCost: (key, value) => value.length,
  // Every value that leaves the cache (eviction, replacement, clear())
  // passes through here.
  onEvict: (key, value) {
    print('Evicted $key');
  },
);

cache['hero'] = 'cached-data';
final result = cache['hero'];
```

### Arena allocation

```dart
final arena = MemoryArena(capacity: 1000, componentsPerEntity: 8);
final slot = arena.allocate();

arena.setPosition(slot, 120, 240);
arena.setVelocity(slot, 10, -2);
arena.applyVelocity(slot, 0.016);
```

### Profiling snapshots

```dart
final profiler = MemoryProfiler();
profiler.trackPool('bullets', bulletPool);
profiler.trackCache('assets', cache);

final snapshot = profiler.capture();
print(snapshot.poolStats);
print(snapshot.cacheStats);
```

## Main APIs

### ObjectPool

Use this when objects are created and destroyed frequently.

Best for:
- particles
- bullets
- temporary lists
- short-lived event payloads
- audio voice buffers

### MemoryScope

Use this to group cleanup operations by scene, system, or feature lifetime.

Best for:
- scene transitions
- subsystem teardown
- temporary runtime ownership

### RefCountedRegistry

Use this when multiple systems share the same resource and it should only be unloaded after the final consumer releases it.

Best for:
- textures
- audio data
- loaded definitions
- compiled runtime assets

### BudgetedCache

Use this when you need a bounded cache with predictable eviction behavior.

Best for:
- runtime metadata
- decoded blobs
- expensive derived results

### MemoryArena

Use this when you want compact, contiguous numeric storage for the hottest loops.

Best for:
- transform state
- physics data
- simulation buffers

### MemoryProfiler

Use this to inspect tracked pools and caches at runtime and tune your memory budgets.

## Behaviour to know

- **Pools track objects by identity.** Pooling types that override `==` (vectors, value objects) is safe, and they may be mutated while in use. Releasing an object twice is ignored; releasing one the pool never handed out throws a `StateError`.
- **`acquireScoped` leases are per acquisition.** If you release a scoped object yourself, the scope leaves it alone later, even when the pool has handed it to someone else.
- **`BudgetedCache.onEvict` sees every value that leaves the cache** except through `remove` (which returns it): budget evictions, replaced values, values too large to fit, and `clear()`. Free cached resources there.
- **`RefCountedRegistry.dispose()` frees everything now.** Handles still held become inert, and loads still running are freed when their own handles are released.
- **`MemoryScope.dispose()` does not wait** for callbacks that return futures. Use `disposeAsync()` when cleanup is asynchronous (for example registry handles).
- **`MemoryArena`'s named accessors need 8 components per slot.** With a shorter layout use `getValue`/`setValue`; debug builds assert on out-of-range slots and offsets, release builds do not check.
- **`releaseAll`, `PoolManager.clearAll` and the profiler's cleanup helpers act on objects that are still in use.** Call them only at teardown.

## Performance notes

For best results:

- prewarm pools for known hot paths
- keep reset callbacks very cheap
- use scopes for deterministic cleanup
- keep cache budgets bounded
- profile before raising limits

## Current status

Just Game Engine uses it for its particle pools, asset scopes and storage caches, and Just Audio Engine for its voice pool. See [CHANGELOG.md](CHANGELOG.md) for what changed in each release.
