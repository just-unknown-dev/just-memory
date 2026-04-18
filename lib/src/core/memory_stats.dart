class MemoryStats {
  const MemoryStats({
    required this.totalCreated,
    required this.totalAcquired,
    required this.totalReleased,
    required this.inUse,
    required this.available,
    required this.peakInUse,
    required this.peakAvailable,
  });

  final int totalCreated;
  final int totalAcquired;
  final int totalReleased;
  final int inUse;
  final int available;
  final int peakInUse;
  final int peakAvailable;

  int get totalTracked => inUse + available;

  @override
  String toString() {
    return 'MemoryStats(created: $totalCreated, acquired: $totalAcquired, '
        'released: $totalReleased, inUse: $inUse, available: $available, '
        'peakInUse: $peakInUse, peakAvailable: $peakAvailable)';
  }
}
