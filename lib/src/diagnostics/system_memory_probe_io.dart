import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'system_memory_snapshot.dart';

typedef _GlobalMemoryStatusExNative =
    Int32 Function(Pointer<_MemoryStatusEx> memoryStatus);
typedef _GlobalMemoryStatusExDart =
    int Function(Pointer<_MemoryStatusEx> memoryStatus);

typedef _SysctlByNameNative =
    Int32 Function(
      Pointer<Utf8> name,
      Pointer<Void> oldPointer,
      Pointer<IntPtr> oldLength,
      Pointer<Void> newPointer,
      IntPtr newLength,
    );
typedef _SysctlByNameDart =
    int Function(
      Pointer<Utf8> name,
      Pointer<Void> oldPointer,
      Pointer<IntPtr> oldLength,
      Pointer<Void> newPointer,
      int newLength,
    );

final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;

  @Uint32()
  external int dwMemoryLoad;

  @Uint64()
  external int ullTotalPhys;

  @Uint64()
  external int ullAvailPhys;

  @Uint64()
  external int ullTotalPageFile;

  @Uint64()
  external int ullAvailPageFile;

  @Uint64()
  external int ullTotalVirtual;

  @Uint64()
  external int ullAvailVirtual;

  @Uint64()
  external int ullAvailExtendedVirtual;
}

SystemMemorySnapshot platformProbeSystemMemory() {
  final rssBytes = ProcessInfo.currentRss;

  try {
    if (Platform.isWindows) {
      return _captureWindowsMemory(rssBytes);
    }
    if (Platform.isLinux || Platform.isAndroid) {
      return _captureProcMemory(rssBytes);
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return _captureDarwinMemory(rssBytes);
    }
  } catch (_) {
    return SystemMemorySnapshot.unsupported(rssBytes: rssBytes);
  }

  return SystemMemorySnapshot.unsupported(rssBytes: rssBytes);
}

SystemMemorySnapshot _captureWindowsMemory(int rssBytes) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final globalMemoryStatusEx = kernel32
      .lookupFunction<_GlobalMemoryStatusExNative, _GlobalMemoryStatusExDart>(
        'GlobalMemoryStatusEx',
      );
  final memoryStatus = calloc<_MemoryStatusEx>();

  try {
    memoryStatus.ref.dwLength = sizeOf<_MemoryStatusEx>();
    final result = globalMemoryStatusEx(memoryStatus);
    if (result == 0) {
      return SystemMemorySnapshot.unsupported(rssBytes: rssBytes);
    }

    return SystemMemorySnapshot(
      totalPhysicalMemoryBytes: memoryStatus.ref.ullTotalPhys,
      freePhysicalMemoryBytes: memoryStatus.ref.ullAvailPhys,
      rssBytes: rssBytes,
      isSupported: true,
    );
  } finally {
    calloc.free(memoryStatus);
  }
}

SystemMemorySnapshot _captureProcMemory(int rssBytes) {
  final file = File('/proc/meminfo');
  if (!file.existsSync()) {
    return SystemMemorySnapshot.unsupported(rssBytes: rssBytes);
  }

  final output = file.readAsStringSync();
  final totalKb = _parseMemInfoInt(output, 'MemTotal');
  final freeKb =
      _parseMemInfoInt(output, 'MemAvailable') ??
      _parseMemInfoInt(output, 'MemFree');

  if (totalKb == null || freeKb == null) {
    return SystemMemorySnapshot.unsupported(rssBytes: rssBytes);
  }

  return SystemMemorySnapshot(
    totalPhysicalMemoryBytes: totalKb * 1024,
    freePhysicalMemoryBytes: freeKb * 1024,
    rssBytes: rssBytes,
    isSupported: true,
  );
}

SystemMemorySnapshot _captureDarwinMemory(int rssBytes) {
  final libSystem = DynamicLibrary.process();
  final sysctlByName = libSystem
      .lookupFunction<_SysctlByNameNative, _SysctlByNameDart>('sysctlbyname');
  final name = 'hw.memsize'.toNativeUtf8();
  final totalBytesPointer = calloc<Uint64>();
  final lengthPointer = calloc<IntPtr>()..value = sizeOf<Uint64>();

  try {
    final result = sysctlByName(
      name,
      totalBytesPointer.cast<Void>(),
      lengthPointer,
      nullptr,
      0,
    );

    if (result != 0) {
      return SystemMemorySnapshot.unsupported(rssBytes: rssBytes);
    }

    final totalBytes = totalBytesPointer.value;
    final freeEstimate = totalBytes > rssBytes ? totalBytes - rssBytes : 0;

    return SystemMemorySnapshot(
      totalPhysicalMemoryBytes: totalBytes,
      freePhysicalMemoryBytes: freeEstimate,
      rssBytes: rssBytes,
      isSupported: true,
    );
  } finally {
    calloc.free(name);
    calloc.free(totalBytesPointer);
    calloc.free(lengthPointer);
  }
}

int? _parseMemInfoInt(String source, String key) {
  final match = RegExp(
    '$key:\\s*(\\d+)\\s*kB',
    multiLine: true,
  ).firstMatch(source);
  return match == null ? null : int.tryParse(match.group(1)!);
}
