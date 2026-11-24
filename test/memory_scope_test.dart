import 'dart:async';

import 'package:just_memory/just_memory.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryScope', () {
    test('ownValue returns the value and disposes it with the scope', () {
      final scope = MemoryScope();
      final disposed = <List<int>>[];

      final list = scope.ownValue(<int>[1, 2], disposed.add);

      expect(list, [1, 2]);
      expect(scope.ownedCount, 1);
      scope.dispose();
      expect(disposed.single, same(list));
      expect(scope.ownedCount, 0);
    });

    test('a child is disposed with its parent, after newer callbacks', () {
      final log = <String>[];
      final parent = MemoryScope(debugLabel: 'parent');
      parent.own(() => log.add('parent-first'));
      final child = parent.child(debugLabel: 'child');
      child.own(() => log.add('child'));
      parent.own(() => log.add('parent-last'));

      parent.dispose();

      expect(log, ['parent-last', 'child', 'parent-first']);
      expect(child.isDisposed, isTrue);
    });

    test('a child disposed early is not disposed twice', () {
      var runs = 0;
      final parent = MemoryScope();
      final child = parent.child();
      child.own(() => runs++);

      child.dispose();
      parent.dispose();

      expect(runs, 1);
    });

    test('own on a disposed scope runs the callback at once', () {
      final scope = MemoryScope()..dispose();
      var ran = false;

      scope.own(() => ran = true);

      expect(ran, isTrue);
      expect(scope.ownedCount, 0);
    });

    test('dispose runs every callback, then throws the first error', () {
      final log = <String>[];
      final scope = MemoryScope(debugLabel: 'hud');
      scope.own(() => log.add('first'));
      scope.own(() => throw ArgumentError('second'));
      scope.own(() => throw ArgumentError('third'));

      expect(
        scope.dispose,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('"hud"'), contains('third')),
          ),
        ),
      );
      expect(log, ['first']);
      expect(scope.isDisposed, isTrue);
    });

    test('dispose twice runs callbacks once', () {
      var runs = 0;
      final scope = MemoryScope()..own(() => runs++);

      scope.dispose();
      scope.dispose();

      expect(runs, 1);
    });

    test('dispose does not wait for async callbacks', () async {
      final gate = Completer<void>();
      var finished = false;
      final scope = MemoryScope()
        ..own(() async {
          await gate.future;
          finished = true;
        });

      scope.dispose();
      expect(finished, isFalse);

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(finished, isTrue);
    });

    test(
      'disposeAsync runs every callback, then throws the first error',
      () async {
        final log = <String>[];
        final scope = MemoryScope();
        scope.own(() async => log.add('first'));
        scope.own(() async => throw StateError('boom'));

        await expectLater(scope.disposeAsync(), throwsStateError);
        expect(log, ['first']);

        // Already disposed: a second call does nothing.
        await scope.disposeAsync();
      },
    );
  });
}
