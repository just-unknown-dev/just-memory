class CacheBudgetStats {
  const CacheBudgetStats({
    required this.entryCount,
    required this.currentCost,
    required this.maxCost,
  });

  final int entryCount;
  final int currentCost;
  final int maxCost;

  double get utilizationPercent =>
      maxCost > 0 ? (currentCost / maxCost) * 100 : 0;
}
