import 'package:just_memory/just_memory.dart';
import 'package:test/test.dart';

void main() {
  group('TypedVec2', () {
    test('length is exact across magnitudes', () {
      for (final d in [1e-6, 0.001, 0.1, 3.0, 1000.0, 1e5, 1e12]) {
        expect(TypedVec2.temp(d, 0).length, closeTo(d, d * 1e-12));
      }
      expect(TypedVec2.temp(3, 4).length, 5);
      expect(TypedVec2.temp(0, 0).length, 0);
    });

    test('normalize gives a unit vector and leaves zero alone', () {
      final v = TypedVec2.temp(3000, 4000)..normalize();
      expect(v.x, closeTo(0.6, 1e-12));
      expect(v.y, closeTo(0.8, 1e-12));

      final zero = TypedVec2.temp(0, 0)..normalize();
      expect(zero.x, 0);
      expect(zero.y, 0);
    });

    test('distance, dot and arithmetic', () {
      final a = TypedVec2.temp(1, 2);
      final b = TypedVec2.temp(4, 6);

      expect(a.distanceTo(b), 5);
      expect(a.distanceSquaredTo(b), 25);
      expect(a.dot(b), 16);

      a.add(b);
      expect([a.x, a.y], [5, 8]);
      a.subtract(b);
      expect([a.x, a.y], [1, 2]);
      a.scale(3);
      expect([a.x, a.y], [3, 6]);
      a.set(-1, -2);
      expect(a.lengthSquared, 5);
      a.copyFrom(b);
      expect(a.toString(), 'TypedVec2(4.0, 6.0)');
    });

    test('an arena-backed vector reads and writes its slot', () {
      final arena = MemoryArena(capacity: 1);
      final slot = arena.allocate();
      final position = TypedVec2(arena, slot);
      final velocity = TypedVec2(
        arena,
        slot,
        xOffset: MemoryArena.offsetVelocityX,
        yOffset: MemoryArena.offsetVelocityY,
      );

      position.set(1, 2);
      velocity.set(3, 4);

      expect(arena.getX(slot), 1);
      expect(arena.getY(slot), 2);
      expect(arena.getVelocityX(slot), 3);
      expect(velocity.length, 5);
    });
  });

  group('TypedTransform', () {
    test('views one arena slot', () {
      final arena = MemoryArena(capacity: 2);
      arena.allocate();
      final slot = arena.allocate();
      final t = TypedTransform(arena, slot);

      t.setPosition(1, 1);
      t.translate(1, 2);
      t.x += 1;
      t.y += 1;
      t.rotation = 1;
      t.rotate(0.5);
      t.setScale(2);
      t.setVelocity(2, 0);
      t.applyVelocity(0.5);

      expect(t.slot, slot);
      expect([t.x, t.y], [4, 4]);
      expect(t.rotation, 1.5);
      expect([t.scaleX, t.scaleY], [2, 2]);
      expect([t.velocityX, t.velocityY], [2, 0]);
      expect(arena.getX(slot), 4);

      t.setScaleXY(1, 3);
      expect(t.scaleY, 3);
    });
  });

  group('TypedBuffer', () {
    test('float64 stores doubles exactly', () {
      final buffer = TypedBuffer<double>.float64(4);

      buffer.setFloat(2, 0.1);

      expect(buffer.getFloat(2), 0.1);
      expect(buffer.getInt(2), 0);
      expect(buffer.length, 3);
      expect(buffer.isEmpty, isFalse);
      expect(buffer.isFull, isFalse);
    });

    test('float32 rounds to single precision', () {
      final buffer = TypedBuffer<double>.float32(2);

      buffer.setFloat(0, 0.1);
      buffer.setInt(1, 7);

      expect(buffer.getFloat(0), closeTo(0.1, 1e-7));
      expect(buffer.getFloat(0), isNot(0.1));
      expect(buffer.getInt(1), 7);
      expect(buffer.isFull, isTrue);
    });

    test('int32 truncates doubles toward zero', () {
      final buffer = TypedBuffer<int>.int32(2);

      buffer.setFloat(0, -2.9);
      buffer.setInt(1, 41);

      expect(buffer.getInt(0), -2);
      expect(buffer.getFloat(1), 41.0);
    });

    test('clear resets the length only', () {
      final buffer = TypedBuffer<double>.float64(3)..setFloat(1, 5);

      buffer.clear();

      expect(buffer.length, 0);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.capacity, 3);
      expect(buffer.getFloat(1), 5);
    });
  });
}
