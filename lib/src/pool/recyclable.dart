/// Interface for objects that can clear their mutable state before reuse.
///
/// An `ObjectPool` with no `reset` callback calls [reset] on released
/// objects that implement this.
abstract mixin class Recyclable {
  /// Clears this object's state so it can be handed out again.
  void reset();
}
