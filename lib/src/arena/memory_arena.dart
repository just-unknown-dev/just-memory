import 'dart:typed_data';

/// Fixed-size, contiguous numeric storage for entity-like state.
///
/// The arena holds [capacity] slots of `componentsPerEntity` doubles each
/// in one [Float64List]. [allocate] hands out a free slot (zeroed) and
/// [free] returns it. Values are read and written by slot and component
/// offset, so update loops touch one flat array instead of many objects.
///
/// The named accessors ([setPosition], [setVelocity], [applyVelocity], ...)
/// use the transform layout given by the `offset*` constants, which needs at
/// least 8 components per slot. With fewer components, use only
/// [getValue] and [setValue] with offsets below `componentsPerEntity`.
///
/// Accessors do not check that a slot is allocated; in debug builds they
/// assert that the slot and offset are in range, so a short layout cannot
/// silently write into the next slot.
class MemoryArena {
  /// Creates an arena of [capacity] slots with [componentsPerEntity] doubles
  /// each.
  MemoryArena({required int capacity, int componentsPerEntity = 8})
    : assert(capacity >= 0, 'capacity must not be negative'),
      assert(componentsPerEntity > 0, 'componentsPerEntity must be positive'),
      _capacity = capacity,
      _componentsPerEntity = componentsPerEntity,
      _data = Float64List(capacity * componentsPerEntity),
      _allocated = List<bool>.filled(capacity, false),
      _freeList = List<int>.generate(capacity, (i) => capacity - 1 - i);

  final int _capacity;
  final int _componentsPerEntity;
  final Float64List _data;
  final List<bool> _allocated;
  final List<int> _freeList;

  int _allocatedCount = 0;
  int _freeListTop = 0;

  /// Offset of the x position in the transform layout.
  static const int offsetX = 0;

  /// Offset of the y position in the transform layout.
  static const int offsetY = 1;

  /// Offset of the rotation in the transform layout.
  static const int offsetRotation = 2;

  /// Offset of the x scale in the transform layout.
  static const int offsetScaleX = 3;

  /// Offset of the y scale in the transform layout.
  static const int offsetScaleY = 4;

  /// Offset of the x velocity in the transform layout.
  static const int offsetVelocityX = 5;

  /// Offset of the y velocity in the transform layout.
  static const int offsetVelocityY = 6;

  /// Offset of the spare value in the transform layout.
  static const int offsetExtra = 7;

  /// How many slots the arena holds.
  int get capacity => _capacity;

  /// How many doubles each slot holds.
  int get componentsPerEntity => _componentsPerEntity;

  /// How many slots are allocated.
  int get allocatedCount => _allocatedCount;

  /// How many slots are free.
  int get availableCount => _capacity - _allocatedCount;

  /// Whether every slot is allocated.
  bool get isFull => _allocatedCount >= _capacity;

  /// The backing array: slot `s`, component `c` is at
  /// `s * componentsPerEntity + c`.
  Float64List get rawData => _data;

  /// Allocates a free slot, zeroes it and returns its index, or `-1` when
  /// the arena is full.
  int allocate() {
    if (_freeListTop >= _capacity) {
      return -1;
    }

    final slot = _freeList[_freeListTop++];
    _allocated[slot] = true;
    _allocatedCount++;

    final base = slot * _componentsPerEntity;
    for (var i = 0; i < _componentsPerEntity; i++) {
      _data[base + i] = 0.0;
    }
    return slot;
  }

  /// Frees [slot]. Freeing a slot that is not allocated does nothing.
  void free(int slot) {
    if (slot < 0 || slot >= _capacity || !_allocated[slot]) {
      return;
    }

    _allocated[slot] = false;
    _freeList[--_freeListTop] = slot;
    _allocatedCount--;
  }

  /// Whether [slot] is allocated.
  bool isAllocated(int slot) {
    return slot >= 0 && slot < _capacity && _allocated[slot];
  }

  @pragma('vm:prefer-inline')
  int _index(int slot, int offset) {
    assert(
      slot >= 0 && slot < _capacity,
      'slot $slot is outside the arena (capacity $_capacity)',
    );
    assert(
      offset >= 0 && offset < _componentsPerEntity,
      'offset $offset is outside a slot of $_componentsPerEntity components',
    );
    return slot * _componentsPerEntity + offset;
  }

  /// The x position of [slot].
  double getX(int slot) => _data[_index(slot, offsetX)];

  /// The y position of [slot].
  double getY(int slot) => _data[_index(slot, offsetY)];

  /// Sets the position of [slot].
  void setPosition(int slot, double x, double y) {
    _data[_index(slot, offsetX)] = x;
    _data[_index(slot, offsetY)] = y;
  }

  /// Moves [slot] by ([dx], [dy]).
  void translate(int slot, double dx, double dy) {
    _data[_index(slot, offsetX)] += dx;
    _data[_index(slot, offsetY)] += dy;
  }

  /// The rotation of [slot].
  double getRotation(int slot) => _data[_index(slot, offsetRotation)];

  /// Sets the rotation of [slot].
  void setRotation(int slot, double rotation) {
    _data[_index(slot, offsetRotation)] = rotation;
  }

  /// Adds [angle] to the rotation of [slot].
  void rotate(int slot, double angle) {
    _data[_index(slot, offsetRotation)] += angle;
  }

  /// The x scale of [slot].
  double getScaleX(int slot) => _data[_index(slot, offsetScaleX)];

  /// The y scale of [slot].
  double getScaleY(int slot) => _data[_index(slot, offsetScaleY)];

  /// Sets both scales of [slot] to [scale].
  void setScale(int slot, double scale) {
    _data[_index(slot, offsetScaleX)] = scale;
    _data[_index(slot, offsetScaleY)] = scale;
  }

  /// Sets the x and y scales of [slot].
  void setScaleXY(int slot, double scaleX, double scaleY) {
    _data[_index(slot, offsetScaleX)] = scaleX;
    _data[_index(slot, offsetScaleY)] = scaleY;
  }

  /// The x velocity of [slot].
  double getVelocityX(int slot) => _data[_index(slot, offsetVelocityX)];

  /// The y velocity of [slot].
  double getVelocityY(int slot) => _data[_index(slot, offsetVelocityY)];

  /// Sets the velocity of [slot].
  void setVelocity(int slot, double vx, double vy) {
    _data[_index(slot, offsetVelocityX)] = vx;
    _data[_index(slot, offsetVelocityY)] = vy;
  }

  /// Moves [slot] by its velocity times [deltaTime].
  void applyVelocity(int slot, double deltaTime) {
    _data[_index(slot, offsetX)] +=
        _data[_index(slot, offsetVelocityX)] * deltaTime;
    _data[_index(slot, offsetY)] +=
        _data[_index(slot, offsetVelocityY)] * deltaTime;
  }

  /// The component at [offset] of [slot].
  double getValue(int slot, int offset) {
    return _data[_index(slot, offset)];
  }

  /// Sets the component at [offset] of [slot].
  void setValue(int slot, int offset, double value) {
    _data[_index(slot, offset)] = value;
  }

  /// Copies every component of slot [from] into slot [to].
  void copySlot(int from, int to) {
    final fromBase = _index(from, 0);
    final toBase = _index(to, 0);
    for (var i = 0; i < _componentsPerEntity; i++) {
      _data[toBase + i] = _data[fromBase + i];
    }
  }

  /// Calls [applyVelocity] on every allocated slot.
  void applyVelocityAll(double deltaTime) {
    for (var slot = 0; slot < _capacity; slot++) {
      if (_allocated[slot]) {
        applyVelocity(slot, deltaTime);
      }
    }
  }

  /// Calls [callback] with every allocated slot, in index order.
  void forEach(void Function(int slot) callback) {
    for (var slot = 0; slot < _capacity; slot++) {
      if (_allocated[slot]) {
        callback(slot);
      }
    }
  }

  /// A new list of the allocated slots, in index order.
  List<int> get allocatedSlots {
    final result = <int>[];
    for (var slot = 0; slot < _capacity; slot++) {
      if (_allocated[slot]) {
        result.add(slot);
      }
    }
    return result;
  }

  /// Frees every slot. Values are zeroed again as slots are allocated.
  void clear() {
    _allocated.fillRange(0, _allocated.length, false);
    _allocatedCount = 0;
    _freeListTop = 0;
    for (var i = 0; i < _capacity; i++) {
      _freeList[i] = _capacity - 1 - i;
    }
  }
}
