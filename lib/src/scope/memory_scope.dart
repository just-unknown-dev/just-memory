import 'dart:async';

/// A cleanup step owned by a [MemoryScope]; may be asynchronous.
typedef DisposeCallback = FutureOr<void> Function();

/// Groups cleanup steps that share one lifetime (a scene, a subsystem) and
/// runs them together, last registered first.
///
/// ```dart
/// final scene = MemoryScope(debugLabel: 'battle');
/// final bullet = bulletPool.acquireScoped(scene);
/// await textures.acquire('boss.png', scope: scene);
/// scene.own(() => print('battle torn down'));
/// // ...
/// await scene.disposeAsync();
/// ```
///
/// Every [own] call adds one callback that lives until the scope is
/// disposed, so give long-lived scopes long-lived things and use a [child]
/// scope for anything acquired per frame or per wave.
class MemoryScope {
  /// Creates an empty scope.
  MemoryScope({this.debugLabel});

  /// A name used in error messages.
  final String? debugLabel;
  final List<DisposeCallback> _callbacks = <DisposeCallback>[];
  bool _isDisposed = false;

  /// Whether [dispose] or [disposeAsync] has run.
  bool get isDisposed => _isDisposed;

  /// How many cleanup callbacks are waiting.
  int get ownedCount => _callbacks.length;

  /// Registers [callback] to run when the scope is disposed. On a scope that
  /// is already disposed, [callback] runs at once (its future, if any, is
  /// not awaited).
  void own(DisposeCallback callback) {
    if (_isDisposed) {
      final result = callback();
      if (result is Future<void>) {
        unawaited(result);
      }
      return;
    }
    _callbacks.add(callback);
  }

  /// Registers [disposer] to run on [value] when the scope is disposed, and
  /// returns [value].
  T ownValue<T>(T value, void Function(T value) disposer) {
    own(() => disposer(value));
    return value;
  }

  /// Creates a scope that is disposed with this one (or earlier, on its
  /// own).
  MemoryScope child({String? debugLabel}) {
    final child = MemoryScope(debugLabel: debugLabel);
    own(child.dispose);
    return child;
  }

  /// Runs every callback, last registered first, without waiting for
  /// asynchronous ones.
  ///
  /// Use [disposeAsync] when a callback returns a future that must finish
  /// (or whose errors must be seen): here such futures run on their own and
  /// their errors go to the current zone as uncaught errors. If synchronous
  /// callbacks throw, the rest still run, and then a [StateError] carrying
  /// the first error is thrown.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    Object? firstError;
    for (var i = _callbacks.length - 1; i >= 0; i--) {
      try {
        final result = _callbacks[i]();
        if (result is Future<void>) {
          unawaited(result);
        }
      } catch (error) {
        firstError ??= error;
      }
    }
    _callbacks.clear();

    if (firstError != null) {
      throw StateError(
        'MemoryScope${_labelSuffix()} disposal encountered an error: '
        '$firstError',
      );
    }
  }

  /// Runs every callback, last registered first, waiting for each one.
  ///
  /// If callbacks throw, the rest still run, and then a [StateError]
  /// carrying the first error is thrown.
  Future<void> disposeAsync() async {
    if (_isDisposed) return;
    _isDisposed = true;

    Object? firstError;
    for (var i = _callbacks.length - 1; i >= 0; i--) {
      try {
        await _callbacks[i]();
      } catch (error) {
        firstError ??= error;
      }
    }
    _callbacks.clear();

    if (firstError != null) {
      throw StateError(
        'MemoryScope${_labelSuffix()} disposal encountered an error: '
        '$firstError',
      );
    }
  }

  String _labelSuffix() => debugLabel == null ? '' : ' "$debugLabel"';
}
