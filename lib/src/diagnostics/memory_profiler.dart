import '../cache/budgeted_cache.dart';
import '../cache/cache_budget_stats.dart';
import '../core/memory_stats.dart';
import '../pool/object_pool.dart';
import '../pool/pool_manager.dart';
import 'system_memory_probe.dart';
import 'system_memory_snapshot.dart';

/// Watches named pools and caches and captures their counters on demand.
///
/// The profiler only reads what it tracks; it does not own it.
/// [captureSystemMemory] reads the host's memory figures.
class MemoryProfiler {
  /// Creates a profiler that tracks nothing yet.
  MemoryProfiler();

  static const Duration _systemMemoryCacheDuration = Duration(seconds: 2);
  static SystemMemorySnapshot? _cachedSystemMemory;
  static DateTime? _lastSystemMemoryCapture;

  final Map<String, ObjectPool<dynamic>> _pools =
      <String, ObjectPool<dynamic>>{};
  final Map<String, BudgetedCache<dynamic, dynamic>> _caches =
      <String, BudgetedCache<dynamic, dynamic>>{};

  /// Tracks [pool] under [name], replacing any pool tracked under it.
  void trackPool<T>(String name, ObjectPool<T> pool) {
    _pools[name] = pool;
  }

  /// Stops tracking the pool under [name].
  void untrackPool(String name) {
    _pools.remove(name);
  }

  /// Tracks [cache] under [name], replacing any cache tracked under it.
  void trackCache<K, V>(String name, BudgetedCache<K, V> cache) {
    _caches[name] = cache;
  }

  /// Stops tracking the cache under [name].
  void untrackCache(String name) {
    _caches.remove(name);
  }

  /// The current counters of every tracked pool and cache.
  MemoryProfileSnapshot capture() {
    final poolStats = <String, MemoryStats>{};
    final cacheStats = <String, CacheBudgetStats>{};

    for (final entry in _pools.entries) {
      poolStats[entry.key] = entry.value.stats;
    }

    for (final entry in _caches.entries) {
      cacheStats[entry.key] = entry.value.stats;
    }

    return MemoryProfileSnapshot(
      timestamp: DateTime.now(),
      poolStats: poolStats,
      cacheStats: cacheStats,
    );
  }

  /// Releases every object of every tracked pool and clears every tracked
  /// cache (passing its entries to its `onEvict`).
  ///
  /// Objects still held by their users are released too, so only call this
  /// when nothing will touch them again. With [clearReleasedObjects], the
  /// pools also drop their free objects. [MemoryCleanupResult.releasedPools]
  /// counts the pools that held any objects.
  MemoryCleanupResult cleanupTrackedResources({
    bool clearReleasedObjects = false,
  }) {
    var releasedPools = 0;

    for (final pool in _pools.values) {
      if (pool.inUseCount > 0 || pool.availableCount > 0) {
        releasedPools++;
      }
      pool.releaseAll();
      if (clearReleasedObjects) {
        pool.clear();
      }
    }

    for (final cache in _caches.values) {
      cache.clear();
    }

    return MemoryCleanupResult(
      releasedPools: releasedPools,
      clearedCaches: _caches.length,
      clearedArenas: 0,
    );
  }

  /// Releases every pool and clears every arena registered with
  /// [PoolManager.instance]; with [clearReleasedObjects], also clears and
  /// unregisters them (see [PoolManager.clearAll]).
  ///
  /// Returns an empty result if the shared manager has been disposed.
  /// Errors thrown by pool reset callbacks are not caught.
  static MemoryCleanupResult cleanupGlobalResources({
    bool clearReleasedObjects = false,
  }) {
    final manager = PoolManager.instance;
    if (manager.isDisposed) {
      return const MemoryCleanupResult(
        releasedPools: 0,
        clearedCaches: 0,
        clearedArenas: 0,
      );
    }

    final releasedPools = manager.getPoolStats().length;
    final clearedArenas = manager.getArenaStats().length;

    manager.releaseAllPools();
    manager.clearAllArenas();
    if (clearReleasedObjects) {
      manager.clearAll();
    }

    return MemoryCleanupResult(
      releasedPools: releasedPools,
      clearedCaches: 0,
      clearedArenas: clearedArenas,
    );
  }

  /// The host's memory figures, re-read at most every two seconds.
  ///
  /// Never throws: on platforms it cannot read, or if reading fails, the
  /// snapshot's [SystemMemorySnapshot.isSupported] is false.
  static SystemMemorySnapshot captureSystemMemory() {
    final cached = _cachedSystemMemory;
    final capturedAt = _lastSystemMemoryCapture;

    if (cached != null &&
        capturedAt != null &&
        DateTime.now().difference(capturedAt) < _systemMemoryCacheDuration) {
      return cached;
    }

    try {
      final snapshot = probeSystemMemory();
      _cachedSystemMemory = snapshot;
      _lastSystemMemoryCapture = DateTime.now();
      return snapshot;
    } catch (_) {
      final snapshot = const SystemMemorySnapshot.unsupported();
      _cachedSystemMemory = snapshot;
      _lastSystemMemoryCapture = DateTime.now();
      return snapshot;
    }
  }
}

/// The counters of a [MemoryProfiler]'s pools and caches at one moment.
class MemoryProfileSnapshot {
  /// Creates a snapshot.
  const MemoryProfileSnapshot({
    required this.timestamp,
    required this.poolStats,
    required this.cacheStats,
  });

  /// When the snapshot was taken.
  final DateTime timestamp;

  /// Each tracked pool's counters, by name.
  final Map<String, MemoryStats> poolStats;

  /// Each tracked cache's size and budget, by name.
  final Map<String, CacheBudgetStats> cacheStats;

  /// How many pools were tracked.
  int get trackedPools => poolStats.length;

  /// How many caches were tracked.
  int get trackedCaches => cacheStats.length;
}

/// What a [MemoryProfiler] cleanup touched.
class MemoryCleanupResult {
  /// Creates a cleanup result.
  const MemoryCleanupResult({
    required this.releasedPools,
    required this.clearedCaches,
    required this.clearedArenas,
  });

  /// Pools that were released.
  final int releasedPools;

  /// Caches that were cleared.
  final int clearedCaches;

  /// Arenas that were cleared.
  final int clearedArenas;

  /// Whether the cleanup touched anything.
  bool get didWork =>
      releasedPools > 0 || clearedCaches > 0 || clearedArenas > 0;
}
