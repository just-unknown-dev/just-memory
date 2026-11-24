import 'dart:async';

import '../scope/memory_scope.dart';

/// Loads the value for [key]; may be synchronous or asynchronous.
typedef ResourceLoader<K, V> = FutureOr<V> Function(K key);

/// Frees a value once nothing holds it any more.
typedef ResourceDisposer<V> = FutureOr<void> Function(V value);

/// Shares loaded values between holders and frees each one after its last
/// holder lets go.
///
/// [acquire] loads the value for a key once (concurrent calls for the same
/// key share one load) and returns a [ResourceHandle]. Each handle counts as
/// one reference; when the last handle for a key is released, the value is
/// passed to the disposer and the next [acquire] loads it again.
///
/// ```dart
/// final textures = RefCountedRegistry<String, Texture>(
///   loader: loadTexture,
///   disposer: (texture) => texture.dispose(),
/// );
/// final handle = await textures.acquire('hero.png', scope: sceneScope);
/// draw(handle.value);
/// ```
class RefCountedRegistry<K, V> {
  /// Creates a registry that loads values with [loader] and frees them with
  /// [disposer].
  RefCountedRegistry({
    required ResourceLoader<K, V> loader,
    ResourceDisposer<V>? disposer,
  }) : _loader = loader,
       _disposer = disposer;

  final ResourceLoader<K, V> _loader;
  final ResourceDisposer<V>? _disposer;

  final Map<K, _ResourceEntry<V>> _entries = <K, _ResourceEntry<V>>{};
  final Map<K, _ResourceEntry<V>> _loading = <K, _ResourceEntry<V>>{};

  // Bumped by dispose(), so loads that finish afterwards stay out of
  // _entries.
  int _generation = 0;

  /// Returns a handle to the value for [key], loading it if needed.
  ///
  /// The reference is counted as soon as this is called, so a value cannot
  /// be freed between its load finishing and this call returning. With a
  /// [scope], the handle is released when the scope is disposed (use
  /// [MemoryScope.disposeAsync] to wait for the disposer).
  ///
  /// If the load fails, the error is rethrown to every caller waiting on it
  /// and the next call loads again.
  Future<ResourceHandle<K, V>> acquire(K key, {MemoryScope? scope}) async {
    final entry = _entries[key] ?? _loading[key] ?? _startLoad(key);
    entry.refCount++;
    if (!entry.isLoaded) {
      try {
        await entry.ready;
      } catch (_) {
        entry.refCount--;
        rethrow;
      }
    }

    final handle = ResourceHandle<K, V>._(this, key, entry);
    scope?.own(handle.release);
    return handle;
  }

  _ResourceEntry<V> _startLoad(K key) {
    final entry = _ResourceEntry<V>();
    _loading[key] = entry;
    entry.ready = _load(key, entry, _generation);
    return entry;
  }

  Future<void> _load(K key, _ResourceEntry<V> entry, int generation) async {
    try {
      entry.value = await _loader(key);
      entry.isLoaded = true;
      if (generation == _generation) {
        _entries[key] = entry;
      }
    } finally {
      if (identical(_loading[key], entry)) {
        _loading.remove(key);
      }
    }
  }

  /// How many handles hold the loaded value for [key]; `0` when it is not
  /// loaded.
  int refCountOf(K key) => _entries[key]?.refCount ?? 0;

  /// Whether a value for [key] is loaded and held.
  bool containsKey(K key) => _entries.containsKey(key);

  /// Whether a value for [key] is being loaded.
  bool isLoading(K key) => _loading.containsKey(key);

  Future<void> _release(K key, _ResourceEntry<V> entry) async {
    // Zero means dispose() already freed this value.
    if (entry.refCount <= 0) return;

    entry.refCount--;
    if (entry.refCount > 0) {
      return;
    }

    if (identical(_entries[key], entry)) {
      _entries.remove(key);
    }
    await _disposer?.call(entry.value);
  }

  /// Frees every loaded value now, whatever its reference count.
  ///
  /// Handles still held become inert: releasing them does nothing, even if
  /// the same key has been loaded again since. Loads still running finish
  /// for their callers, but their values are not added to the registry;
  /// they are freed when their own handles are released. The registry can
  /// be used again afterwards.
  Future<void> dispose() async {
    _generation++;
    _loading.clear();
    final entries = _entries.values.toList(growable: false);
    _entries.clear();
    for (final entry in entries) {
      entry.refCount = 0;
      await _disposer?.call(entry.value);
    }
  }
}

/// One reference to a value held by a [RefCountedRegistry].
class ResourceHandle<K, V> {
  ResourceHandle._(this._registry, this.key, this._entry);

  final RefCountedRegistry<K, V> _registry;
  final _ResourceEntry<V> _entry;

  /// The key the value was loaded for.
  final K key;
  bool _released = false;

  /// The shared value.
  V get value => _entry.value;

  /// How many handles hold this value; `0` once it has been freed.
  int get refCount => _entry.refCount;

  /// Whether this handle has been released.
  bool get isReleased => _released;

  /// Gives up this reference; the value is freed when it was the last one.
  /// Calling it again does nothing.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _registry._release(key, _entry);
  }
}

class _ResourceEntry<V> {
  late V value;
  late Future<void> ready;
  bool isLoaded = false;
  int refCount = 0;
}
