import 'package:just_memory/just_memory.dart';
import 'package:test/test.dart';

void main() {
  group('BudgetedCache', () {
    late List<String> evicted;
    late BudgetedCache<String, int> cache;

    setUp(() {
      evicted = <String>[];
      cache = BudgetedCache<String, int>(
        maxCost: 10,
        estimateCost: (key, value) => value,
        onEvict: (key, value) => evicted.add('$key=$value'),
      );
    });

    test('a value over budget is rejected without flushing the rest', () {
      cache['a'] = 3;
      cache['b'] = 3;

      cache['huge'] = 50;

      expect(evicted, ['huge=50']);
      expect(cache.containsKey('huge'), isFalse);
      expect(cache.length, 2);
      expect(cache.currentCost, 6);
    });

    test('a value over budget still evicts the old value of its key', () {
      cache['a'] = 3;

      cache['a'] = 50;

      expect(evicted, ['a=3', 'a=50']);
      expect(cache.isEmpty, isTrue);
      expect(cache.currentCost, 0);
    });

    test('replacing a value passes the old one to onEvict', () {
      cache['a'] = 1;
      cache['a'] = 2;

      expect(evicted, ['a=1']);
      expect(cache['a'], 2);
      expect(cache.currentCost, 2);
    });

    test('storing the same object again does not evict it', () {
      final objects = BudgetedCache<String, List<int>>(
        maxCost: 10,
        estimateCost: (key, value) => 1,
        onEvict: (key, value) => evicted.add(key),
      );
      final list = <int>[];

      objects['k'] = list;
      objects['k'] = list;

      expect(evicted, isEmpty);
      expect(objects.length, 1);
    });

    test('evicts least recently used entries until the budget fits', () {
      cache['a'] = 4;
      cache['b'] = 4;
      expect(cache['a'], 4); // a is now the most recent

      cache['c'] = 4;

      expect(evicted, ['b=4']);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.currentCost, 8);
    });

    test('containsKey does not count as a use', () {
      cache['a'] = 4;
      cache['b'] = 4;
      expect(cache.containsKey('a'), isTrue);

      cache['c'] = 4;

      expect(evicted, ['a=4']);
    });

    test('clear passes every entry to onEvict, oldest first', () {
      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3;
      expect(cache['a'], 1);
      var lengthSeen = -1;
      final watched = BudgetedCache<String, int>(
        maxCost: 10,
        estimateCost: (key, value) => value,
        onEvict: (key, value) => lengthSeen = cache.length,
      );
      watched['x'] = 1;

      cache.clear();
      expect(evicted, ['b=2', 'c=3', 'a=1']);
      expect(cache.isEmpty, isTrue);
      expect(cache.currentCost, 0);

      watched.clear();
      expect(lengthSeen, 0);
    });

    test('clear without onEvict empties the cache', () {
      final plain = BudgetedCache<String, int>(
        maxCost: 5,
        estimateCost: (key, value) => value,
      );
      plain['a'] = 2;

      plain.clear();

      expect(plain.isEmpty, isTrue);
      expect(plain.currentCost, 0);
    });

    test('remove returns the value without onEvict', () {
      cache['a'] = 4;

      expect(cache.remove('a'), 4);
      expect(cache.remove('a'), isNull);
      expect(evicted, isEmpty);
      expect(cache.currentCost, 0);
    });

    test('a missing key reads as null', () {
      expect(cache['nope'], isNull);
    });

    test('a negative cost is rejected', () {
      expect(() => cache['bad'] = -1, throwsArgumentError);
      expect(cache.isEmpty, isTrue);
    });

    test('stats report size and budget', () {
      cache['a'] = 4;

      final stats = cache.stats;

      expect(stats.entryCount, 1);
      expect(stats.currentCost, 4);
      expect(stats.maxCost, 10);
      expect(stats.utilizationPercent, closeTo(40, 1e-9));
    });
  });
}
