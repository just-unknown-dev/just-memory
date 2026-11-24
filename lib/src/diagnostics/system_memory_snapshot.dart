/// The host's memory figures at one moment, as read by
/// `MemoryProfiler.captureSystemMemory`.
///
/// What the figures mean depends on the platform:
///
/// * Windows: physical memory from `GlobalMemoryStatusEx`.
/// * Linux and Android: `MemTotal` and `MemAvailable` (or `MemFree`) from
///   `/proc/meminfo`.
/// * macOS and iOS: total from `hw.memsize`; the free figure is only an
///   estimate, total minus this process's resident set.
/// * Web (where the browser exposes `performance.memory`): the JS heap
///   limit as total, the limit minus the used heap as free, and the heap
///   size as [rssBytes].
class SystemMemorySnapshot {
  /// Creates a snapshot.
  const SystemMemorySnapshot({
    required this.totalPhysicalMemoryBytes,
    required this.freePhysicalMemoryBytes,
    required this.rssBytes,
    required this.isSupported,
  });

  /// A snapshot for a platform that could not be read; only [rssBytes] may
  /// be known.
  const SystemMemorySnapshot.unsupported({this.rssBytes = 0})
    : totalPhysicalMemoryBytes = 0,
      freePhysicalMemoryBytes = 0,
      isSupported = false;

  /// Total physical memory, in bytes.
  final int totalPhysicalMemoryBytes;

  /// Free physical memory, in bytes (see [SystemMemorySnapshot] for how it
  /// is measured).
  final int freePhysicalMemoryBytes;

  /// This process's resident set size, in bytes.
  final int rssBytes;

  /// Whether the total and free figures were read.
  final bool isSupported;

  /// A copy with the given fields replaced.
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

  /// Total minus free physical memory, never below zero.
  int get usedPhysicalMemoryBytes {
    final used = totalPhysicalMemoryBytes - freePhysicalMemoryBytes;
    if (used < 0) {
      return 0;
    }
    return used;
  }

  /// Free as a fraction of total memory; `0` when unsupported.
  double get availabilityRatio {
    if (!isSupported || totalPhysicalMemoryBytes <= 0) {
      return 0.0;
    }
    return freePhysicalMemoryBytes / totalPhysicalMemoryBytes;
  }
}
