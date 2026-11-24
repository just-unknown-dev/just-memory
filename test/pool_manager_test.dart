import 'package:just_memory/just_memory.dart';
import 'package:test/test.dart';

void main() {
  tearDown(PoolManager.resetInstance);

  group('PoolManager', () {
    test('registers, finds and unregisters object pools', () {
      final manager = PoolManager.instance;
      final pool = ObjectPool<List<int>>(create: () => <int>[]);

      manager.registerPool('lists', pool);

      expect(manager.hasPool('lists'), isTrue);
      expect(manager.pool<List<int>>('lists'), same(pool));
      expect(manager.tryPool<List<int>>('lists'), same(pool));
      expect(manager.tryPool<List<int>>('missing'), isNull);
      expect(() => manager.pool<List<int>>('missing'), throwsStateError);
      expect(() => manager.registerPool('lists', pool), throwsStateError);

      manager.unregisterPool('lists');
      expect(manager.hasPool('lists'), isFalse);
    });

    test('creates, finds and unregisters arenas', () {
      final manager = PoolManager.instance;

      final arena = manager.createArena('bodies', capacity: 4);

      expect(manager.arena('bodies'), same(arena));
      expect(manager.tryArena('bodies'), same(arena));
      expect(manager.hasArena('bodies'), isTrue);
      expect(() => manager.arena('missing'), throwsStateError);
      expect(
        () => manager.createArena('bodies', capacity: 1),
        throwsStateError,
      );

      manager.unregisterArena('bodies');
      expect(manager.hasArena('bodies'), isFalse);
    });

    test('creates and finds round-robin pools', () {
      final manager = PoolManager.instance;

      final ring = manager.createRoundRobin<int>(
        'ring',
        create: () => 1,
        size: 2,
      );

      expect(manager.roundRobin<int>('ring'), same(ring));
      expect(() => manager.roundRobin<int>('missing'), throwsStateError);
      expect(
        () => manager.registerRoundRobin<int>('ring', ring),
        throwsStateError,
      );
    });

    test('reports stats and releases or clears everything', () {
      final manager = PoolManager.instance;
      final pool = ObjectPool<List<int>>(create: () => <int>[]);
      manager.registerPool('lists', pool);
      final arena = manager.createArena('bodies', capacity: 4);
      pool.acquire();
      arena.allocate();

      final poolStats = manager.getPoolStats()['lists']!;
      final arenaStats = manager.getArenaStats()['bodies']!;
      expect(poolStats.inUse, 1);
      expect(poolStats.total, 1);
      expect(poolStats.totalCreated, 1);
      expect(arenaStats.allocated, 1);
      expect(arenaStats.available, 3);
      expect(arenaStats.utilizationPercent, 25);

      manager.releaseAllPools();
      manager.clearAllArenas();
      expect(pool.inUseCount, 0);
      expect(pool.availableCount, 1);
      expect(arena.allocatedCount, 0);

      manager.clearAll();
      expect(manager.hasPool('lists'), isFalse);
      expect(manager.hasArena('bodies'), isFalse);
      expect(pool.availableCount, 0);
    });

    test('throws after dispose; resetInstance gives a fresh manager', () {
      final manager = PoolManager.instance;
      manager.dispose();
      manager.dispose();

      expect(manager.isDisposed, isTrue);
      expect(manager.tryPool<int>('x'), isNull);
      expect(manager.tryArena('x'), isNull);
      expect(
        () => manager.registerPool('x', ObjectPool<int>(create: () => 0)),
        throwsStateError,
      );

      PoolManager.resetInstance();
      expect(PoolManager.instance, isNot(same(manager)));
      expect(PoolManager.instance.isDisposed, isFalse);
    });
  });
}
