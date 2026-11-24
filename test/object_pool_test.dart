import 'package:just_memory/just_memory.dart';
import 'package:test/test.dart';

/// A mutable value type: equal when the coordinates match.
class _Vec {
  _Vec(this.x);

  double x;

  @override
  bool operator ==(Object other) => other is _Vec && other.x == x;

  @override
  int get hashCode => x.hashCode;
}

class _Recycled with Recyclable {
  int resets = 0;

  @override
  void reset() => resets++;
}

class _Voice {
  _Voice(this.name);

  final String name;
  int priority = 0;
}

void main() {
  group('ObjectPool', () {
    test('releases objects mutated while in use, with value equality', () {
      final pool = ObjectPool<_Vec>(
        create: () => _Vec(0),
        reset: (v) => v.x = 0,
      );

      final v = pool.acquire();
      v.x = 5; // changes its hashCode
      pool.release(v);

      expect(pool.inUseCount, 0);
      expect(pool.availableCount, 1);
    });

    test('tracks equal objects separately', () {
      final pool = ObjectPool<_Vec>(create: () => _Vec(0));

      final a = pool.acquire();
      final b = pool.acquire();
      expect(a, equals(b));
      expect(pool.inUseCount, 2);

      pool.release(a);
      pool.release(b);
      expect(pool.availableCount, 2);
      expect(pool.inUseCount, 0);
    });

    test('ignores a second release of a free object', () {
      final pool = ObjectPool<List<int>>(create: () => <int>[]);
      final value = pool.acquire();

      pool.release(value);
      pool.release(value);

      expect(pool.availableCount, 1);
      expect(pool.stats.totalReleased, 1);
    });

    test('throws on releasing a foreign object, naming the pool', () {
      final pool = ObjectPool<List<int>>(
        create: () => <int>[],
        debugLabel: 'scratch',
      );

      expect(
        () => pool.release(<int>[]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('scratch'),
          ),
        ),
      );
    });

    test('keeps at most maxSize free objects and counts peaks', () {
      var created = 0;
      final pool = ObjectPool<List<int>>(
        create: () {
          created++;
          return <int>[];
        },
        initialSize: 2,
        maxSize: 3,
      );
      expect(created, 2);

      final held = [for (var i = 0; i < 4; i++) pool.acquire()];
      expect(created, 4);
      held.forEach(pool.release);

      final stats = pool.stats;
      expect(stats.available, 3);
      expect(stats.inUse, 0);
      expect(stats.totalCreated, 4);
      expect(stats.totalAcquired, 4);
      expect(stats.totalReleased, 4);
      expect(stats.peakInUse, 4);
      expect(stats.peakAvailable, 3);
      expect(stats.totalTracked, 3);
      expect(pool.totalSize, 3);
    });

    test('rejects a negative maxSize', () {
      expect(
        () => ObjectPool<int>(create: () => 0, maxSize: -1),
        throwsRangeError,
      );
    });

    test('prewarm stops at maxSize and ignores non-positive counts', () {
      final pool = ObjectPool<List<int>>(create: () => <int>[], maxSize: 2);

      pool.prewarm(0);
      pool.prewarm(-3);
      expect(pool.availableCount, 0);

      pool.prewarm(5);
      expect(pool.availableCount, 2);
    });

    test('resets Recyclable objects when no reset callback is set', () {
      final pool = ObjectPool<_Recycled>(create: _Recycled.new);
      final value = pool.acquire();

      pool.release(value);

      expect(value.resets, 1);
    });

    test('prefers the reset callback over Recyclable.reset', () {
      var callbackResets = 0;
      final pool = ObjectPool<_Recycled>(
        create: _Recycled.new,
        reset: (_) => callbackResets++,
      );
      final value = pool.acquire();

      pool.release(value);

      expect(callbackResets, 1);
      expect(value.resets, 0);
    });

    test('calls onAcquire for new and reused objects', () {
      final acquired = <List<int>>[];
      final pool = ObjectPool<List<int>>(
        create: () => <int>[],
        onAcquire: acquired.add,
      );

      final first = pool.acquire();
      pool.release(first);
      final second = pool.acquire();

      expect(acquired, hasLength(2));
      expect(identical(acquired[0], acquired[1]), isTrue);
      expect(identical(first, second), isTrue);
    });

    test('shrink drops free objects; negative targets count as zero', () {
      final pool = ObjectPool<List<int>>(create: () => <int>[], initialSize: 5);

      pool.shrink(3);
      expect(pool.availableCount, 3);

      pool.shrink(-1);
      expect(pool.availableCount, 0);
    });

    test('releaseAll releases every in-use object', () {
      final pool = ObjectPool<List<int>>(create: () => <int>[]);
      pool.acquire();
      pool.acquire();

      pool.releaseAll();

      expect(pool.inUseCount, 0);
      expect(pool.availableCount, 2);
    });

    test('clear forgets in-use objects', () {
      final pool = ObjectPool<List<int>>(create: () => <int>[]);
      final value = pool.acquire();

      pool.clear();

      expect(pool.totalSize, 0);
      expect(() => pool.release(value), throwsStateError);
    });

    group('acquireScoped', () {
      test('is released when the scope is disposed', () {
        final pool = ObjectPool<List<int>>(create: () => <int>[]);
        final scope = MemoryScope();

        pool.acquireScoped(scope);
        expect(pool.inUseCount, 1);

        scope.dispose();
        expect(pool.inUseCount, 0);
        expect(pool.availableCount, 1);
      });

      test('leaves an object alone once it was released by hand', () {
        final pool = ObjectPool<List<int>>(create: () => <int>[]);
        final scope = MemoryScope();

        final scoped = pool.acquireScoped(scope);
        pool.release(scoped);
        final reacquired = pool.acquire(); // same object, new holder
        expect(identical(scoped, reacquired), isTrue);

        scope.dispose();

        expect(pool.inUseCount, 1);
        expect(pool.availableCount, 0);
      });

      test('a later scoped lease of the same object still works', () {
        final pool = ObjectPool<List<int>>(create: () => <int>[]);
        final first = MemoryScope();
        final second = MemoryScope();

        final a = pool.acquireScoped(first);
        pool.release(a);
        final b = pool.acquireScoped(second);
        expect(identical(a, b), isTrue);

        first.dispose(); // stale lease: no effect
        expect(pool.inUseCount, 1);

        second.dispose();
        expect(pool.inUseCount, 0);
      });
    });
  });

  group('RoundRobinPool', () {
    test('hands out objects in turn and recycles them', () {
      var next = 0;
      final recycled = <int>[];
      final pool = RoundRobinPool<int>(
        create: () => next++,
        size: 3,
        onRecycle: recycled.add,
      );

      expect([for (var i = 0; i < 4; i++) pool.next()], [0, 1, 2, 0]);
      expect(recycled, [0, 1, 2, 0]);
      expect(pool.currentIndex, 1);
      expect(pool.size, 3);
      expect(pool.at(4), 1);

      pool.reset();
      expect(pool.currentIndex, 0);

      final seen = <int>[];
      pool.forEach(seen.add);
      expect(seen, [0, 1, 2]);
    });

    test('rejects a size below one', () {
      expect(
        () => RoundRobinPool<int>(create: () => 0, size: 0),
        throwsRangeError,
      );
      expect(
        () => RoundRobinPool<int>(create: () => 0, size: -2),
        throwsRangeError,
      );
    });
  });

  group('PriorityPool', () {
    late List<String> reclaimed;
    late PriorityPool<_Voice> pool;
    var created = 0;

    setUp(() {
      reclaimed = <String>[];
      created = 0;
      pool = PriorityPool<_Voice>(
        create: () => _Voice('v${created++}'),
        reset: (v) => v.priority = 0,
        getPriority: (v) => v.priority,
        onReclaim: (v) => reclaimed.add('${v.name}@${v.priority}'),
      );
    });

    test('reuses released objects first', () {
      final a = pool.acquire();
      pool.release(a);

      expect(identical(pool.acquire(), a), isTrue);
      expect(pool.inUseCount, 1);
      expect(pool.availableCount, 0);
    });

    test('reclaims the lowest priority below minPriority', () {
      final high = pool.acquire()..priority = 5;
      final low = pool.acquire()..priority = 1;

      final stolen = pool.acquire(minPriority: 3);

      expect(identical(stolen, low), isTrue);
      expect(reclaimed, ['v1@1']); // seen before reset
      expect(stolen.priority, 0);
      expect(high.priority, 5);
      expect(pool.inUseCount, 2);
      expect(created, 2);
    });

    test('creates a new object when nothing is below minPriority', () {
      pool.acquire().priority = 5;

      final fresh = pool.acquire(minPriority: 3);

      expect(fresh.name, 'v1');
      expect(reclaimed, isEmpty);
      expect(pool.inUseCount, 2);
    });

    test('ignores releases of objects it does not hold', () {
      pool.release(_Voice('stranger'));
      expect(pool.availableCount, 0);
    });

    test('prewarms initialSize objects', () {
      final warm = PriorityPool<_Voice>(
        create: () => _Voice('w'),
        initialSize: 3,
      );
      expect(warm.availableCount, 3);
    });
  });
}
