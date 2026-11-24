/// The size and budget of one `BudgetedCache` at one moment.
class CacheBudgetStats {
  /// Creates a snapshot of cache size and budget.
  const CacheBudgetStats({
    required this.entryCount,
    required this.currentCost,
    required this.maxCost,
  });

  /// Entries held.
  final int entryCount;

  /// The total cost of the entries held.
  final int currentCost;

  /// The cache's budget.
  final int maxCost;

  /// [currentCost] as a percentage of [maxCost].
  double get utilizationPercent =>
      maxCost > 0 ? (currentCost / maxCost) * 100 : 0;
}
