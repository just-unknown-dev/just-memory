import 'dart:async';

typedef DisposeCallback = FutureOr<void> Function();

class MemoryScope {
  MemoryScope({this.debugLabel});

  final String? debugLabel;
  final List<DisposeCallback> _callbacks = <DisposeCallback>[];
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;
  int get ownedCount => _callbacks.length;

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

  T ownValue<T>(T value, void Function(T value) disposer) {
    own(() => disposer(value));
    return value;
  }

  MemoryScope child({String? debugLabel}) {
    final child = MemoryScope(debugLabel: debugLabel);
    own(child.dispose);
    return child;
  }

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
        'MemoryScope disposal encountered an error: $firstError',
      );
    }
  }

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
        'MemoryScope disposal encountered an error: $firstError',
      );
    }
  }
}
