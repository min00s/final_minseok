import 'package:flutter/material.dart';
import 'storage_service.dart';
import 'gemini_repository.dart';
import 'main.dart' show AppColors;

class FridgeScreen extends StatefulWidget {
  final GeminiRepository geminiRepo;
  const FridgeScreen({super.key, required this.geminiRepo});

  @override
  State<FridgeScreen> createState() => _FridgeScreenState();
}

class _FridgeScreenState extends State<FridgeScreen> {
  final _storage = StorageService();
  List<FridgeItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await _storage.loadFridgeItems();
    setState(() { _items = items; _isLoading = false; });
  }

  Future<void> _deleteItem(FridgeItem item) async {
    await _storage.deleteFridgeItem(item.id);
    await _loadItems();
  }

  Future<void> _editItem(FridgeItem item) async {
    await showDialog(
      context: context,
      builder: (_) => _FridgeItemDialog(
        storage: _storage,
        geminiRepo: widget.geminiRepo,
        existingItem: item,
      ),
    );
    await _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('나의 냉장고 🧊',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
                fontSize: 20)),
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: AppColors.primary))
          : _items.isEmpty
          ? _buildEmptyState()
          : Column(
        children: [
          _buildExpiryBanner(),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.05,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _items.length,
              itemBuilder: (_, i) => _FridgeItemCard(
                item: _items[i],
                onEdit: () => _editItem(_items[i]),
                onDelete: () => _deleteItem(_items[i]),
              ),
            ),
          ),
          _buildParseButton(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🧊', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text('냉장고가 비어있어요',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark)),
          const SizedBox(height: 8),
          Text('식재료를 탐지하고 냉장고에 추가해보세요!',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildExpiryBanner() {
    final expiring = _items.where((item) {
      final s = item.expiryStatus;
      return s == ExpiryStatus.critical || s == ExpiryStatus.expired;
    }).toList();
    if (expiring.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${expiring.map((e) => e.name).join(", ")} 유통기한이 임박했어요!',
              style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParseButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () =>
              Navigator.pop(context, _items.map((e) => e.name).toList()),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30)),
            elevation: 0,
          ),
          child: const Text('냉장고 파먹기 🍳',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

// ── 냉장고 아이템 카드 ─────────────────────────────────────────────
class _FridgeItemCard extends StatelessWidget {
  final FridgeItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _FridgeItemCard(
      {required this.item, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final status = item.expiryStatus;
    final borderColor = _borderColor(status);

    return GestureDetector(
      onTap: onEdit,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.emoji,
                      style: const TextStyle(fontSize: 32)),
                  const SizedBox(height: 6),
                  Text(item.name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(_dateLabel(),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textGrey)),
                  if (item.expiryDate != null) ...[
                    const SizedBox(height: 2),
                    Text(_expiryLabel(status),
                        style: TextStyle(
                            fontSize: 11,
                            color: _textColor(status),
                            fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      size: 13, color: AppColors.textGrey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel() {
    final d = item.addedAt;
    return '${d.year.toString().substring(2)}.${d.month}.${d.day} 추가';
  }

  String _expiryLabel(ExpiryStatus status) {
    final days = item.daysUntilExpiry!;
    if (status == ExpiryStatus.expired) return '기한 초과';
    if (days == 0) return '오늘 만료';
    if (days == 1) return '내일 만료';
    return '$days일 남음';
  }

  Color _borderColor(ExpiryStatus status) {
    switch (status) {
      case ExpiryStatus.expired:   return Colors.red.shade300;
      case ExpiryStatus.critical:  return Colors.orange.shade300;
      case ExpiryStatus.warning:   return Colors.yellow.shade600;
      default:                     return AppColors.border;
    }
  }

  Color _textColor(ExpiryStatus status) {
    switch (status) {
      case ExpiryStatus.expired:   return Colors.red;
      case ExpiryStatus.critical:  return Colors.orange;
      case ExpiryStatus.warning:   return Colors.amber.shade700;
      default:                     return AppColors.primary;
    }
  }
}

// ── 식재료 추가/수정 다이얼로그 ───────────────────────────────────
class _FridgeItemDialog extends StatefulWidget {
  final StorageService storage;
  final GeminiRepository geminiRepo;
  final FridgeItem? existingItem;
  final String? initialName;

  const _FridgeItemDialog({
    required this.storage,
    required this.geminiRepo,
    this.existingItem,
    this.initialName,
  });

  @override
  State<_FridgeItemDialog> createState() => _FridgeItemDialogState();
}

class _FridgeItemDialogState extends State<_FridgeItemDialog> {
  late TextEditingController _nameController;
  late TextEditingController _emojiController;
  DateTime? _expiryDate;
  bool _loadingAiSuggestion = false;
  String? _aiSuggestion;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
        text: widget.existingItem?.name ?? widget.initialName ?? '');
    _emojiController = TextEditingController(
        text: widget.existingItem?.emoji ?? '🥬');
    _expiryDate = widget.existingItem?.expiryDate;
    if (widget.existingItem == null &&
        (widget.initialName?.isNotEmpty ?? false)) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _getAiExpiryHint());
    }
  }

  Future<void> _getAiExpiryHint() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() { _loadingAiSuggestion = true; _aiSuggestion = null; });
    try {
      final hint = await widget.geminiRepo.getExpiryHint(name);
      setState(() { _aiSuggestion = hint; _loadingAiSuggestion = false; });
    } catch (_) {
      setState(() => _loadingAiSuggestion = false);
    }
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 7)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: '유통기한 선택',
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final item = FridgeItem(
      id: widget.existingItem?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      emoji: _emojiController.text.trim().isNotEmpty
          ? _emojiController.text.trim()
          : '🥬',
      addedAt: widget.existingItem?.addedAt ?? DateTime.now(),
      expiryDate: _expiryDate,
    );
    await widget.storage.saveFridgeItem(item);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        widget.existingItem == null ? '냉장고에 추가' : '식재료 수정',
        style: const TextStyle(
            fontWeight: FontWeight.bold, color: AppColors.textDark),
      ),
      // ← overflow 방지: IntrinsicHeight + SingleChildScrollView
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 58,
                    child: TextField(
                      controller: _emojiController,
                      style: const TextStyle(fontSize: 26),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: '식재료 이름',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onSubmitted: (_) => _getAiExpiryHint(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loadingAiSuggestion ? null : _getAiExpiryHint,
                  icon: _loadingAiSuggestion
                      ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.secondary))
                      : const Icon(Icons.auto_awesome,
                      size: 15, color: AppColors.secondary),
                  label: const Text('AI 유통기한 추천',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.secondary)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.secondary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (_aiSuggestion != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8EC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💡 ', style: TextStyle(fontSize: 13)),
                      Expanded(
                        child: Text(_aiSuggestion!,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.secondary)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text('유통기한',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textDark)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickExpiryDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _expiryDate == null
                              ? '날짜를 선택하세요 (선택사항)'
                              : '${_expiryDate!.year}.${_expiryDate!.month}.${_expiryDate!.day}',
                          style: TextStyle(
                              color: _expiryDate == null
                                  ? AppColors.textGrey
                                  : AppColors.textDark,
                              fontSize: 13),
                        ),
                      ),
                      if (_expiryDate != null)
                        GestureDetector(
                          onTap: () => setState(() => _expiryDate = null),
                          child: const Icon(Icons.close,
                              size: 15, color: AppColors.textGrey),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소',
              style: TextStyle(color: AppColors.textGrey)),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('저장'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emojiController.dispose();
    super.dispose();
  }
}

// ── 탐지 결과에서 냉장고 추가 다이얼로그 ──────────────────────────
class AddToFridgeDialog extends StatefulWidget {
  final List<String> detectedItems;
  final StorageService storage;
  final GeminiRepository geminiRepo;

  const AddToFridgeDialog({
    super.key,
    required this.detectedItems,
    required this.storage,
    required this.geminiRepo,
  });

  @override
  State<AddToFridgeDialog> createState() => _AddToFridgeDialogState();
}

class _AddToFridgeDialogState extends State<AddToFridgeDialog> {
  late List<bool> _selected;

  static const Map<String, String> _emojiMap = {
    '계란': '🥚', '달걀': '🥚', '양파': '🧅', '감자': '🥔', '당근': '🥕',
    '토마토': '🍅', '대파': '🌿', '마늘': '🧄', '두부': '🟫', '고기': '🥩',
    '돼지고기': '🥩', '소고기': '🥩', '닭고기': '🍗', '생선': '🐟',
    '배추': '🥬', '시금치': '🥬', '오이': '🥒', '고추': '🌶️',
    '버섯': '🍄', '사과': '🍎', '바나나': '🍌', '우유': '🥛',
    '치즈': '🧀', '버터': '🧈', '김치': '🌶️',
  };

  @override
  void initState() {
    super.initState();
    _selected = List.filled(widget.detectedItems.length, true);
  }

  String _getEmoji(String name) {
    for (final key in _emojiMap.keys) {
      if (name.contains(key)) return _emojiMap[key]!;
    }
    return '🥬';
  }

  Future<void> _addSelected() async {
    for (int i = 0; i < widget.detectedItems.length; i++) {
      if (!_selected[i]) continue;
      final name = widget.detectedItems[i];
      await widget.storage.saveFridgeItem(FridgeItem(
        id: '${DateTime.now().millisecondsSinceEpoch}_$i',
        name: name,
        emoji: _getEmoji(name),
        addedAt: DateTime.now(),
      ));
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('냉장고에 추가',
          style: TextStyle(
              fontWeight: FontWeight.bold, color: AppColors.textDark)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('추가할 식재료를 선택하세요',
                style: TextStyle(
                    color: Colors.grey.shade500, fontSize: 13)),
            const SizedBox(height: 10),
            ...widget.detectedItems.asMap().entries.map((e) =>
                CheckboxListTile(
                  value: _selected[e.key],
                  onChanged: (v) =>
                      setState(() => _selected[e.key] = v ?? false),
                  title: Text('${_getEmoji(e.value)}  ${e.value}',
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textDark)),
                  activeColor: AppColors.primary,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소',
              style: TextStyle(color: AppColors.textGrey)),
        ),
        ElevatedButton(
          onPressed: _selected.any((s) => s) ? _addSelected : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('추가'),
        ),
      ],
    );
  }
}
