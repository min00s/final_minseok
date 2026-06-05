import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'gemini_repository.dart';

// ── 냉장고 식재료 모델 ─────────────────────────────────────────────
class FridgeItem {
  final String id;
  final String name;
  final String emoji;
  final DateTime addedAt;
  final DateTime? expiryDate;

  FridgeItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.addedAt,
    this.expiryDate,
  });

  // 유통기한까지 남은 일수
  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  // 유통기한 상태
  ExpiryStatus get expiryStatus {
    final days = daysUntilExpiry;
    if (days == null) return ExpiryStatus.unknown;
    if (days < 0) return ExpiryStatus.expired;
    if (days <= 2) return ExpiryStatus.critical;
    if (days <= 5) return ExpiryStatus.warning;
    return ExpiryStatus.good;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'addedAt': addedAt.toIso8601String(),
    'expiryDate': expiryDate?.toIso8601String(),
  };

  factory FridgeItem.fromJson(Map<String, dynamic> json) => FridgeItem(
    id: json['id'],
    name: json['name'],
    emoji: json['emoji'] ?? '🥬',
    addedAt: DateTime.parse(json['addedAt']),
    expiryDate: json['expiryDate'] != null
        ? DateTime.parse(json['expiryDate'])
        : null,
  );
}

enum ExpiryStatus { good, warning, critical, expired, unknown }

// ── 즐겨찾기 모델 ──────────────────────────────────────────────────
class FavoriteRecipe {
  final String id;
  final RecipeRecommendation recipe;
  final DateTime savedAt;

  FavoriteRecipe({
    required this.id,
    required this.recipe,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'savedAt': savedAt.toIso8601String(),
    'title': recipe.title,
    'summary': recipe.summary,
    'calories': recipe.calories,
    'ingredients': recipe.ingredients,
    'steps': recipe.steps,
    'tip': recipe.tip,
  };

  factory FavoriteRecipe.fromJson(Map<String, dynamic> json) => FavoriteRecipe(
    id: json['id'],
    savedAt: DateTime.parse(json['savedAt']),
    recipe: RecipeRecommendation(
      title: json['title'],
      summary: json['summary'] ?? '',
      calories: json['calories'] ?? 0,
      ingredients: List<String>.from(json['ingredients'] ?? []),
      steps: List<String>.from(json['steps'] ?? []),
      tip: json['tip'] ?? '',
    ),
  );
}

// ── StorageService ─────────────────────────────────────────────────
class StorageService {
  static const _fridgeKey = 'fridge_items';
  static const _favoritesKey = 'favorite_recipes';

  // ── 냉장고 ──────────────────────────────────────────────────────
  Future<List<FridgeItem>> loadFridgeItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_fridgeKey) ?? [];
    return raw.map((s) => FridgeItem.fromJson(jsonDecode(s))).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  Future<void> saveFridgeItem(FridgeItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadFridgeItems();
    items.removeWhere((e) => e.id == item.id);
    items.insert(0, item);
    await prefs.setStringList(
      _fridgeKey,
      items.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> deleteFridgeItem(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadFridgeItems();
    items.removeWhere((e) => e.id == id);
    await prefs.setStringList(
      _fridgeKey,
      items.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> updateFridgeItem(FridgeItem item) => saveFridgeItem(item);

  // ── 즐겨찾기 ────────────────────────────────────────────────────
  Future<List<FavoriteRecipe>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_favoritesKey) ?? [];
    return raw.map((s) => FavoriteRecipe.fromJson(jsonDecode(s))).toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  }

  Future<bool> isFavorite(String recipeTitle) async {
    final favorites = await loadFavorites();
    return favorites.any((f) => f.recipe.title == recipeTitle);
  }

  Future<void> addFavorite(RecipeRecommendation recipe) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = await loadFavorites();
    if (favorites.any((f) => f.recipe.title == recipe.title)) return;
    final item = FavoriteRecipe(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      recipe: recipe,
      savedAt: DateTime.now(),
    );
    favorites.insert(0, item);
    await prefs.setStringList(
      _favoritesKey,
      favorites.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> removeFavorite(String recipeTitle) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = await loadFavorites();
    favorites.removeWhere((f) => f.recipe.title == recipeTitle);
    await prefs.setStringList(
      _favoritesKey,
      favorites.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }
}
