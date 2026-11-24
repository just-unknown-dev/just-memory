import 'system_memory_snapshot.dart';

/// The probe for platforms with neither `dart:io` nor JS interop: reports
/// nothing.
SystemMemorySnapshot platformProbeSystemMemory() {
  return const SystemMemorySnapshot.unsupported();
}
