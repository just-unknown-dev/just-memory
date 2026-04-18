import 'dart:async';

import '../scope/memory_scope.dart';

typedef ResourceLoader<K, V> = FutureOr<V> Function(K key);
typedef ResourceDisposer<V> = FutureOr<void> Function(V value);

class RefCountedRegistry<K, V> {
  RefCountedRegistry({
    required ResourceLoader<K, V> loader,
    ResourceDisposer<V>? disposer,
  }) : _loader = loader,
       _disposer = disposer;

  final ResourceLoader<K, V> _loader;
  final ResourceDisposer<V>? _disposer;

  final Map<K, _ResourceEntry<V>> _entries = <K, _ResourceEntry<V>>{};
  final Map<K, Future<V>> _pendingLoads = <K, Future<V>>{};

  Future<ResourceHandle<K, V>> acquire(K key, {MemoryScope? scope}) async {
    final entry = await _getOrLoad(key);
    entry.refCount++;

    final handle = ResourceHandle<K, V>._(this, key, entry);
    if (scope != null) {
      scope.own(handle.release);
    }
    return handle;
  }

  Future<_ResourceEntry<V>> _getOrLoad(K key) async {
    final existing = _entries[key];
    if (existing != null) {
      return existing;
    }

    final pending = _pendingLoads[key];
    if (pending != null) {
      final value = await pending;
      return _entries[key] ?? _ResourceEntry<V>(value);
    }

    final future = Future<V>.sync(() => _loader(key));
    _pendingLoads[key] = future;

    try {
      final value = await future;
      final entry = _ResourceEntry<V>(value);
      _entries[key] = entry;
      return entry;
    } finally {
      _pendingLoads.remove(key);
    }
  }

  int refCountOf(K key) => _entries[key]?.refCount ?? 0;

  bool containsKey(K key) => _entries.containsKey(key);

  Future<void> _release(K key) async {
    final entry = _entries[key];
    if (entry == null) return;

    entry.refCount--;
    if (entry.refCount > 0) {
      return;
    }

    _entries.remove(key);
    await _disposer?.call(entry.value);
  }

  Future<void> dispose() async {
    final keys = _entries.keys.toList(growable: false);
    for (final key in keys) {
      final entry = _entries.remove(key);
      if (entry != null) {
        await _disposer?.call(entry.value);
      }
    }
  }
}

class ResourceHandle<K, V> {
  ResourceHandle._(this._registry, this.key, this._entry);

  final RefCountedRegistry<K, V> _registry;
  final _ResourceEntry<V> _entry;

  final K key;
  bool _released = false;

  V get value => _entry.value;
  int get refCount => _entry.refCount;
  bool get isReleased => _released;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _registry._release(key);
  }
}

class _ResourceEntry<V> {
  _ResourceEntry(this.value);

  final V value;
  int refCount = 0;
}
