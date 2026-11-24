/// The counters of one `ObjectPool` at one moment.
class MemoryStats {
  /// Creates a snapshot of pool counters.
  const MemoryStats({
    required this.totalCreated,
    required this.totalAcquired,
    required this.totalReleased,
    required this.inUse,
    required this.available,
    required this.peakInUse,
    required this.peakAvailable,
  });

  /// Objects created over the pool's life.
  final int totalCreated;

  /// Acquire calls over the pool's life.
  final int totalAcquired;

  /// Release calls that returned an object, over the pool's life.
  final int totalReleased;

  /// Objects in use now.
  final int inUse;

  /// Free objects now.
  final int available;

  /// The most objects ever in use at once.
  final int peakInUse;

  /// The most free objects ever held at once.
  final int peakAvailable;

  /// In-use plus free objects.
  int get totalTracked => inUse + available;

  @override
  String toString() {
    return 'MemoryStats(created: $totalCreated, acquired: $totalAcquired, '
        'released: $totalReleased, inUse: $inUse, available: $available, '
        'peakInUse: $peakInUse, peakAvailable: $peakAvailable)';
  }
}
