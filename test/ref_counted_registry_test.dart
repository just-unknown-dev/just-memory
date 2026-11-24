import 'dart:async';

import 'package:just_memory/just_memory.dart';
import 'package:test/test.dart';

void main() {
  group('RefCountedRegistry', () {
    late List<String> disposed;
    late int loads;

    RefCountedRegistry<String, String> registry({
      FutureOr<String> Function(String key)? loader,
    }) {
      return RefCountedRegistry<String, String>(
        loader:
            loader ??
            (key) {
              loads++;
              return 'v:$key';
            },
        disposer: disposed.add,
      );
    }

    setUp(() {
      disposed = <String>[];
      loads = 0;
    });

    test('concurrent acquires share one load', () async {
      final gate = Completer<String>();
      final reg = registry(
        loader: (key) {
          loads++;
          return gate.future;
        },
      );

      final fa = reg.acquire('tex');
      final fb = reg.acquire('tex');
      expect(reg.isLoading('tex'), isTrue);
      expect(reg.containsKey('tex'), isFalse);

      gate.complete('texture');
      final a = await fa;
      final b = await fb;

      expect(loads, 1);
      expect(a.value, 'texture');
      expect(b.value, 'texture');
      expect(reg.refCountOf('tex'), 2);
      expect(reg.isLoading('tex'), isFalse);
    });

    test(
      'a holder releasing at once cannot free a value another waits for',
      () async {
        final gate = Completer<String>();
        final reg = registry(loader: (_) => gate.future);

        final fa = reg.acquire('tex');
        final fb = reg.acquire('tex');
        gate.complete('texture');

        final a = await fa;
        await a.release();
        final b = await fb;

        expect(disposed, isEmpty);
        expect(b.refCount, 1);
        expect(reg.containsKey('tex'), isTrue);
      },
    );

    test(
      'an acquire counts before a release of the last handle lands',
      () async {
        final reg = registry();
        final first = await reg.acquire('tex');

        final pending = reg.acquire('tex');
        await first.release();
        final second = await pending;

        expect(disposed, isEmpty);
        expect(second.refCount, 1);
      },
    );

    test('works with a synchronous loader', () async {
      final reg = registry();

      final handle = await reg.acquire('a');

      expect(handle.value, 'v:a');
      expect(handle.key, 'a');
    });

    test('release is idempotent', () async {
      final reg = registry();
      final a = await reg.acquire('k');
      final b = await reg.acquire('k');

      await a.release();
      await a.release();

      expect(a.isReleased, isTrue);
      expect(b.refCount, 1);
      expect(disposed, isEmpty);
    });

    test(
      'the last release frees the value; the next acquire reloads',
      () async {
        final reg = registry();
        final handle = await reg.acquire('k');

        await handle.release();
        expect(disposed, ['v:k']);
        expect(reg.containsKey('k'), isFalse);
        expect(reg.refCountOf('k'), 0);

        await reg.acquire('k');
        expect(loads, 2);
      },
    );

    test(
      'a failed load reaches every waiter and the next acquire retries',
      () async {
        var attempt = 0;
        final reg = registry(
          loader: (key) async {
            attempt++;
            if (attempt == 1) throw StateError('disk');
            return 'v:$key';
          },
        );

        final fa = reg.acquire('k');
        final fb = reg.acquire('k');
        await expectLater(fa, throwsStateError);
        await expectLater(fb, throwsStateError);
        expect(reg.isLoading('k'), isFalse);
        expect(reg.containsKey('k'), isFalse);

        final handle = await reg.acquire('k');
        expect(handle.value, 'v:k');
        expect(handle.refCount, 1);
      },
    );

    test('dispose frees everything and leaves old handles inert', () async {
      final reg = registry();
      final stale = await reg.acquire('tex');

      await reg.dispose();
      expect(disposed, ['v:tex']);
      expect(stale.refCount, 0);

      final fresh = await reg.acquire('tex');
      await stale.release();

      expect(fresh.refCount, 1);
      expect(reg.containsKey('tex'), isTrue);
      expect(disposed, ['v:tex']);
    });

    test(
      'a load finishing after dispose stays out and is freed on release',
      () async {
        final gate = Completer<String>();
        final reg = registry(loader: (_) => gate.future);

        final pending = reg.acquire('late');
        await reg.dispose();
        gate.complete('late-value');
        final handle = await pending;

        expect(handle.value, 'late-value');
        expect(reg.containsKey('late'), isFalse);

        await handle.release();
        expect(disposed, ['late-value']);
      },
    );

    test('an acquire after dispose starts a new load', () async {
      final gates = <Completer<String>>[];
      final reg = registry(
        loader: (_) {
          final gate = Completer<String>();
          gates.add(gate);
          return gate.future;
        },
      );

      final old = reg.acquire('k');
      await reg.dispose();
      final fresh = reg.acquire('k');
      expect(gates, hasLength(2));

      gates[1].complete('new');
      gates[0].complete('old');

      expect((await fresh).value, 'new');
      expect((await old).value, 'old');
      expect(reg.refCountOf('k'), 1);
    });

    test('a scope releases its handles', () async {
      final reg = registry();
      final scope = MemoryScope();

      await reg.acquire('a', scope: scope);
      await reg.acquire('b', scope: scope);
      await scope.disposeAsync();

      expect(disposed, unorderedEquals(['v:a', 'v:b']));
    });
  });
}
