class LeakTracker {
  LeakTracker({this.enabled = true});

  final bool enabled;
  final Map<Object, String> _live = <Object, String>{};

  void track(Object object, {String label = 'resource'}) {
    if (!enabled) return;
    _live[object] = label;
  }

  void untrack(Object object) {
    if (!enabled) return;
    _live.remove(object);
  }

  bool get hasLeaks => _live.isNotEmpty;
  int get leakCount => _live.length;

  Map<String, int> summaryByLabel() {
    final summary = <String, int>{};
    for (final label in _live.values) {
      summary[label] = (summary[label] ?? 0) + 1;
    }
    return summary;
  }

  void clear() => _live.clear();
}
