// Generated from reassort_maillots_clean.json. Do not edit by hand.
class SeedProductData {
  const SeedProductData({
    required this.category,
    required this.name,
    required this.variants,
  });

  final String category;
  final String name;
  final List<SeedVariantData> variants;
}

class SeedVariantData {
  const SeedVariantData(this.color, this.size, this.quantity);

  final String color;
  final String size;
  final int quantity;
}

const stockSeedProducts = <SeedProductData>[];

