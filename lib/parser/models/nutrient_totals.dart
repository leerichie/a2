class NutrientTotals {
  const NutrientTotals({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    this.fatG,
    this.fibreG,
  });
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double? fatG;
  final double? fibreG;
}
