import '../arena/memory_arena.dart';
import 'object_pool.dart';

/// A process-wide registry of named [ObjectPool]s, [MemoryArena]s and
/// [RoundRobinPool]s, so systems can share them by name.
///
/// Registering does not transfer ownership, but [clearAll] and [dispose]
/// clear every registered pool and arena, which forgets objects that are
/// still in use. Use [instance] for the shared registry and [resetInstance]
/// between tests.
class PoolManager {
  PoolManager._();

  static PoolManager? _instance;

  /// The shared registry, created on first use.
  static PoolManager get instance => _instance ??= PoolManager._();

  /// Disposes the shared registry; the next [instance] is a new, empty one.
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

  /// Registers [pool] under [name]; throws a [StateError] if the name is
  /// taken.
  void registerPool<T>(String name, ObjectPool<T> pool) {
    _checkDisposed();
    if (_pools.containsKey(name)) {
      throw StateError('Pool "$name" is already registered');
    }
    _pools[name] = pool;
  }

  /// The pool registered under [name]; throws a [StateError] if there is
  /// none.
  ObjectPool<T> pool<T>(String name) {
    _checkDisposed();
    final pool = _pools[name];
    if (pool == null) {
      throw StateError('Pool "$name" is not registered');
    }
    return pool as ObjectPool<T>;
  }

  /// The pool registered under [name], or null.
  ObjectPool<T>? tryPool<T>(String name) {
    if (_isDisposed) return null;
    return _pools[name] as ObjectPool<T>?;
  }

  /// Whether a pool is registered under [name].
  bool hasPool(String name) => _pools.containsKey(name);

  /// Removes the pool registered under [name], leaving the pool itself as
  /// it is.
  void unregisterPool(String name) {
    _pools.remove(name);
  }

  /// Registers [arena] under [name]; throws a [StateError] if the name is
  /// taken.
  void registerArena(String name, MemoryArena arena) {
    _checkDisposed();
    if (_arenas.containsKey(name)) {
      throw StateError('Arena "$name" is already registered');
    }
    _arenas[name] = arena;
  }

  /// Creates a [MemoryArena] and registers it under [name].
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

  /// The arena registered under [name]; throws a [StateError] if there is
  /// none.
  MemoryArena arena(String name) {
    _checkDisposed();
    final arena = _arenas[name];
    if (arena == null) {
      throw StateError('Arena "$name" is not registered');
    }
    return arena;
  }

  /// The arena registered under [name], or null.
  MemoryArena? tryArena(String name) {
    if (_isDisposed) return null;
    return _arenas[name];
  }

  /// Whether an arena is registered under [name].
  bool hasArena(String name) => _arenas.containsKey(name);

  /// Removes the arena registered under [name], leaving the arena itself as
  /// it is.
  void unregisterArena(String name) {
    _arenas.remove(name);
  }

  /// Registers [pool] under [name]; throws a [StateError] if the name is
  /// taken.
  void registerRoundRobin<T>(String name, RoundRobinPool<T> pool) {
    _checkDisposed();
    if (_roundRobinPools.containsKey(name)) {
      throw StateError('RoundRobinPool "$name" is already registered');
    }
    _roundRobinPools[name] = pool;
  }

  /// Creates a [RoundRobinPool] and registers it under [name].
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

  /// The round-robin pool registered under [name]; throws a [StateError] if
  /// there is none.
  RoundRobinPool<T> roundRobin<T>(String name) {
    _checkDisposed();
    final pool = _roundRobinPools[name];
    if (pool == null) {
      throw StateError('RoundRobinPool "$name" is not registered');
    }
    return pool as RoundRobinPool<T>;
  }

  /// The counts of every registered object pool, by name.
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

  /// The occupancy of every registered arena, by name.
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

  /// Calls [ObjectPool.releaseAll] on every registered pool.
  void releaseAllPools() {
    for (final pool in _pools.values) {
      pool.releaseAll();
    }
  }

  /// Calls [MemoryArena.clear] on every registered arena.
  void clearAllArenas() {
    for (final arena in _arenas.values) {
      arena.clear();
    }
  }

  /// Clears every registered pool and arena and unregisters everything.
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

  /// Clears everything (see [clearAll]); afterwards lookups and
  /// registrations throw a [StateError].
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _clear();
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _isDisposed;
}

/// The counts of one [ObjectPool], as reported by
/// [PoolManager.getPoolStats].
class PoolStats {
  /// Creates a snapshot of pool counts.
  const PoolStats({
    required this.available,
    required this.inUse,
    required this.totalCreated,
  });

  /// Free objects.
  final int available;

  /// Objects in use.
  final int inUse;

  /// Objects created over the pool's life.
  final int totalCreated;

  /// Free plus in-use objects.
  int get total => available + inUse;
}

/// The occupancy of one [MemoryArena], as reported by
/// [PoolManager.getArenaStats].
class ArenaStats {
  /// Creates a snapshot of arena occupancy.
  const ArenaStats({
    required this.capacity,
    required this.allocated,
    required this.available,
  });

  /// Total slots.
  final int capacity;

  /// Allocated slots.
  final int allocated;

  /// Free slots.
  final int available;

  /// Allocated slots as a percentage of [capacity].
  double get utilizationPercent =>
      capacity > 0 ? (allocated / capacity) * 100 : 0;
}
