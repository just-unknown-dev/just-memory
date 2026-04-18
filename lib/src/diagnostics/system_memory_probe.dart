import 'system_memory_snapshot.dart';
import 'system_memory_probe_stub.dart'
    if (dart.library.js_interop) 'system_memory_probe_web.dart'
    if (dart.library.io) 'system_memory_probe_io.dart';

SystemMemorySnapshot probeSystemMemory() => platformProbeSystemMemory();
