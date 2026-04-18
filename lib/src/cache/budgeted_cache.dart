import 'dart:collection';

import 'cache_budget_stats.dart';

typedef CostEstimator<K, V> = int Function(K key, V value);
typedef EvictionCallback<K, V> = void Function(K key, V value);

class BudgetedCache<K, V> {
  BudgetedCache({
    required this.maxCost,
    required this.estimateCost,
    this.onEvict,
  }) : assert(maxCost > 0, 'maxCost must be positive');

  final int maxCost;
  final CostEstimator<K, V> estimateCost;
  final EvictionCallback<K, V>? onEvict;

  final LinkedHashMap<K, _CacheEntry<V>> _entries =
      LinkedHashMap<K, _CacheEntry<V>>();
  int _currentCost = 0;

  int get currentCost => _currentCost;
  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  CacheBudgetStats get stats => CacheBudgetStats(
    entryCount: _entries.length,
    currentCost: _currentCost,
    maxCost: maxCost,
  );

  bool containsKey(K key) => _entries.containsKey(key);

  V? operator [](K key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    return entry.value;
  }

  void operator []=(K key, V value) {
    final cost = estimateCost(key, value);
    final previous = _entries.remove(key);
    if (previous != null) {
      _currentCost -= previous.cost;
    }

    _entries[key] = _CacheEntry<V>(value, cost);
    _currentCost += cost;
    _evictIfNeeded();
  }

  V? remove(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _currentCost -= entry.cost;
    return entry.value;
  }

  void clear() {
    _entries.clear();
    _currentCost = 0;
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
