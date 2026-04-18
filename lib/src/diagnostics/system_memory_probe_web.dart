import 'dart:js_interop';

import 'system_memory_snapshot.dart';

@JS('globalThis')
external _GlobalThis? get _globalThis;

extension type _GlobalThis._(JSObject _) implements JSObject {
  external _Performance? get performance;
}

extension type _Performance._(JSObject _) implements JSObject {
  external _MemoryInfo? get memory;
}

extension type _MemoryInfo._(JSObject _) implements JSObject {
  external JSNumber? get usedJSHeapSize;
  external JSNumber? get totalJSHeapSize;
  external JSNumber? get jsHeapSizeLimit;
}

SystemMemorySnapshot platformProbeSystemMemory() {
  final memory = _globalThis?.performance?.memory;
  if (memory == null) {
    return const SystemMemorySnapshot.unsupported();
  }

  final usedHeap = _toInt(memory.usedJSHeapSize);
  final totalHeap = _toInt(memory.totalJSHeapSize);
  final heapLimit = _toInt(memory.jsHeapSizeLimit);

  final totalBytes = heapLimit > 0
      ? heapLimit
      : (totalHeap > 0 ? totalHeap : 0);
  if (totalBytes <= 0) {
    return SystemMemorySnapshot.unsupported(rssBytes: usedHeap);
  }

  final freeBytes = (totalBytes - usedHeap).clamp(0, totalBytes).toInt();

  return SystemMemorySnapshot(
    totalPhysicalMemoryBytes: totalBytes,
    freePhysicalMemoryBytes: freeBytes,
    rssBytes: totalHeap > 0 ? totalHeap : usedHeap,
    isSupported: true,
  );
}

int _toInt(JSNumber? value) {
  if (value == null) {
    return 0;
  }
  return value.toDartDouble.toInt();
}
