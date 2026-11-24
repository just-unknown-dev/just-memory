import 'dart:collection';

import '../core/memory_stats.dart';
import '../scope/memory_scope.dart';
import 'recyclable.dart';

/// A pool that hands out reusable objects of type [T] and takes them back.
///
/// [acquire] returns an object from the pool, creating one with [create] when
/// none is free. [release] gives it back: the pool runs [reset] (or
/// [Recyclable.reset] when no [reset] is set) and keeps the object for the
/// next [acquire], up to `maxSize` free objects.
///
/// The pool tracks objects by identity, so types that override `==` and
/// `hashCode` (vectors, value objects) are safe to pool and may be mutated
/// while they are in use.
///
/// ```dart
/// final bullets = ObjectPool<Bullet>(
///   create: Bullet.new,
///   reset: (b) => b.reset(),
///   initialSize: 64,
///   maxSize: 256,
/// );
/// final bullet = bullets.acquire();
/// // ...
/// bullets.release(bullet);
/// ```
class ObjectPool<T> {
  /// Creates a pool that makes new objects with [create].
  ///
  /// [initialSize] objects are created up front (see [prewarm]). [maxSize]
  /// caps how many free objects the pool keeps; `0` means no cap, and a
  /// negative value throws a [RangeError]. Objects released while the pool
  /// is full are dropped for the garbage collector.
  ObjectPool({
    required this.create,
    this.reset,
    this.onAcquire,
    this.debugLabel,
    int initialSize = 0,
    int maxSize = 0,
  }) : _maxSize = RangeError.checkNotNegative(maxSize, 'maxSize') {
    prewarm(initialSize);
  }

  /// Makes a new object when the pool has none free.
  final T Function() create;

  /// Clears an object's state when it is released. When null, objects that
  /// implement [Recyclable] are reset with [Recyclable.reset].
  final void Function(T value)? reset;

  /// Called with each object as it is handed out by [acquire].
  final void Function(T value)? onAcquire;

  /// A name used in error messages.
  final String? debugLabel;

  final List<T> _available = <T>[];
  final Set<T> _inUse = HashSet<T>.identity();
  final Map<T, Object> _scopedLeases = HashMap<T, Object>.identity();
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

  /// Returns a free object, creating one if the pool is empty.
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

  /// Acquires an object that [scope] releases when it is disposed.
  ///
  /// Releasing the object yourself first is fine: the scope then leaves it
  /// alone, even if the pool has since handed the same object to someone
  /// else.
  T acquireScoped(MemoryScope scope) {
    final value = acquire();
    final lease = Object();
    _scopedLeases[value] = lease;
    scope.own(() {
      if (identical(_scopedLeases[value], lease)) {
        release(value);
      }
    });
    return value;
  }

  /// Gives [value] back to the pool and resets it.
  ///
  /// Releasing an object that is already free does nothing. Releasing an
  /// object this pool never handed out (or forgot through [clear]) throws a
  /// [StateError].
  void release(T value) {
    final wasInUse = _inUse.remove(value);
    if (!wasInUse) {
      if (_isAvailable(value)) {
        return;
      }
      throw StateError(
        debugLabel == null
            ? 'Attempted to release a value that is not managed by this pool.'
            : 'Attempted to release a value that is not managed by pool "$debugLabel".',
      );
    }

    if (_scopedLeases.isNotEmpty) {
      _scopedLeases.remove(value);
    }
    _totalReleased++;

    final reset = this.reset;
    if (reset != null) {
      reset(value);
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

  bool _isAvailable(T value) {
    for (final candidate in _available) {
      if (identical(candidate, value)) return true;
    }
    return false;
  }

  /// Releases every object that is in use.
  ///
  /// Their holders still have references to them, so only call this when
  /// nothing will touch those objects again (a scene teardown, for example).
  void releaseAll() {
    for (final value in _inUse.toList(growable: false)) {
      release(value);
    }
  }

  /// Creates up to [count] free objects ahead of time, stopping at the
  /// pool's `maxSize`. Does nothing when [count] is zero or less.
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

  /// Drops free objects until at most [targetSize] remain. A negative
  /// [targetSize] counts as zero.
  void shrink(int targetSize) {
    final target = targetSize < 0 ? 0 : targetSize;
    while (_available.length > target) {
      _available.removeLast();
    }
  }

  /// Forgets every object, free and in use.
  ///
  /// Objects that were in use are no longer tracked; releasing one later
  /// throws a [StateError].
  void clear() {
    _available.clear();
    _inUse.clear();
    _scopedLeases.clear();
  }

  /// How many free objects the pool holds.
  int get availableCount => _available.length;

  /// How many objects are acquired and not yet released.
  int get inUseCount => _inUse.length;

  /// How many objects [create] has made over the pool's life.
  int get totalCreated => _totalCreated;

  /// Free plus in-use objects.
  int get totalSize => _available.length + _inUse.length;

  /// A snapshot of the pool's counters.
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

/// A fixed ring of objects handed out in turn.
///
/// [next] returns the oldest object, after [onRecycle] has cleared it. There
/// is no release: an object is reused once [size] more have been taken, so
/// only use it for objects whose lifetime is shorter than one turn of the
/// ring (per-frame scratch buffers, trail segments).
class RoundRobinPool<T> {
  /// Creates the ring with [size] objects from [create]. [size] must be
  /// positive; otherwise a [RangeError] is thrown.
  RoundRobinPool({
    required T Function() create,
    required int size,
    this.onRecycle,
  }) : _pool = List<T>.generate(_checkSize(size), (_) => create());

  static int _checkSize(int size) {
    if (size <= 0) {
      throw RangeError.range(size, 1, null, 'size', 'Must be positive');
    }
    return size;
  }

  final List<T> _pool;

  /// Called with each object as [next] hands it out again.
  final void Function(T object)? onRecycle;
  int _index = 0;

  /// Returns the next object in the ring.
  T next() {
    final object = _pool[_index];
    onRecycle?.call(object);
    _index = (_index + 1) % _pool.length;
    return object;
  }

  /// The object at [index], wrapped around the ring.
  T at(int index) => _pool[index % _pool.length];

  /// How many objects the ring holds.
  int get size => _pool.length;

  /// The index [next] hands out next.
  int get currentIndex => _index;

  /// Starts the ring again from its first object.
  void reset() => _index = 0;

  /// Calls [callback] with every object in the ring.
  void forEach(void Function(T object) callback) {
    for (final object in _pool) {
      callback(object);
    }
  }
}

/// A pool that, when empty, can take back its lowest-priority object.
///
/// With [getPriority] set, [acquire] reclaims the in-use object with the
/// lowest priority below `minPriority` instead of creating a new one: the
/// usual voice-stealing scheme for sounds or particles. The reclaimed
/// object's previous holder still has a reference to it, so it should listen
/// to [onReclaim] (or check the object's state) before using it again, and
/// must not release it.
///
/// Objects are tracked by identity.
class PriorityPool<T> {
  /// Creates a pool that makes new objects with [create], [initialSize] of
  /// them up front.
  PriorityPool({
    required this.create,
    this.reset,
    this.getPriority,
    this.onReclaim,
    int initialSize = 0,
  }) {
    for (var i = 0; i < initialSize; i++) {
      _available.add(create());
    }
  }

  /// Makes a new object when none is free and none can be reclaimed.
  final T Function() create;

  /// Clears an object's state when it is released or reclaimed.
  final void Function(T object)? reset;

  /// The priority of an in-use object; objects below `minPriority` can be
  /// reclaimed by [acquire].
  final int Function(T object)? getPriority;

  /// Called with an in-use object just before [acquire] reclaims it, while
  /// it still holds its previous holder's state.
  final void Function(T object)? onReclaim;

  final List<T> _available = <T>[];
  final Set<T> _inUse = HashSet<T>.identity();

  /// Returns a free object, else reclaims the lowest-priority in-use object
  /// whose priority is below [minPriority], else creates a new one.
  T acquire({int minPriority = 0}) {
    if (_available.isNotEmpty) {
      final object = _available.removeLast();
      _inUse.add(object);
      return object;
    }

    final getPriority = this.getPriority;
    if (_inUse.isNotEmpty && getPriority != null) {
      T? lowest;
      var found = false;
      var lowestPriority = minPriority;

      for (final object in _inUse) {
        final priority = getPriority(object);
        if (priority < lowestPriority) {
          lowest = object;
          found = true;
          lowestPriority = priority;
        }
      }

      if (found) {
        final object = lowest as T;
        onReclaim?.call(object);
        reset?.call(object);
        return object;
      }
    }

    final object = create();
    _inUse.add(object);
    return object;
  }

  /// Gives [object] back to the pool and resets it. Objects the pool does
  /// not consider in use are ignored.
  void release(T object) {
    if (_inUse.remove(object)) {
      reset?.call(object);
      _available.add(object);
    }
  }

  /// How many free objects the pool holds.
  int get availableCount => _available.length;

  /// How many objects are in use.
  int get inUseCount => _inUse.length;
}
