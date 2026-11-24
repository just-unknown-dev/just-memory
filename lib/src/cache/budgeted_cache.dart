import 'dart:collection';

import 'cache_budget_stats.dart';

/// Returns what an entry costs against a [BudgetedCache]'s budget (bytes,
/// pixels, or any unit). Must not be negative.
typedef CostEstimator<K, V> = int Function(K key, V value);

/// Called with an entry that has left a [BudgetedCache].
typedef EvictionCallback<K, V> = void Function(K key, V value);

/// A least-recently-used cache bounded by total cost rather than entry count.
///
/// Each entry's cost comes from [estimateCost]. When the total goes over
/// [maxCost], the least recently used entries are evicted until it fits.
/// Reading an entry with `[]` marks it as recently used.
///
/// Every value that leaves the cache, other than through [remove] (which
/// returns it), is passed to [onEvict]: budget evictions, a value replaced by
/// a different one under the same key, a value too large to fit at all, and
/// everything dropped by [clear]. That makes [onEvict] the one place to free
/// cached resources.
class BudgetedCache<K, V> {
  /// Creates a cache that holds at most [maxCost] worth of entries.
  BudgetedCache({
    required this.maxCost,
    required this.estimateCost,
    this.onEvict,
  }) : assert(maxCost > 0, 'maxCost must be positive');

  /// The budget the entries' costs must fit in.
  final int maxCost;

  /// Returns an entry's cost.
  final CostEstimator<K, V> estimateCost;

  /// Called with each value that leaves the cache (see [BudgetedCache]).
  final EvictionCallback<K, V>? onEvict;

  final LinkedHashMap<K, _CacheEntry<V>> _entries =
      LinkedHashMap<K, _CacheEntry<V>>();
  int _currentCost = 0;

  /// The total cost of the entries held.
  int get currentCost => _currentCost;

  /// How many entries are held.
  int get length => _entries.length;

  /// Whether the cache holds no entries.
  bool get isEmpty => _entries.isEmpty;

  /// A snapshot of the cache's size and budget.
  CacheBudgetStats get stats => CacheBudgetStats(
    entryCount: _entries.length,
    currentCost: _currentCost,
    maxCost: maxCost,
  );

  /// Whether [key] is cached. Does not count as a use.
  bool containsKey(K key) => _entries.containsKey(key);

  /// The value for [key], or null. Marks the entry as recently used.
  V? operator [](K key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    return entry.value;
  }

  /// Caches [value] under [key] as the most recently used entry, then evicts
  /// the least recently used entries until the budget fits.
  ///
  /// A different value already cached under [key] goes to [onEvict]. A value
  /// whose cost alone is over [maxCost] is not cached: it goes straight to
  /// [onEvict] and the other entries stay. Throws an [ArgumentError] if
  /// [estimateCost] returns a negative cost.
  void operator []=(K key, V value) {
    final cost = estimateCost(key, value);
    if (cost < 0) {
      throw ArgumentError.value(cost, 'estimateCost', 'Must not be negative');
    }

    final previous = _entries.remove(key);
    if (previous != null) {
      _currentCost -= previous.cost;
      if (!identical(previous.value, value)) {
        onEvict?.call(key, previous.value);
      }
    }

    if (cost > maxCost) {
      onEvict?.call(key, value);
      return;
    }

    _entries[key] = _CacheEntry<V>(value, cost);
    _currentCost += cost;
    _evictIfNeeded();
  }

  /// Removes [key] and returns its value (without calling [onEvict]), or
  /// null if it was not cached.
  V? remove(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _currentCost -= entry.cost;
    return entry.value;
  }

  /// Empties the cache, passing every entry to [onEvict], least recently
  /// used first. The cache is already empty when [onEvict] runs.
  void clear() {
    final onEvict = this.onEvict;
    if (onEvict == null || _entries.isEmpty) {
      _entries.clear();
      _currentCost = 0;
      return;
    }

    final evicted = _entries.entries.toList(growable: false);
    _entries.clear();
    _currentCost = 0;
    for (final entry in evicted) {
      onEvict(entry.key, entry.value.value);
    }
  }

  void _evictIfNeeded() {
    while (_currentCost > maxCost && _entries.isNotEmpty) {
      final oldestKey = _entries.keys.first;
      final entry = _entries.remove(oldestKey)!;
      _currentCost -= entry.cost;
      onEvict?.call(oldestKey, entry.value);
    }
  }
}

class _CacheEntry<V> {
  const _CacheEntry(this.value, this.cost);

  final V value;
  final int cost;
}
