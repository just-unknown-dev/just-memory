/// Counts objects that were created but never disposed, by label.
///
/// Call [track] when an object is created and [untrack] when it is
/// disposed; whatever is still tracked is a leak. Objects are tracked by
/// identity, and the tracker holds strong references to them, so keep it
/// for debug builds and pass `enabled: false` (or skip creating it) in
/// release builds.
class LeakTracker {
  /// Creates a tracker; with [enabled] false, every call does nothing.
  LeakTracker({this.enabled = true});

  /// Whether [track] and [untrack] record anything.
  final bool enabled;
  final Map<Object, String> _live = Map<Object, String>.identity();

  /// Records [object] as live under [label].
  void track(Object object, {String label = 'resource'}) {
    if (!enabled) return;
    _live[object] = label;
  }

  /// Records [object] as disposed.
  void untrack(Object object) {
    if (!enabled) return;
    _live.remove(object);
  }

  /// Whether any tracked object has not been untracked.
  bool get hasLeaks => _live.isNotEmpty;

  /// How many tracked objects have not been untracked.
  int get leakCount => _live.length;

  /// How many objects are still tracked, per label.
  Map<String, int> summaryByLabel() {
    final summary = <String, int>{};
    for (final label in _live.values) {
      summary[label] = (summary[label] ?? 0) + 1;
    }
    return summary;
  }

  /// Forgets every tracked object.
  void clear() => _live.clear();
}
