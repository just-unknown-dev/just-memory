import 'package:just_memory/just_memory.dart';
import 'package:test/test.dart';

class _Key {
  _Key(this.id);

  final int id;

  @override
  bool operator ==(Object other) => other is _Key && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

void main() {
  tearDown(PoolManager.resetInstance);

  group('LeakTracker', () {
    test('counts live objects by identity and label', () {
      final tracker = LeakTracker();
      final a = _Key(1);
      final b = _Key(1); // equal to a, but a different object

      tracker.track(a, label: 'texture');
      tracker.track(b, label: 'texture');
      tracker.track(Object(), label: 'sound');

      expect(tracker.leakCount, 3);
      expect(tracker.summaryByLabel(), {'texture': 2, 'sound': 1});

      tracker.untrack(a);
      expect(tracker.leakCount, 2);
      expect(tracker.hasLeaks, isTrue);

      tracker.clear();
      expect(tracker.hasLeaks, isFalse);
    });

    test('does nothing when disabled', () {
      final tracker = LeakTracker(enabled: false);

      tracker.track(Object());
      tracker.untrack(Object());

      expect(tracker.leakCount, 0);
    });
  });

  group('MemoryProfiler', () {
    test('untracked pools and caches drop out of snapshots', () {
      final profiler = MemoryProfiler()
        ..trackPool('p', ObjectPool<int>(create: () => 0))
        ..trackCache(
          'c',
          BudgetedCache<String, int>(maxCost: 1, estimateCost: (k, v) => 1),
        );

      profiler
        ..untrackPool('p')
        ..untrackCache('c');
      final snapshot = profiler.capture();

      expect(snapshot.trackedPools, 0);
      expect(snapshot.trackedCaches, 0);
    });

    test('cleanupTrackedResources passes cache entries to onEvict', () {
      final evicted = <String>[];
      final cache = BudgetedCache<String, int>(
        maxCost: 5,
        estimateCost: (k, v) => 1,
        onEvict: (k, v) => evicted.add(k),
      );
      final profiler = MemoryProfiler()..trackCache('c', cache);
      cache['a'] = 1;

      final result = profiler.cleanupTrackedResources();

      expect(evicted, ['a']);
      expect(result.clearedCaches, 1);
      expect(result.didWork, isTrue);
    });

    test('cleanupGlobalResources releases the shared pools and arenas', () {
      final manager = PoolManager.instance;
      final pool = ObjectPool<List<int>>(create: () => <int>[]);
      manager.registerPool('lists', pool);
      final arena = manager.createArena('bodies', capacity: 2);
      pool.acquire();
      arena.allocate();

      final result = MemoryProfiler.cleanupGlobalResources();

      expect(result.releasedPools, 1);
      expect(result.clearedArenas, 1);
      expect(pool.inUseCount, 0);
      expect(arena.allocatedCount, 0);
      expect(manager.hasPool('lists'), isTrue);

      MemoryProfiler.cleanupGlobalResources(clearReleasedObjects: true);
      expect(manager.hasPool('lists'), isFalse);
    });

    test('cleanupGlobalResources on a disposed manager does nothing', () {
      PoolManager.instance.dispose();

      final result = MemoryProfiler.cleanupGlobalResources();

      expect(result.didWork, isFalse);
    });

    test('captureSystemMemory caches its reading briefly', () {
      final first = MemoryProfiler.captureSystemMemory();
      final second = MemoryProfiler.captureSystemMemory();

      expect(second, same(first));
    });
  });

  group('value types', () {
    test('MemoryStats', () {
      const stats = MemoryStats(
        totalCreated: 3,
        totalAcquired: 5,
        totalReleased: 4,
        inUse: 1,
        available: 2,
        peakInUse: 2,
        peakAvailable: 2,
      );

      expect(stats.totalTracked, 3);
      expect(stats.toString(), contains('created: 3'));
    });

    test('CacheBudgetStats with no budget', () {
      const stats = CacheBudgetStats(entryCount: 0, currentCost: 0, maxCost: 0);
      expect(stats.utilizationPercent, 0);
    });

    test('ArenaStats with no capacity', () {
      const stats = ArenaStats(capacity: 0, allocated: 0, available: 0);
      expect(stats.utilizationPercent, 0);
    });

    test('SystemMemorySnapshot figures', () {
      const snapshot = SystemMemorySnapshot(
        totalPhysicalMemoryBytes: 1000,
        freePhysicalMemoryBytes: 250,
        rssBytes: 10,
        isSupported: true,
      );

      expect(snapshot.usedPhysicalMemoryBytes, 750);
      expect(snapshot.availabilityRatio, 0.25);

      final odd = snapshot.copyWith(freePhysicalMemoryBytes: 2000);
      expect(odd.usedPhysicalMemoryBytes, 0);
      expect(odd.rssBytes, 10);

      const unsupported = SystemMemorySnapshot.unsupported(rssBytes: 5);
      expect(unsupported.isSupported, isFalse);
      expect(unsupported.availabilityRatio, 0);
      expect(unsupported.copyWith(isSupported: true).rssBytes, 5);
    });
  });
}
