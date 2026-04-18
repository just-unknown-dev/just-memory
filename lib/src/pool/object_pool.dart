import '../core/memory_stats.dart';
import '../scope/memory_scope.dart';
import 'recyclable.dart';

class ObjectPool<T> {
  ObjectPool({
    required this.create,
    this.reset,
    this.onAcquire,
    this.debugLabel,
    int initialSize = 0,
    int maxSize = 0,
  }) : _maxSize = maxSize {
    prewarm(initialSize);
  }

  final T Function() create;
  final void Function(T value)? reset;
  final void Function(T value)? onAcquire;
  final String? debugLabel;

  final List<T> _available = <T>[];
  final Set<T> _inUse = <T>{};
  final int _maxSize;

  int _totalCreated = 0;
  int _totalAcquired = 0;
  int _totalReleased = 0;
  int _peakInUse = 0;
  int _peakAvailable = 0;

  T _createNew() {
    _totalCreated++;
    return create();
  }

  T acquire() {
    final value = _available.isNotEmpty
        ? _available.removeLast()
        : _createNew();
    _inUse.add(value);
    _totalAcquired++;
    if (_inUse.length > _peakInUse) {
      _peakInUse = _inUse.length;
    }
    onAcquire?.call(value);
    return value;
  }

  T acquireScoped(MemoryScope scope) {
    final value = acquire();
    scope.own(() => release(value));
    return value;
  }

  void release(T value) {
    final wasInUse = _inUse.remove(value);
    if (!wasInUse) {
      if (_available.contains(value)) {
        return;
      }
      throw StateError(
        debugLabel == null
            ? 'Attempted to release a value that is not managed by this pool.'
            : 'Attempted to release a value that is not managed by pool "$debugLabel".',
      );
    }

    _totalReleased++;

    if (reset != null) {
      reset!.call(value);
    } else if (value is Recyclable) {
      value.reset();
    }

    if (_maxSize == 0 || _available.length < _maxSize) {
      _available.add(value);
      if (_available.length > _peakAvailable) {
        _peakAvailable = _available.length;
      }
    }
  }

  void releaseAll() {
    for (final value in _inUse.toList(growable: false)) {
      release(value);
    }
  }

  void prewarm(int count) {
    if (count <= 0) return;
    for (var i = 0; i < count; i++) {
      if (_maxSize != 0 && _available.length >= _maxSize) {
        break;
      }
      _available.add(_createNew());
    }
    if (_available.length > _peakAvailable) {
      _peakAvailable = _available.length;
    }
  }

  void shrink(int targetSize) {
    while (_available.length > targetSize) {
      _available.removeLast();
    }
  }

  void clear() {
    _available.clear();
    _inUse.clear();
  }

  int get availableCount => _available.length;
  int get inUseCount => _inUse.length;
  int get totalCreated => _totalCreated;
  int get totalSize => _available.length + _inUse.length;

  MemoryStats get stats => MemoryStats(
    totalCreated: _totalCreated,
    totalAcquired: _totalAcquired,
    totalReleased: _totalReleased,
    inUse: _inUse.length,
    available: _available.length,
    peakInUse: _peakInUse,
    peakAvailable: _peakAvailable,
  );
}

class RoundRobinPool<T> {
  RoundRobinPool({
    required T Function() create,
    required int size,
    this.onRecycle,
  }) : _pool = List<T>.generate(size, (_) => create());

  final List<T> _pool;
  final void Function(T object)? onRecycle;
  int _index = 0;

  T next() {
    final object = _pool[_index];
    onRecycle?.call(object);
    _index = (_index + 1) % _pool.length;
    return object;
  }

  T at(int index) => _pool[index % _pool.length];

  int get size => _pool.length;
  int get currentIndex => _index;

  void reset() => _index = 0;

  void forEach(void Function(T object) callback) {
    for (final object in _pool) {
      callback(object);
    }
  }
}

class PriorityPool<T> {
  PriorityPool({
    required this.create,
    this.reset,
    this.getPriority,
    int initialSize = 0,
  }) {
    for (var i = 0; i < initialSize; i++) {
      _available.add(create());
    }
  }

  final T Function() create;
  final void Function(T object)? reset;
  final int Function(T object)? getPriority;

  final List<T> _available = <T>[];
  final Set<T> _inUse = <T>{};

  T acquire({int minPriority = 0}) {
    if (_available.isNotEmpty) {
      final object = _available.removeLast();
      _inUse.add(object);
      return object;
    }

    if (_inUse.isNotEmpty && getPriority != null) {
      T? lowest;
      var lowestPriority = minPriority;

      for (final object in _inUse) {
        final priority = getPriority!(object);
        if (priority < lowestPriority) {
          lowest = object;
          lowestPriority = priority;
        }
      }

      if (lowest != null) {
        _inUse.remove(lowest);
        reset?.call(lowest);
        _inUse.add(lowest);
        return lowest;
      }
    }

    final object = create();
    _inUse.add(object);
    return object;
  }

  void release(T object) {
    if (_inUse.remove(object)) {
      reset?.call(object);
      _available.add(object);
    }
  }

  int get availableCount => _available.length;
  int get inUseCount => _inUse.length;
}
