/// Interface for objects that can clear their mutable state before reuse.
abstract mixin class Recyclable {
  void reset();
}
