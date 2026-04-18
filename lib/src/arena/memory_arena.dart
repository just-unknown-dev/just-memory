import 'dart:typed_data';

class MemoryArena {
  MemoryArena({required int capacity, int componentsPerEntity = 8})
    : _capacity = capacity,
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

  static const int offsetX = 0;
  static const int offsetY = 1;
  static const int offsetRotation = 2;
  static const int offsetScaleX = 3;
  static const int offsetScaleY = 4;
  static const int offsetVelocityX = 5;
  static const int offsetVelocityY = 6;
  static const int offsetExtra = 7;

  int get capacity => _capacity;
  int get allocatedCount => _allocatedCount;
  int get availableCount => _capacity - _allocatedCount;
  bool get isFull => _allocatedCount >= _capacity;
  Float64List get rawData => _data;

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

  void free(int slot) {
    if (slot < 0 || slot >= _capacity || !_allocated[slot]) {
      return;
    }

    _allocated[slot] = false;
    _freeList[--_freeListTop] = slot;
    _allocatedCount--;
  }

  bool isAllocated(int slot) {
    return slot >= 0 && slot < _capacity && _allocated[slot];
  }

  int _baseIndex(int slot) => slot * _componentsPerEntity;

  double getX(int slot) => _data[_baseIndex(slot) + offsetX];
  double getY(int slot) => _data[_baseIndex(slot) + offsetY];

  void setPosition(int slot, double x, double y) {
    final base = _baseIndex(slot);
    _data[base + offsetX] = x;
    _data[base + offsetY] = y;
  }

  void translate(int slot, double dx, double dy) {
    final base = _baseIndex(slot);
    _data[base + offsetX] += dx;
    _data[base + offsetY] += dy;
  }

  double getRotation(int slot) => _data[_baseIndex(slot) + offsetRotation];

  void setRotation(int slot, double rotation) {
    _data[_baseIndex(slot) + offsetRotation] = rotation;
  }

  void rotate(int slot, double angle) {
    _data[_baseIndex(slot) + offsetRotation] += angle;
  }

  double getScaleX(int slot) => _data[_baseIndex(slot) + offsetScaleX];
  double getScaleY(int slot) => _data[_baseIndex(slot) + offsetScaleY];

  void setScale(int slot, double scale) {
    final base = _baseIndex(slot);
    _data[base + offsetScaleX] = scale;
    _data[base + offsetScaleY] = scale;
  }

  void setScaleXY(int slot, double scaleX, double scaleY) {
    final base = _baseIndex(slot);
    _data[base + offsetScaleX] = scaleX;
    _data[base + offsetScaleY] = scaleY;
  }

  double getVelocityX(int slot) => _data[_baseIndex(slot) + offsetVelocityX];
  double getVelocityY(int slot) => _data[_baseIndex(slot) + offsetVelocityY];

  void setVelocity(int slot, double vx, double vy) {
    final base = _baseIndex(slot);
    _data[base + offsetVelocityX] = vx;
    _data[base + offsetVelocityY] = vy;
  }

  void applyVelocity(int slot, double deltaTime) {
    final base = _baseIndex(slot);
    _data[base + offsetX] += _data[base + offsetVelocityX] * deltaTime;
    _data[base + offsetY] += _data[base + offsetVelocityY] * deltaTime;
  }

  double getValue(int slot, int offset) {
    return _data[_baseIndex(slot) + offset];
  }

  void setValue(int slot, int offset, double value) {
    _data[_baseIndex(slot) + offset] = value;
  }

  void copySlot(int from, int to) {
    final fromBase = _baseIndex(from);
    final toBase = _baseIndex(to);
    for (var i = 0; i < _componentsPerEntity; i++) {
      _data[toBase + i] = _data[fromBase + i];
    }
  }

  void applyVelocityAll(double deltaTime) {
    for (var slot = 0; slot < _capacity; slot++) {
      if (_allocated[slot]) {
        applyVelocity(slot, deltaTime);
      }
    }
  }

  void forEach(void Function(int slot) callback) {
    for (var slot = 0; slot < _capacity; slot++) {
      if (_allocated[slot]) {
        callback(slot);
      }
    }
  }

  List<int> get allocatedSlots {
    final result = <int>[];
    for (var slot = 0; slot < _capacity; slot++) {
      if (_allocated[slot]) {
        result.add(slot);
      }
    }
    return result;
  }

  void clear() {
    _allocated.fillRange(0, _allocated.length, false);
    _allocatedCount = 0;
    _freeListTop = 0;
    for (var i = 0; i < _capacity; i++) {
      _freeList[i] = _capacity - 1 - i;
    }
  }
}
