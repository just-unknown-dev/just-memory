import 'package:just_memory/just_memory.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryArena', () {
    test('allocates until full, then returns -1', () {
      final arena = MemoryArena(capacity: 2);

      final a = arena.allocate();
      final b = arena.allocate();

      expect({a, b}, {0, 1});
      expect(arena.allocate(), -1);
      expect(arena.isFull, isTrue);
      expect(arena.allocatedCount, 2);
      expect(arena.availableCount, 0);
      expect(arena.capacity, 2);
      expect(arena.componentsPerEntity, 8);
    });

    test('free returns a slot; bad or repeated frees do nothing', () {
      final arena = MemoryArena(capacity: 2);
      final slot = arena.allocate();

      arena.free(slot);
      arena.free(slot);
      arena.free(-1);
      arena.free(99);

      expect(arena.isAllocated(slot), isFalse);
      expect(arena.isAllocated(-1), isFalse);
      expect(arena.allocatedCount, 0);
      expect(arena.allocate(), slot);
    });

    test('a reused slot comes back zeroed', () {
      final arena = MemoryArena(capacity: 1);
      final slot = arena.allocate();
      arena.setPosition(slot, 3, 4);

      arena.free(slot);
      final again = arena.allocate();

      expect(again, slot);
      expect(arena.getX(again), 0);
      expect(arena.getY(again), 0);
    });

    test('transform accessors read back what they wrote', () {
      final arena = MemoryArena(capacity: 1);
      final s = arena.allocate();

      arena.setPosition(s, 1, 2);
      arena.translate(s, 10, 20);
      arena.setRotation(s, 0.5);
      arena.rotate(s, 0.25);
      arena.setScale(s, 2);
      arena.setVelocity(s, 3, -4);
      arena.applyVelocity(s, 0.5);
      arena.setValue(s, MemoryArena.offsetExtra, 9);

      expect(arena.getX(s), 12.5);
      expect(arena.getY(s), 20);
      expect(arena.getRotation(s), 0.75);
      expect(arena.getScaleX(s), 2);
      expect(arena.getScaleY(s), 2);
      expect(arena.getVelocityX(s), 3);
      expect(arena.getVelocityY(s), -4);
      expect(arena.getValue(s, MemoryArena.offsetExtra), 9);

      arena.setScaleXY(s, 1, 3);
      expect(arena.getScaleY(s), 3);
      expect(arena.rawData[s * 8 + MemoryArena.offsetScaleY], 3);
    });

    test('applyVelocityAll, forEach and allocatedSlots skip free slots', () {
      final arena = MemoryArena(capacity: 3);
      final slots = [arena.allocate(), arena.allocate(), arena.allocate()];
      arena.free(slots[1]);
      for (final s in arena.allocatedSlots) {
        arena.setVelocity(s, 1, 1);
      }

      arena.applyVelocityAll(2);
      final visited = <int>[];
      arena.forEach(visited.add);

      expect(arena.allocatedSlots, visited);
      expect(visited, orderedEquals(visited.toList()..sort()));
      expect(visited, isNot(contains(slots[1])));
      for (final s in visited) {
        expect(arena.getX(s), 2);
      }
    });

    test('copySlot copies every component', () {
      final arena = MemoryArena(capacity: 2, componentsPerEntity: 3);
      final a = arena.allocate();
      final b = arena.allocate();
      for (var c = 0; c < 3; c++) {
        arena.setValue(a, c, c + 1.0);
      }

      arena.copySlot(a, b);

      expect([for (var c = 0; c < 3; c++) arena.getValue(b, c)], [1, 2, 3]);
    });

    test('clear frees every slot', () {
      final arena = MemoryArena(capacity: 2);
      arena.allocate();
      arena.allocate();

      arena.clear();

      expect(arena.allocatedCount, 0);
      expect(arena.allocatedSlots, isEmpty);
      expect(arena.allocate(), isNot(-1));
    });

    test('asserts when a named accessor needs more components', () {
      final arena = MemoryArena(capacity: 2, componentsPerEntity: 4);
      final a = arena.allocate();
      final b = arena.allocate();
      arena.setPosition(a, 7, 7);

      expect(() => arena.setVelocity(b, 9, 9), throwsA(isA<AssertionError>()));
      expect(() => arena.getValue(a, 4), throwsA(isA<AssertionError>()));
      expect(arena.getY(a), 7);
    });

    test('asserts on slots outside the arena', () {
      final arena = MemoryArena(capacity: 2);

      expect(() => arena.getX(2), throwsA(isA<AssertionError>()));
      expect(() => arena.setValue(-1, 0, 1), throwsA(isA<AssertionError>()));
    });
  });
}
