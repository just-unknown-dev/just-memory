/// Memory-management primitives for games and other real-time Dart code.
///
/// * [ObjectPool], [RoundRobinPool] and [PriorityPool] reuse objects instead
///   of allocating new ones; [PoolManager] shares them by name.
/// * [MemoryScope] runs a lifetime's cleanup steps together.
/// * [RefCountedRegistry] loads shared resources once and frees them after
///   the last holder lets go.
/// * [BudgetedCache] is an LRU cache bounded by total cost.
/// * [MemoryArena], [TypedVec2], [TypedTransform] and [TypedBuffer] keep hot
///   numeric state in flat typed arrays.
/// * [MemoryProfiler] and [LeakTracker] show what is held and what leaked.
library;

export 'src/arena/memory_arena.dart';
export 'src/arena/typed_buffer.dart';
export 'src/cache/budgeted_cache.dart';
export 'src/cache/cache_budget_stats.dart';
export 'src/core/memory_stats.dart';
export 'src/diagnostics/leak_tracker.dart';
export 'src/diagnostics/memory_profiler.dart';
export 'src/diagnostics/system_memory_snapshot.dart';
export 'src/pool/object_pool.dart';
export 'src/pool/pool_manager.dart';
export 'src/pool/recyclable.dart';
export 'src/resource/ref_counted_registry.dart';
export 'src/scope/memory_scope.dart';
