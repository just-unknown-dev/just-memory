import 'dart:typed_data';

import 'memory_arena.dart';

class TypedVec2 {
  TypedVec2(this._arena, this._slot, {int xOffset = 0, int yOffset = 1})
    : _xOffset = xOffset,
      _yOffset = yOffset;

  TypedVec2.temp(double x, double y)
    : _arena = null,
      _slot = -1,
      _xOffset = 0,
      _yOffset = 1,
      _tempX = x,
      _tempY = y;

  final MemoryArena? _arena;
  final int _slot;
  final int _xOffset;
  final int _yOffset;
  double _tempX = 0.0;
  double _tempY = 0.0;

  bool get _isTemp => _arena == null;

  double get x => _isTemp ? _tempX : _arena!.getValue(_slot, _xOffset);
  set x(double value) {
    if (_isTemp) {
      _tempX = value;
    } else {
      _arena!.setValue(_slot, _xOffset, value);
    }
  }

  double get y => _isTemp ? _tempY : _arena!.getValue(_slot, _yOffset);
  set y(double value) {
    if (_isTemp) {
      _tempY = value;
    } else {
      _arena!.setValue(_slot, _yOffset, value);
    }
  }

  void set(double x, double y) {
    this.x = x;
    this.y = y;
  }

  void add(TypedVec2 other) {
    x += other.x;
    y += other.y;
  }

  void subtract(TypedVec2 other) {
    x -= other.x;
    y -= other.y;
  }

  void scale(double factor) {
    x *= factor;
    y *= factor;
  }

  double get lengthSquared => x * x + y * y;

  double get length {
    final ls = lengthSquared;
    if (ls == 0) return 0;
    return _sqrt(ls);
  }

  void normalize() {
    final len = length;
    if (len > 0) {
      x /= len;
      y /= len;
    }
  }

  double dot(TypedVec2 other) => x * other.x + y * other.y;

  double distanceTo(TypedVec2 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return _sqrt(dx * dx + dy * dy);
  }

  double distanceSquaredTo(TypedVec2 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return dx * dx + dy * dy;
  }

  void copyFrom(TypedVec2 other) {
    x = other.x;
    y = other.y;
  }

  static double _sqrt(double x) {
    return x.isNaN || x < 0
        ? 0
        : x == 0
        ? 0
        : _dartSqrt(x);
  }

  static double _dartSqrt(double x) {
    return x <= 0
        ? 0
        : x.isInfinite
        ? x
        : _sqrtImpl(x);
  }

  static double _sqrtImpl(double x) {
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  @override
  String toString() => 'TypedVec2($x, $y)';
}

class TypedTransform {
  TypedTransform(this._arena, this._slot);

  final MemoryArena _arena;
  final int _slot;

  double get x => _arena.getX(_slot);
  set x(double value) => _arena.setValue(_slot, MemoryArena.offsetX, value);

  double get y => _arena.getY(_slot);
  set y(double value) => _arena.setValue(_slot, MemoryArena.offsetY, value);

  void setPosition(double x, double y) => _arena.setPosition(_slot, x, y);
  void translate(double dx, double dy) => _arena.translate(_slot, dx, dy);

  double get rotation => _arena.getRotation(_slot);
  set rotation(double value) => _arena.setRotation(_slot, value);
  void rotate(double angle) => _arena.rotate(_slot, angle);

  double get scaleX => _arena.getScaleX(_slot);
  double get scaleY => _arena.getScaleY(_slot);
  void setScale(double scale) => _arena.setScale(_slot, scale);
  void setScaleXY(double sx, double sy) => _arena.setScaleXY(_slot, sx, sy);

  double get velocityX => _arena.getVelocityX(_slot);
  double get velocityY => _arena.getVelocityY(_slot);
  void setVelocity(double vx, double vy) => _arena.setVelocity(_slot, vx, vy);
  void applyVelocity(double dt) => _arena.applyVelocity(_slot, dt);

  int get slot => _slot;
}

class TypedBuffer<T extends num> {
  TypedBuffer.float64(int capacity)
    : _float64Data = Float64List(capacity),
      _float32Data = null,
      _int32Data = null,
      _capacity = capacity;

  TypedBuffer.float32(int capacity)
    : _float64Data = null,
      _float32Data = Float32List(capacity),
      _int32Data = null,
      _capacity = capacity;

  TypedBuffer.int32(int capacity)
    : _float64Data = null,
      _float32Data = null,
      _int32Data = Int32List(capacity),
      _capacity = capacity;

  final Float64List? _float64Data;
  final Float32List? _float32Data;
  final Int32List? _int32Data;
  final int _capacity;
  int _length = 0;

  int get capacity => _capacity;
  int get length => _length;
  bool get isEmpty => _length == 0;
  bool get isFull => _length >= _capacity;

  double getFloat(int index) {
    if (_float64Data != null) return _float64Data[index];
    if (_float32Data != null) return _float32Data[index].toDouble();
    return _int32Data![index].toDouble();
  }

  void setFloat(int index, double value) {
    if (_float64Data != null) {
      _float64Data[index] = value;
    } else if (_float32Data != null) {
      _float32Data[index] = value;
    } else {
      _int32Data![index] = value.toInt();
    }

    if (index >= _length) {
      _length = index + 1;
    }
  }

  int getInt(int index) {
    if (_int32Data != null) return _int32Data[index];
    if (_float64Data != null) return _float64Data[index].toInt();
    return _float32Data![index].toInt();
  }

  void setInt(int index, int value) {
    setFloat(index, value.toDouble());
  }

  void clear() {
    _length = 0;
  }
}
