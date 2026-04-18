import '../cache/budgeted_cache.dart';
import '../cache/cache_budget_stats.dart';
import '../core/memory_stats.dart';
import '../pool/object_pool.dart';
import '../pool/pool_manager.dart';
import 'system_memory_probe.dart';
import 'system_memory_snapshot.dart';

class MemoryProfiler {
  static const Duration _systemMemoryCacheDuration = Duration(seconds: 2);
  static SystemMemorySnapshot? _cachedSystemMemory;
  static DateTime? _lastSystemMemoryCapture;

  final Map<String, ObjectPool<dynamic>> _pools =
      <String, ObjectPool<dynamic>>{};
  final Map<String, BudgetedCache<dynamic, dynamic>> _caches =
      <String, BudgetedCache<dynamic, dynamic>>{};

  void trackPool<T>(String name, ObjectPool<T> pool) {
    _pools[name] = pool;
  }

  void untrackPool(String name) {
    _pools.remove(name);
  }

  void trackCache<K, V>(String name, BudgetedCache<K, V> cache) {
    _caches[name] = cache;
  }

  void untrackCache(String name) {
    _caches.remove(name);
  }

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

  static MemoryCleanupResult cleanupGlobalResources({
    bool clearReleasedObjects = false,
  }) {
    try {
      final manager = PoolManager.instance;
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
    } catch (_) {
      return const MemoryCleanupResult(
        releasedPools: 0,
        clearedCaches: 0,
        clearedArenas: 0,
      );
    }
  }

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

class MemoryProfileSnapshot {
  const MemoryProfileSnapshot({
    required this.timestamp,
    required this.poolStats,
    required this.cacheStats,
  });

  final DateTime timestamp;
  final Map<String, MemoryStats> poolStats;
  final Map<String, CacheBudgetStats> cacheStats;

  int get trackedPools => poolStats.length;
  int get trackedCaches => cacheStats.length;
}

class MemoryCleanupResult {
  const MemoryCleanupResult({
    required this.releasedPools,
    required this.clearedCaches,
    required this.clearedArenas,
  });

  final int releasedPools;
  final int clearedCaches;
  final int clearedArenas;

  bool get didWork =>
      releasedPools > 0 || clearedCaches > 0 || clearedArenas > 0;
}
