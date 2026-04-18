import 'dart:io';

import 'package:test/test.dart';
import 'package:just_memory/just_memory.dart';

void main() {
  group('ObjectPool', () {
    test('reuses released objects and tracks stats', () {
      var created = 0;
      final pool = ObjectPool<_Reusable>(
        create: () => _Reusable(++created),
        reset: (value) => value.value = 0,
        initialSize: 1,
        maxSize: 2,
      );

      final first = pool.acquire();
      first.value = 42;
      pool.release(first);

      final second = pool.acquire();
      expect(identical(first, second), isTrue);
      expect(second.value, 0);
      expect(pool.stats.totalCreated, 1);
      expect(pool.stats.inUse, 1);
    });

    test('rejects releasing values not owned by the pool', () {
      final pool = ObjectPool<_Reusable>(create: () => _Reusable(1));

      expect(() => pool.release(_Reusable(999)), throwsStateError);
      expect(pool.availableCount, 0);
      expect(pool.inUseCount, 0);
    });
  });

  group('MemoryScope', () {
    test('releases registered cleanup callbacks in LIFO order', () {
      final log = <String>[];
      final scope = MemoryScope();

      scope.own(() => log.add('first'));
      scope.own(() => log.add('second'));
      scope.dispose();

      expect(log, ['second', 'first']);
      expect(scope.isDisposed, isTrue);
    });

    test('disposeAsync waits for async cleanup callbacks to finish', () async {
      final scope = MemoryScope();
      var cleaned = false;

      scope.own(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        cleaned = true;
      });

      await scope.disposeAsync();

      expect(cleaned, isTrue);
      expect(scope.isDisposed, isTrue);
    });
  });

  group('RefCountedRegistry', () {
    test('loads once and unloads when final handle is released', () async {
      var loads = 0;
      var unloads = 0;

      final registry = RefCountedRegistry<String, String>(
        loader: (key) async {
          loads++;
          return 'value:$key';
        },
        disposer: (value) {
          unloads++;
        },
      );

      final a = await registry.acquire('player');
      final b = await registry.acquire('player');

      expect(a.value, 'value:player');
      expect(identical(a.value, b.value), isTrue);
      expect(a.refCount, 2);

      a.release();
      expect(registry.refCountOf('player'), 1);

      b.release();
      expect(registry.refCountOf('player'), 0);
      expect(loads, 1);
      expect(unloads, 1);
    });

    test('scope disposal can await async resource cleanup', () async {
      var unloads = 0;
      final scope = MemoryScope();
      final registry = RefCountedRegistry<String, String>(
        loader: (key) async => 'value:$key',
        disposer: (value) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          unloads++;
        },
      );

      await registry.acquire('player', scope: scope);
      await scope.disposeAsync();

      expect(unloads, 1);
      expect(registry.containsKey('player'), isFalse);
    });
  });

  group('BudgetedCache', () {
    test('evicts least recently used entries when over budget', () {
      final evicted = <String>[];
      final cache = BudgetedCache<String, String>(
        maxCost: 3,
        estimateCost: (key, value) => 1,
        onEvict: (key, value) => evicted.add(key),
      );

      cache['a'] = 'A';
      cache['b'] = 'B';
      cache['c'] = 'C';
      expect(cache['a'], 'A'); // refresh a
      cache['d'] = 'D';

      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('d'), isTrue);
      expect(cache.containsKey('b'), isFalse);
      expect(evicted, ['b']);
    });
  });

  group('MemoryProfiler', () {
    test('captures snapshots from pools and caches', () {
      final profiler = MemoryProfiler();
      final pool = ObjectPool<_Reusable>(
        create: () => _Reusable(1),
        reset: (value) => value.value = 0,
        initialSize: 2,
        maxSize: 4,
      );
      final cache = BudgetedCache<String, String>(
        maxCost: 2,
        estimateCost: (key, value) => 1,
      );

      profiler.trackPool('reusables', pool);
      profiler.trackCache('strings', cache);

      final item = pool.acquire();
      cache['a'] = 'A';
      final snapshot = profiler.capture();
      pool.release(item);

      expect(snapshot.poolStats['reusables']?.inUse, 1);
      expect(snapshot.cacheStats['strings']?.entryCount, 1);
      expect(snapshot.trackedPools, 1);
      expect(snapshot.trackedCaches, 1);
    });

    test('captures system memory availability', () {
      final snapshot = MemoryProfiler.captureSystemMemory();

      expect(snapshot.isSupported, isA<bool>());
      expect(snapshot.totalPhysicalMemoryBytes, greaterThanOrEqualTo(0));
      expect(snapshot.freePhysicalMemoryBytes, greaterThanOrEqualTo(0));
      expect(snapshot.rssBytes, greaterThanOrEqualTo(0));
      expect(snapshot.availabilityRatio, inInclusiveRange(0.0, 1.0));

      if (Platform.isWindows) {
        expect(snapshot.isSupported, isTrue);
        expect(snapshot.totalPhysicalMemoryBytes, greaterThan(0));
      }
    });

    test('cleanupTrackedResources clears tracked caches and pools', () {
      final profiler = MemoryProfiler();
      final pool = ObjectPool<_Reusable>(
        create: () => _Reusable(7),
        reset: (value) => value.value = 0,
        initialSize: 1,
        maxSize: 4,
      );
      final cache = BudgetedCache<String, String>(
        maxCost: 4,
        estimateCost: (key, value) => 1,
      );

      profiler.trackPool('reusables', pool);
      profiler.trackCache('strings', cache);

      pool.acquire();
      cache['a'] = 'A';
      cache['b'] = 'B';

      final result = profiler.cleanupTrackedResources(
        clearReleasedObjects: true,
      );

      expect(result.clearedCaches, 1);
      expect(result.releasedPools, 1);
      expect(cache.isEmpty, isTrue);
      expect(pool.inUseCount, 0);
      expect(pool.availableCount, 0);
    });
  });
}

class _Reusable {
  _Reusable(this.id);

  final int id;
  int value = 0;
}
