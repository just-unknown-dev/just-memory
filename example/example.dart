// A tiny "scene" that uses each part of just_memory once.
//
// Run with: dart run example/example.dart
import 'package:just_memory/just_memory.dart';

/// A pooled game object: reset clears it for its next use.
class Bullet with Recyclable {
  double x = 0;
  double y = 0;
  bool active = false;

  @override
  void reset() {
    x = 0;
    y = 0;
    active = false;
  }
}

Future<void> main() async {
  // Everything the scene creates is cleaned up when this scope is disposed.
  final scene = MemoryScope(debugLabel: 'demo-scene');

  // Object pool: reuse bullets instead of allocating one per shot.
  final bullets = ObjectPool<Bullet>(
    create: Bullet.new,
    initialSize: 16,
    maxSize: 64,
    debugLabel: 'bullets',
  );
  final shot = bullets.acquire()
    ..x = 10
    ..active = true;
  bullets.release(shot); // reset() runs, the bullet goes back to the pool
  bullets.acquireScoped(scene); // released when the scene is disposed

  // Reference-counted resources: load once, free after the last release.
  final textures = RefCountedRegistry<String, String>(
    loader: (path) async => 'pixels of $path',
    disposer: (pixels) => print('freed $pixels'),
  );
  final hero = await textures.acquire('hero.png', scope: scene);
  final heroAgain = await textures.acquire('hero.png');
  print('${hero.value} is held ${hero.refCount} times');
  await heroAgain.release();

  // Budgeted cache: bounded by total cost, least recently used goes first.
  final glyphs = BudgetedCache<String, List<int>>(
    maxCost: 1024,
    estimateCost: (key, bytes) => bytes.length,
    onEvict: (key, bytes) => print('evicted glyph $key'),
  );
  glyphs['A'] = List<int>.filled(600, 0);
  glyphs['B'] = List<int>.filled(600, 0); // pushes 'A' out

  // Arena: transform state for many entities in one flat Float64List.
  final bodies = MemoryArena(capacity: 1000);
  final body = bodies.allocate();
  bodies.setPosition(body, 0, 0);
  bodies.setVelocity(body, 120, -40);
  bodies.applyVelocityAll(1 / 60);
  final position = TypedVec2(bodies, body);
  print('body moved to $position, ${position.length.toStringAsFixed(3)} away');

  // Profiler: what the pools and caches hold right now.
  final profiler = MemoryProfiler()
    ..trackPool('bullets', bullets)
    ..trackCache('glyphs', glyphs);
  final snapshot = profiler.capture();
  print('bullets: ${snapshot.poolStats['bullets']}');
  print('glyph cache: ${snapshot.cacheStats['glyphs']!.currentCost} bytes');

  final system = MemoryProfiler.captureSystemMemory();
  if (system.isSupported) {
    final freePercent = (system.availabilityRatio * 100).toStringAsFixed(0);
    print('system memory: $freePercent% free');
  }

  // Tear the scene down: the scoped bullet and the texture are released.
  await scene.disposeAsync();
  print(
    'after teardown: ${bullets.inUseCount} bullets in use, '
    'texture loaded: ${textures.containsKey('hero.png')}',
  );
}
