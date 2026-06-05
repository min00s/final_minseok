import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

// ── 레시피 데이터 모델 ──────────────────────────────────────────────
class RecipeRecommendation {
  final String title;
  final String summary;
  final int calories;
  final List<String> ingredients;
  final List<String> steps;
  final String tip;

  const RecipeRecommendation({
    required this.title,
    required this.summary,
    this.calories = 0,
    required this.ingredients,
    required this.steps,
    required this.tip,
  });

  factory RecipeRecommendation.fromJson(Map<String, dynamic> json, int index) {
    return RecipeRecommendation(
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? json['title']
          : '추천 레시피 ${index + 1}',
      summary: json['summary'] ?? '',
      calories: json['calories'] is int ? json['calories'] : 0,
      ingredients: _toStringList(json['ingredients']),
      steps: _toStringList(json['steps']),
      tip: json['tip'] ?? '',
    );
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }
}

// ── GeminiRepository ───────────────────────────────────────────────
class GeminiRepository {
  static const _modelNames = [
    'gemini-2.0-flash-001',
    'gemini-2.0-flash',
    'gemini-2.0-flash-lite',
  ];

  final String apiKey;

  GeminiRepository({required this.apiKey});

  // 1) 이미지에서 식재료 추가 탐지 (Vision)
  Future<List<String>> detectIngredientsFromImage(
      File imageFile, {
        List<String> alreadyDetected = const [],
      }) async {
    final imageBytes = await imageFile.readAsBytes();

    final alreadyStr = alreadyDetected.isNotEmpty
        ? '이미 감지된 재료(제외): ${alreadyDetected.join(", ")}'
        : '';

    final prompt = '''
너는 음식 재료 인식 전문가야.
이 이미지에서 식재료를 모두 찾아줘.
$alreadyStr

반드시 아래 JSON 배열만 반환해. 마크다운, 설명문, 코드블록은 쓰지 마.
항목은 한국어로 써줘 (예: 계란, 양파, 감자, 당근, 토마토, 대파, 마늘, 두부 등).
식재료가 없으면 빈 배열 [] 반환.

["재료1", "재료2"]
''';

    Exception? lastError;
    for (final modelName in _modelNames) {
      try {
        final model = GenerativeModel(model: modelName, apiKey: apiKey);
        final content = [
          Content.multi([
            DataPart('image/jpeg', imageBytes),
            TextPart(prompt),
          ])
        ];
        final response = await model.generateContent(content);
        final text = response.text ?? '';
        return _parseStringArray(text);
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }
    throw GeminiException('식재료 인식 실패: ${lastError?.toString()}');
  }

  // 2) 식재료 리스트로 레시피 추천
  Future<List<RecipeRecommendation>> getRecipeRecommendations(
      List<String> ingredients,
      ) async {
    if (ingredients.isEmpty) return [];

    final foodList = ingredients.join(', ');

    final prompt = '''
너는 한국 가정식과 간단한 냉장고 재료 요리에 강한 전문 셰프야.
다음 [ 음식리스트 ]를 주재료로 활용해서 실제로 만들기 쉬운 레시피 5가지를 추천해줘.

[ 음식리스트 ]
[$foodList]

반드시 아래 JSON 배열만 반환해. 마크다운, 설명문, 코드블록은 쓰지 마.
각 레시피는 서로 다른 조리 방식이나 맛 방향이어야 해.
식재료가 부족하면 집에 흔히 있는 기본 재료(소금, 후추, 식용유, 간장, 설탕, 마늘, 파)는 추가해도 돼.
steps는 초보자가 그대로 따라 할 수 있게 5~8단계로 짧고 구체적으로 작성해.
calories는 1인분 기준 대략적인 열량(kcal)을 정수로 적어줘.

[
  {
    "title": "요리명",
    "summary": "한 줄 설명",
    "calories": 450,
    "ingredients": ["재료 1", "재료 2"],
    "steps": ["1단계", "2단계", "3단계"],
    "tip": "실패를 줄이는 팁"
  }
]
''';

    Exception? lastError;
    for (final modelName in _modelNames) {
      try {
        final model = GenerativeModel(model: modelName, apiKey: apiKey);
        final response =
        await model.generateContent([Content.text(prompt)]);
        final text = response.text ?? '';
        return _parseRecipes(text);
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }
    throw GeminiException('레시피 요청 실패: ${lastError?.toString()}');
  }

  // 3) 식재료 유통기한 AI 추천
  Future<String> getExpiryHint(String ingredient) async {
    final prompt = '''
"$ingredient"의 냉장 보관 시 평균적인 유통기한을 한 문장으로 알려줘.
예시: "계란은 냉장 보관 시 평균 3~4주 정도 신선하게 유지됩니다."
딱 한 문장만 반환해. 마크다운 쓰지 마.
''';
    Exception? lastError;
    for (final modelName in _modelNames) {
      try {
        final model = GenerativeModel(model: modelName, apiKey: apiKey);
        final response =
        await model.generateContent([Content.text(prompt)]);
        return response.text?.trim() ?? '유통기한 정보를 가져오지 못했습니다.';
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }
    throw GeminiException('유통기한 추천 실패: ${lastError?.toString()}');
  }

  // ── 파싱 헬퍼 ─────────────────────────────────────────────────────
  List<String> _parseStringArray(String text) {
    final cleaned = _stripMarkdown(text);
    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    if (start < 0 || end <= start) return [];
    try {
      final list = jsonDecode(cleaned.substring(start, end + 1)) as List;
      return list
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<RecipeRecommendation> _parseRecipes(String text) {
    final cleaned = _stripMarkdown(text);
    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    if (start < 0 || end <= start) return _fallback(text);
    try {
      final list = jsonDecode(cleaned.substring(start, end + 1)) as List;
      return list
          .asMap()
          .entries
          .map((e) => RecipeRecommendation.fromJson(
        e.value as Map<String, dynamic>,
        e.key,
      ))
          .take(5)
          .toList();
    } catch (_) {
      return _fallback(text);
    }
  }

  String _stripMarkdown(String text) => text
      .trim()
      .replaceAll('```json', '')
      .replaceAll('```', '')
      .trim();

  List<RecipeRecommendation> _fallback(String text) => [
    RecipeRecommendation(
      title: '추천 레시피',
      summary: 'Gemini 응답을 구조화하지 못해 원문을 표시합니다.',
      ingredients: [],
      steps: text.split('\n').where((l) => l.trim().isNotEmpty).toList(),
      tip: '다시 추천받기를 시도하면 구조화된 결과가 나올 수 있습니다.',
    )
  ];
}

class GeminiException implements Exception {
  final String message;
  GeminiException(this.message);
  @override
  String toString() => message;
}
