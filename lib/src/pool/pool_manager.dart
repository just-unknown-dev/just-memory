import '../arena/memory_arena.dart';
import 'object_pool.dart';

class PoolManager {
  PoolManager._();

  static PoolManager? _instance;
  static PoolManager get instance => _instance ??= PoolManager._();

  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  final Map<String, ObjectPool<dynamic>> _pools =
      <String, ObjectPool<dynamic>>{};
  final Map<String, MemoryArena> _arenas = <String, MemoryArena>{};
  final Map<String, RoundRobinPool<dynamic>> _roundRobinPools =
      <String, RoundRobinPool<dynamic>>{};

  bool _isDisposed = false;

  void registerPool<T>(String name, ObjectPool<T> pool) {
    _checkDisposed();
    if (_pools.containsKey(name)) {
      throw StateError('Pool "$name" is already registered');
    }
    _pools[name] = pool;
  }

  ObjectPool<T> pool<T>(String name) {
    _checkDisposed();
    final pool = _pools[name];
    if (pool == null) {
      throw StateError('Pool "$name" is not registered');
    }
    return pool as ObjectPool<T>;
  }

  ObjectPool<T>? tryPool<T>(String name) {
    if (_isDisposed) return null;
    return _pools[name] as ObjectPool<T>?;
  }

  bool hasPool(String name) => _pools.containsKey(name);

  void unregisterPool(String name) {
    _pools.remove(name);
  }

  void registerArena(String name, MemoryArena arena) {
    _checkDisposed();
    if (_arenas.containsKey(name)) {
      throw StateError('Arena "$name" is already registered');
    }
    _arenas[name] = arena;
  }

  MemoryArena createArena(
    String name, {
    required int capacity,
    int componentsPerEntity = 8,
  }) {
    final arena = MemoryArena(
      capacity: capacity,
      componentsPerEntity: componentsPerEntity,
    );
    registerArena(name, arena);
    return arena;
  }

  MemoryArena arena(String name) {
    _checkDisposed();
    final arena = _arenas[name];
    if (arena == null) {
      throw StateError('Arena "$name" is not registered');
    }
    return arena;
  }

  MemoryArena? tryArena(String name) {
    if (_isDisposed) return null;
    return _arenas[name];
  }

  bool hasArena(String name) => _arenas.containsKey(name);

  void unregisterArena(String name) {
    _arenas.remove(name);
  }

  void registerRoundRobin<T>(String name, RoundRobinPool<T> pool) {
    _checkDisposed();
    if (_roundRobinPools.containsKey(name)) {
      throw StateError('RoundRobinPool "$name" is already registered');
    }
    _roundRobinPools[name] = pool;
  }

  RoundRobinPool<T> createRoundRobin<T>(
    String name, {
    required T Function() create,
    required int size,
    void Function(T)? onRecycle,
  }) {
    final pool = RoundRobinPool<T>(
      create: create,
      size: size,
      onRecycle: onRecycle,
    );
    registerRoundRobin(name, pool);
    return pool;
  }

  RoundRobinPool<T> roundRobin<T>(String name) {
    _checkDisposed();
    final pool = _roundRobinPools[name];
    if (pool == null) {
      throw StateError('RoundRobinPool "$name" is not registered');
    }
    return pool as RoundRobinPool<T>;
  }

  Map<String, PoolStats> getPoolStats() {
    final stats = <String, PoolStats>{};
    for (final entry in _pools.entries) {
      stats[entry.key] = PoolStats(
        available: entry.value.availableCount,
        inUse: entry.value.inUseCount,
        totalCreated: entry.value.totalCreated,
      );
    }
    return stats;
  }

  Map<String, ArenaStats> getArenaStats() {
    final stats = <String, ArenaStats>{};
    for (final entry in _arenas.entries) {
      stats[entry.key] = ArenaStats(
        capacity: entry.value.capacity,
        allocated: entry.value.allocatedCount,
        available: entry.value.availableCount,
      );
    }
    return stats;
  }

  void releaseAllPools() {
    for (final pool in _pools.values) {
      pool.releaseAll();
    }
  }

  void clearAllArenas() {
    for (final arena in _arenas.values) {
      arena.clear();
    }
  }

  void clearAll() => _clear();

  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('PoolManager has been disposed');
    }
  }

  void _clear() {
    for (final pool in _pools.values) {
      pool.clear();
    }
    _pools.clear();

    for (final arena in _arenas.values) {
      arena.clear();
    }
    _arenas.clear();

    _roundRobinPools.clear();
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _clear();
  }

  bool get isDisposed => _isDisposed;
}

class PoolStats {
  const PoolStats({
    required this.available,
    required this.inUse,
    required this.totalCreated,
  });

  final int available;
  final int inUse;
  final int totalCreated;

  int get total => available + inUse;
}

class ArenaStats {
  const ArenaStats({
    required this.capacity,
    required this.allocated,
    required this.available,
  });

  final int capacity;
  final int allocated;
  final int available;

  double get utilizationPercent =>
      capacity > 0 ? (allocated / capacity) * 100 : 0;
}
