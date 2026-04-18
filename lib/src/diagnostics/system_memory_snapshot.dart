class SystemMemorySnapshot {
  const SystemMemorySnapshot({
    required this.totalPhysicalMemoryBytes,
    required this.freePhysicalMemoryBytes,
    required this.rssBytes,
    required this.isSupported,
  });

  const SystemMemorySnapshot.unsupported({this.rssBytes = 0})
    : totalPhysicalMemoryBytes = 0,
      freePhysicalMemoryBytes = 0,
      isSupported = false;

  final int totalPhysicalMemoryBytes;
  final int freePhysicalMemoryBytes;
  final int rssBytes;
  final bool isSupported;

  SystemMemorySnapshot copyWith({
    int? totalPhysicalMemoryBytes,
    int? freePhysicalMemoryBytes,
    int? rssBytes,
    bool? isSupported,
  }) {
    return SystemMemorySnapshot(
      totalPhysicalMemoryBytes:
          totalPhysicalMemoryBytes ?? this.totalPhysicalMemoryBytes,
      freePhysicalMemoryBytes:
          freePhysicalMemoryBytes ?? this.freePhysicalMemoryBytes,
      rssBytes: rssBytes ?? this.rssBytes,
      isSupported: isSupported ?? this.isSupported,
    );
  }

  int get usedPhysicalMemoryBytes {
    final used = totalPhysicalMemoryBytes - freePhysicalMemoryBytes;
    if (used < 0) {
      return 0;
    }
    return used;
  }

  double get availabilityRatio {
    if (!isSupported || totalPhysicalMemoryBytes <= 0) {
      return 0.0;
    }
    return freePhysicalMemoryBytes / totalPhysicalMemoryBytes;
  }
}
