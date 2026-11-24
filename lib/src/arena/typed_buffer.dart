import 'dart:math' as math;
import 'dart:typed_data';

import 'memory_arena.dart';

/// A 2D vector stored in two components of a [MemoryArena] slot, or in its
/// own fields when made with [TypedVec2.temp].
///
/// Reads and writes go straight to the arena, so the vector allocates
/// nothing per use.
class TypedVec2 {
  /// A vector backed by a slot of an arena, at components [xOffset] and
  /// [yOffset] (the position by default).
  TypedVec2(this._arena, this._slot, {int xOffset = 0, int yOffset = 1})
    : _xOffset = xOffset,
      _yOffset = yOffset;

  /// A standalone vector that holds ([x], [y]) itself.
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

  /// The x component.
  double get x => _isTemp ? _tempX : _arena!.getValue(_slot, _xOffset);
  set x(double value) {
    if (_isTemp) {
      _tempX = value;
    } else {
      _arena!.setValue(_slot, _xOffset, value);
    }
  }

  /// The y component.
  double get y => _isTemp ? _tempY : _arena!.getValue(_slot, _yOffset);
  set y(double value) {
    if (_isTemp) {
      _tempY = value;
    } else {
      _arena!.setValue(_slot, _yOffset, value);
    }
  }

  /// Sets both components.
  void set(double x, double y) {
    this.x = x;
    this.y = y;
  }

  /// Adds [other] to this vector.
  void add(TypedVec2 other) {
    x += other.x;
    y += other.y;
  }

  /// Subtracts [other] from this vector.
  void subtract(TypedVec2 other) {
    x -= other.x;
    y -= other.y;
  }

  /// Multiplies both components by [factor].
  void scale(double factor) {
    x *= factor;
    y *= factor;
  }

  /// The squared length; cheaper than [length] for comparisons.
  double get lengthSquared => x * x + y * y;

  /// The length.
  double get length => math.sqrt(lengthSquared);

  /// Scales this vector to length 1. A zero vector is left as it is.
  void normalize() {
    final len = length;
    if (len > 0) {
      x /= len;
      y /= len;
    }
  }

  /// The dot product with [other].
  double dot(TypedVec2 other) => x * other.x + y * other.y;

  /// The distance to [other].
  double distanceTo(TypedVec2 other) => math.sqrt(distanceSquaredTo(other));

  /// The squared distance to [other]; cheaper than [distanceTo] for
  /// comparisons.
  double distanceSquaredTo(TypedVec2 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return dx * dx + dy * dy;
  }

  /// Copies [other]'s components into this vector.
  void copyFrom(TypedVec2 other) {
    x = other.x;
    y = other.y;
  }

  @override
  String toString() => 'TypedVec2($x, $y)';
}

/// A view of one [MemoryArena] slot as a 2D transform (position, rotation,
/// scale, velocity), using the arena's transform layout.
class TypedTransform {
  /// A view of [_slot] in [_arena].
  TypedTransform(this._arena, this._slot);

  final MemoryArena _arena;
  final int _slot;

  /// The x position.
  double get x => _arena.getX(_slot);
  set x(double value) => _arena.setValue(_slot, MemoryArena.offsetX, value);

  /// The y position.
  double get y => _arena.getY(_slot);
  set y(double value) => _arena.setValue(_slot, MemoryArena.offsetY, value);

  /// Sets the position.
  void setPosition(double x, double y) => _arena.setPosition(_slot, x, y);

  /// Moves the position by ([dx], [dy]).
  void translate(double dx, double dy) => _arena.translate(_slot, dx, dy);

  /// The rotation.
  double get rotation => _arena.getRotation(_slot);
  set rotation(double value) => _arena.setRotation(_slot, value);

  /// Adds [angle] to the rotation.
  void rotate(double angle) => _arena.rotate(_slot, angle);

  /// The x scale.
  double get scaleX => _arena.getScaleX(_slot);

  /// The y scale.
  double get scaleY => _arena.getScaleY(_slot);

  /// Sets both scales to [scale].
  void setScale(double scale) => _arena.setScale(_slot, scale);

  /// Sets the x and y scales.
  void setScaleXY(double sx, double sy) => _arena.setScaleXY(_slot, sx, sy);

  /// The x velocity.
  double get velocityX => _arena.getVelocityX(_slot);

  /// The y velocity.
  double get velocityY => _arena.getVelocityY(_slot);

  /// Sets the velocity.
  void setVelocity(double vx, double vy) => _arena.setVelocity(_slot, vx, vy);

  /// Moves the position by the velocity times [dt].
  void applyVelocity(double dt) => _arena.applyVelocity(_slot, dt);

  /// The arena slot this transform views.
  int get slot => _slot;
}

/// A fixed-capacity numeric buffer backed by a [Float64List], [Float32List]
/// or [Int32List].
///
/// [length] is one past the highest index written since the last [clear].
/// Writing a double to an `int32` buffer truncates it toward zero (and
/// throws for NaN or infinity). The type argument is not used; the backing
/// list is chosen by the constructor.
class TypedBuffer<T extends num> {
  /// A buffer of [capacity] 64-bit floats.
  TypedBuffer.float64(int capacity)
    : _float64Data = Float64List(capacity),
      _float32Data = null,
      _int32Data = null,
      _capacity = capacity;

  /// A buffer of [capacity] 32-bit floats.
  TypedBuffer.float32(int capacity)
    : _float64Data = null,
      _float32Data = Float32List(capacity),
      _int32Data = null,
      _capacity = capacity;

  /// A buffer of [capacity] 32-bit signed integers.
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

  /// How many values the buffer can hold.
  int get capacity => _capacity;

  /// One past the highest index written since the last [clear].
  int get length => _length;

  /// Whether nothing has been written since the last [clear].
  bool get isEmpty => _length == 0;

  /// Whether the value at the last index has been written.
  bool get isFull => _length >= _capacity;

  /// The value at [index] as a double.
  double getFloat(int index) {
    if (_float64Data != null) return _float64Data[index];
    if (_float32Data != null) return _float32Data[index].toDouble();
    return _int32Data![index].toDouble();
  }

  /// Writes [value] at [index].
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

  /// The value at [index] as an int, truncated toward zero.
  int getInt(int index) {
    if (_int32Data != null) return _int32Data[index];
    if (_float64Data != null) return _float64Data[index].toInt();
    return _float32Data![index].toInt();
  }

  /// Writes [value] at [index].
  void setInt(int index, int value) {
    setFloat(index, value.toDouble());
  }

  /// Resets [length] to zero. The stored values are kept.
  void clear() {
    _length = 0;
  }
}
