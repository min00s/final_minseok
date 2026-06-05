import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import 'config.dart';
import 'gemini_repository.dart';
import 'storage_service.dart';
import 'fridge_screen.dart';
import 'favorites_screen.dart';

// ── 앱 전체 테마 컬러 ──────────────────────────────────────────────
class AppColors {
  static const bg        = Color(0xFFFDF6EE);
  static const primary   = Color(0xFF5C8A5A);
  static const secondary = Color(0xFFB87333);
  static const accent    = Color(0xFFE8A87C);
  static const card      = Color(0xFFFFFFFF);
  static const textDark  = Color(0xFF3A2E1E);
  static const textGrey  = Color(0xFF8C7B6B);
  static const border    = Color(0xFFE0D4C3);
}

void main() => runApp(const KingJangoApp());

class KingJangoApp extends StatelessWidget {
  const KingJangoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: AppColors.bg,
      ),
      home: const MainScreen(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  메인 화면
// ═══════════════════════════════════════════════════════════════════
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  File? _image;
  final picker = ImagePicker();

  String _statusText = '하단 버튼으로 식재료를 인식해보세요!';
  bool _isLoading = false;
  List<String> _detectedItems = [];

  late final GeminiRepository _geminiRepo;
  final _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _geminiRepo = GeminiRepository(apiKey: geminiApiKey);
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile == null) return;
    setState(() {
      _image = File(pickedFile.path);
      _isLoading = true;
      _statusText = '모델이 식재료를 인식 중...';
      _detectedItems = [];
    });
    await _runGeminiDetection(_image!);
  }

  Future<void> _runGeminiDetection(File image) async {
    try {
      final items = await _geminiRepo.detectIngredientsFromImage(image);
      setState(() {
        _detectedItems = items;
        _isLoading = false;
        _statusText = items.isEmpty
            ? '식재료를 인식하지 못했습니다.\n다시 시도해 주세요.'
            : '발견된 식재료:';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusText = '인식 중 오류가 발생했습니다.';
      });
    }
  }

  Future<void> _showAddToFridgeDialog() async {
    if (_detectedItems.isEmpty) {
      _showSnack('먼저 식재료를 인식해 주세요!');
      return;
    }
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => AddToFridgeDialog(
        detectedItems: _detectedItems,
        storage: _storage,
        geminiRepo: _geminiRepo,
      ),
    );
    if (added == true && mounted) {
      _showSnack('냉장고에 추가됐어요! 🧊', color: AppColors.primary);
    }
  }

  void _goToRecipe(List<String> ingredients) {
    if (ingredients.isEmpty) {
      _showSnack('먼저 식재료를 인식해 주세요!');
      return;
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => RecipeScreen(
          ingredients: ingredients, geminiRepo: _geminiRepo),
    ));
  }

  Future<void> _openFridge() async {
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
          builder: (_) => FridgeScreen(geminiRepo: _geminiRepo)),
    );
    if (result != null && result.isNotEmpty && mounted) {
      _goToRecipe(result);
    }
  }

  void _showSnack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color ?? AppColors.secondary,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading ? _buildLoadingScreen() : _buildMainScreen();
  }

  Widget _buildMainScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _detectedItems.isEmpty
          ? _buildHomePage()
          : _buildResultPage(),
    );
  }

  // ── 탐지 전: 홈 이미지 + 버튼 ────────────────────────────────────
  Widget _buildHomePage() {
    return Column(
      children: [
        Expanded(
          child: Image.asset(
            'assets/homepage.png',
            fit: BoxFit.contain,
            alignment: Alignment.center,
          ),
        ),
        _buildBottomButtons(),
      ],
    );
  }

  // ── 탐지 후: 깔끔한 결과 화면 ─────────────────────────────────────
  Widget _buildResultPage() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 탐지된 사진
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _image != null
                      ? Image.file(_image!,
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.cover)
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 20),

                // 발견된 식재료 카드
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondary.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🥬 발견된 식재료',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _detectedItems
                            .map((item) => _IngredientChip(label: item))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 액션 버튼 2개
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showAddToFridgeDialog,
                        icon: const Icon(Icons.kitchen, size: 17),
                        label: const Text('냉장고에 추가',
                            style: TextStyle(fontSize: 14)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.secondary,
                          side: const BorderSide(
                              color: AppColors.secondary, width: 1.5),
                          padding:
                          const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _goToRecipe(_detectedItems),
                        icon: const Icon(Icons.restaurant_menu, size: 17),
                        label: const Text('레시피 추천',
                            style: TextStyle(fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding:
                          const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 다시 찍기 버튼
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _detectedItems = [];
                      _image = null;
                      _statusText = '하단 버튼으로 식재료를 인식해보세요!';
                    }),
                    icon: const Icon(Icons.arrow_back,
                        size: 16, color: AppColors.textGrey),
                    label: const Text('돌아가기',
                        style: TextStyle(
                            color: AppColors.textGrey, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
        _buildBottomButtons(),
      ],
    );
  }

  Widget _buildBottomButtons() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _BottomIconButton(
            icon: Icons.camera_alt,
            label: '카메라',
            onTap: () => _pickImage(ImageSource.camera),
          ),
          _BottomIconButton(
            icon: Icons.photo_library,
            label: '갤러리',
            onTap: () => _pickImage(ImageSource.gallery),
          ),
          _BottomIconButton(
            icon: Icons.kitchen,
            label: '냉장고',
            onTap: _openFridge,
          ),
          _BottomIconButton(
            icon: Icons.star,
            label: '즐겨찾기',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FavoritesScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/homepage.png',
                width: 260, fit: BoxFit.contain),
            const SizedBox(height: 36),
            const CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 4),
            const SizedBox(height: 20),
            const Text('모델이 식재료를 인식 중입니다...',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textGrey)),
            const SizedBox(height: 6),
            const Text('잠시만 기다려 주세요.',
                style:
                TextStyle(fontSize: 13, color: AppColors.textGrey)),
          ],
        ),
      ),
    );
  }

}

// ── 하단 아이콘 버튼 ───────────────────────────────────────────────
class _BottomIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BottomIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFF5EDE0),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
            child: Icon(icon, color: AppColors.secondary, size: 30),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── 재료 칩 ────────────────────────────────────────────────────────
class _IngredientChip extends StatelessWidget {
  final String label;
  const _IngredientChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.eco, size: 13, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  레시피 추천 화면
// ═══════════════════════════════════════════════════════════════════
class RecipeScreen extends StatefulWidget {
  final List<String> ingredients;
  final GeminiRepository geminiRepo;

  const RecipeScreen(
      {super.key, required this.ingredients, required this.geminiRepo});

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  List<RecipeRecommendation> _recipes = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchRecipes();
  }

  Future<void> _fetchRecipes() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final recipes = await widget.geminiRepo
          .getRecipeRecommendations(widget.ingredients);
      setState(() { _recipes = recipes; _isLoading = false; });
    } catch (e) {
      setState(() { _errorMessage = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('레시피 추천 🍽️',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.textDark)),
        backgroundColor: AppColors.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textDark),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.secondary),
            onPressed: _isLoading ? null : _fetchRecipes,
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🧊 내 식재료',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.ingredients
                      .map((item) => _IngredientChip(label: item))
                      .toList(),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.accent),
            SizedBox(height: 16),
            Text('Gemini가 레시피를 생성 중입니다...',
                style: TextStyle(color: AppColors.textGrey, fontSize: 15)),
          ],
        ),
      );
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _fetchRecipes,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    if (_recipes.isEmpty) {
      return const Center(
          child: Text('추천할 레시피를 찾지 못했습니다.',
              style: TextStyle(color: AppColors.textGrey, fontSize: 15)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _recipes.length,
      itemBuilder: (_, i) => _RecipeCard(recipe: _recipes[i]),
    );
  }
}

// ── 레시피 카드 ────────────────────────────────────────────────────
class _RecipeCard extends StatefulWidget {
  final RecipeRecommendation recipe;
  const _RecipeCard({required this.recipe});

  @override
  State<_RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<_RecipeCard> {
  bool _expanded = false;
  bool _isFavorite = false;
  final _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final fav = await _storage.isFavorite(widget.recipe.title);
    if (mounted) setState(() => _isFavorite = fav);
  }

  Future<void> _toggleFavorite() async {
    if (_isFavorite) {
      await _storage.removeFavorite(widget.recipe.title);
    } else {
      await _storage.addFavorite(widget.recipe);
    }
    setState(() => _isFavorite = !_isFavorite);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isFavorite ? '즐겨찾기에 추가됐어요 ⭐' : '즐겨찾기에서 삭제됐어요'),
        backgroundColor: _isFavorite
            ? const Color(0xFF9B7940)
            : Colors.grey.shade600,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.07),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.restaurant,
                        color: AppColors.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(recipe.title,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textDark)),
                        const SizedBox(height: 2),
                        Text(recipe.summary,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textGrey)),
                      ],
                    ),
                  ),
                  if (recipe.calories > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${recipe.calories}kcal',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.secondary,
                              fontWeight: FontWeight.bold)),
                    ),
                  IconButton(
                    icon: Icon(
                      _isFavorite ? Icons.star : Icons.star_border,
                      color: _isFavorite
                          ? const Color(0xFF9B7940)
                          : AppColors.border,
                      size: 22,
                    ),
                    onPressed: _toggleFavorite,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textGrey, size: 20),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 14),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 12),
                _sectionTitle('📋 재료'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: recipe.ingredients
                      .map((ing) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primary
                              .withValues(alpha: 0.2)),
                    ),
                    child: Text(ing,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary)),
                  ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                _sectionTitle('🍳 조리 순서'),
                const SizedBox(height: 8),
                ...recipe.steps.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text('${e.key + 1}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(e.value,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textDark))),
                    ],
                  ),
                )),
                if (recipe.tip.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8EC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('💡 ', style: TextStyle(fontSize: 14)),
                        Expanded(
                          child: Text(recipe.tip,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.secondary)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: AppColors.textDark));
}
