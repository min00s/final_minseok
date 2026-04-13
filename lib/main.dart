import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:math';

void main() => runApp(const KingJangoApp());

class KingJangoApp extends StatelessWidget {
  const KingJangoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  File? _image;
  final picker = ImagePicker();
  String _result = "식재료를 인식해 주세요!";
  bool _isLoading = false;

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _modelReady = false;

  // 인식된 식재료 이름 목록
  List<String> _detectedItems = [];

  // YOLO 설정
  static const int inputSize = 640;
  static const double confidenceThreshold = 0.1;
  static const double iouThreshold = 0.5;

  @override
  void initState() {
    super.initState();
    loadModel();
  }

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/food_model.tflite');

      final labelData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelData.split('\n').where((e) => e.trim().isNotEmpty).toList();

      print('모델 로드 완료! 라벨 수: ${_labels.length}');
      print('라벨: $_labels');
      print('입력 텐서: ${_interpreter!.getInputTensors()}');
      print('출력 텐서: ${_interpreter!.getOutputTensors()}');

      setState(() {
        _modelReady = true;
      });
    } catch (e) {
      print('모델 로드 오류: $e');
      setState(() {
        _result = "모델 로드 실패: $e";
      });
    }
  }

  // 카메라로 촬영
  Future<void> getImageFromCamera() async {
    if (!_modelReady) {
      setState(() {
        _result = "모델이 아직 로딩 중입니다. 잠시 기다려주세요.";
      });
      return;
    }

    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _isLoading = true;
        _result = "분석 중...";
        _detectedItems = [];
      });
      await runModelOnImage(_image!);
    }
  }

  // 갤러리에서 선택
  Future<void> getImageFromGallery() async {
    if (!_modelReady) {
      setState(() {
        _result = "모델이 아직 로딩 중입니다. 잠시 기다려주세요.";
      });
      return;
    }

    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _isLoading = true;
        _result = "분석 중...";
        _detectedItems = [];
      });
      await runModelOnImage(_image!);
    }
  }

  Future<void> runModelOnImage(File image) async {
    try {
      if (_labels.isEmpty) {
        setState(() {
          _isLoading = false;
          _result = "오류: 라벨 파일이 비어있습니다.";
        });
        return;
      }

      final imageBytes = await image.readAsBytes();
      final decoded = img.decodeImage(imageBytes)!;
      final resized = img.copyResize(decoded, width: inputSize, height: inputSize);

      // 입력 텐서 준비 [1, 640, 640, 3] — HWC 형식, 0~1 정규화
      var input = List.generate(
        1,
            (_) => List.generate(
          inputSize,
              (y) => List.generate(
            inputSize,
                (x) {
              final pixel = resized.getPixel(x, y);
              return [
                pixel.r / 255.0,
                pixel.g / 255.0,
                pixel.b / 255.0,
              ];
            },
          ),
        ),
      );

      int numClasses = _labels.length;
      int numDetections = 8400;
      int outputChannels = 4 + numClasses;

      var output = List.generate(
        1,
            (_) => List.generate(
          outputChannels,
              (_) => List.filled(numDetections, 0.0),
        ),
      );

      _interpreter!.run(input, output);

      // 디버깅 로그
      double globalMax = 0;
      int globalMaxIdx = 0;
      int globalMaxClass = 0;
      for (int i = 0; i < numDetections; i++) {
        for (int c = 0; c < numClasses; c++) {
          double score = output[0][4 + c][i];
          if (score > globalMax) {
            globalMax = score;
            globalMaxIdx = i;
            globalMaxClass = c;
          }
        }
      }
      print('최고 confidence: $globalMax');
      if (globalMax > 0) {
        print('최고 클래스: ${_labels[globalMaxClass]}');
      }

      // YOLO 출력 파싱
      List<Map<String, dynamic>> detections = [];

      for (int i = 0; i < numDetections; i++) {
        double maxClassScore = 0;
        int maxClassIndex = 0;

        for (int c = 0; c < numClasses; c++) {
          double score = output[0][4 + c][i];
          if (score > maxClassScore) {
            maxClassScore = score;
            maxClassIndex = c;
          }
        }

        if (maxClassScore > confidenceThreshold) {
          detections.add({
            'class': maxClassIndex,
            'className': _labels[maxClassIndex],
            'confidence': maxClassScore,
            'x': output[0][0][i],
            'y': output[0][1][i],
            'w': output[0][2][i],
            'h': output[0][3][i],
          });
        }
      }

      detections = _nms(detections);

      setState(() {
        _isLoading = false;
        if (detections.isNotEmpty) {
          // 중복 제거하여 이름만 추출 (확률 표시 안 함)
          Set<String> foundItems = {};
          for (var det in detections) {
            foundItems.add(det['className']);
          }
          _detectedItems = foundItems.toList();
          _result = "발견된 식재료:";
        } else {
          _detectedItems = [];
          _result = "식재료를 인식하지 못했습니다.\n다시 시도해 주세요.";
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _result = "오류 발생: $e";
      });
      print('추론 오류: $e');
    }
  }

  List<Map<String, dynamic>> _nms(List<Map<String, dynamic>> detections) {
    detections.sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));
    List<Map<String, dynamic>> result = [];

    while (detections.isNotEmpty) {
      var best = detections.removeAt(0);
      result.add(best);
      detections.removeWhere((det) {
        if (det['class'] != best['class']) return false;
        return _calculateIoU(best, det) > iouThreshold;
      });
    }
    return result;
  }

  double _calculateIoU(Map<String, dynamic> a, Map<String, dynamic> b) {
    double ax1 = a['x'] - a['w'] / 2;
    double ay1 = a['y'] - a['h'] / 2;
    double ax2 = a['x'] + a['w'] / 2;
    double ay2 = a['y'] + a['h'] / 2;
    double bx1 = b['x'] - b['w'] / 2;
    double by1 = b['y'] - b['h'] / 2;
    double bx2 = b['x'] + b['w'] / 2;
    double by2 = b['y'] + b['h'] / 2;
    double interX1 = max(ax1, bx1);
    double interY1 = max(ay1, by1);
    double interX2 = min(ax2, bx2);
    double interY2 = min(ay2, by2);
    double interArea = max(0, interX2 - interX1) * max(0, interY2 - interY1);
    double aArea = (ax2 - ax1) * (ay2 - ay1);
    double bArea = (bx2 - bx1) * (by2 - by1);
    return interArea / (aArea + bArea - interArea);
  }

  // 레시피 추천 페이지로 이동
  void _goToRecipe() {
    if (_detectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('먼저 식재료를 인식해 주세요!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecipeScreen(ingredients: _detectedItems),
      ),
    );
  }

  @override
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading ? buildLoadingScreen() : buildMainScreen();
  }

  Widget buildMainScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        title: const Text('킹장고를 부탁해 🥕',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),

            // 이미지 영역
            Center(
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.3),
                      spreadRadius: 2,
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: Image(
                    image: _image == null
                        ? const AssetImage('assets/vegetable.png.jpg')
                    as ImageProvider
                        : FileImage(_image!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 인식 결과 영역
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.15),
                    spreadRadius: 1,
                    blurRadius: 5,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    _result,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  if (_detectedItems.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: _detectedItems.map((item) {
                        return Chip(
                          avatar: const Icon(Icons.eco, color: Colors.white, size: 18),
                          label: Text(item, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          backgroundColor: Colors.green,
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 카메라 & 갤러리 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: getImageFromCamera,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('카메라', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: getImageFromGallery,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('갤러리', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),

            // 레시피 추천 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _goToRecipe,
                  icon: const Icon(Icons.restaurant_menu),
                  label: const Text('레시피 추천받기', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/skku.jpg', width: 200, fit: BoxFit.contain),
            const SizedBox(height: 50),
            const CircularProgressIndicator(
                color: Colors.green, strokeWidth: 5),
            const SizedBox(height: 30),
            const Text(
              "AI가 식재료를 신속하게 분석 중입니다...",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey),
            ),
            const SizedBox(height: 10),
            const Text("잠시만 기다려 주세요.",
                style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ========== 레시피 추천 화면 ==========
class RecipeScreen extends StatelessWidget {
  final List<String> ingredients;

  const RecipeScreen({super.key, required this.ingredients});

  // 식재료 기반 레시피 데이터
  List<Map<String, dynamic>> getRecipes() {
    List<Map<String, dynamic>> allRecipes = [
      {
        'name': '계란말이',
        'ingredients': ['Egg'],
        'description': '부드럽고 촉촉한 계란말이',
        'icon': '🍳',
      },
      {
        'name': '양파볶음',
        'ingredients': ['Onion'],
        'description': '달콤하게 볶은 양파볶음',
        'icon': '🧅',
      },
      {
        'name': '감자볶음',
        'ingredients': ['Potato'],
        'description': '바삭한 감자볶음',
        'icon': '🥔',
      },
      {
        'name': '토마토 스파게티',
        'ingredients': ['Tomato'],
        'description': '신선한 토마토 소스 스파게티',
        'icon': '🍝',
      },
      {
        'name': '당근라페',
        'ingredients': ['carrot'],
        'description': '상큼한 프렌치 당근 샐러드',
        'icon': '🥕',
      },
      {
        'name': '스페니시 오믈렛',
        'ingredients': ['Egg', 'Potato', 'Onion'],
        'description': '감자와 양파가 들어간 스페인식 오믈렛',
        'icon': '🍳',
      },
      {
        'name': '토마토 계란볶음',
        'ingredients': ['Tomato', 'Egg'],
        'description': '중국식 토마토 계란볶음',
        'icon': '🍅',
      },
      {
        'name': '카레',
        'ingredients': ['Potato', 'Onion', 'carrot'],
        'description': '감자, 양파, 당근이 들어간 카레',
        'icon': '🍛',
      },
      {
        'name': '야채볶음',
        'ingredients': ['Onion', 'carrot'],
        'description': '양파와 당근을 넣은 야채볶음',
        'icon': '🥘',
      },
      {
        'name': '감자샐러드',
        'ingredients': ['Potato', 'Egg', 'carrot'],
        'description': '부드러운 감자샐러드',
        'icon': '🥗',
      },
    ];

    // 내가 가진 식재료로 만들 수 있는 레시피 필터링
    List<Map<String, dynamic>> matchedRecipes = [];
    for (var recipe in allRecipes) {
      List<String> needed = List<String>.from(recipe['ingredients']);
      bool canMake = needed.every((item) => ingredients.contains(item));
      if (canMake) {
        matchedRecipes.add(recipe);
      }
    }

    return matchedRecipes;
  }

  @override
  Widget build(BuildContext context) {
    final recipes = getRecipes();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        title: const Text('레시피 추천 🍽️',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 2,
      ),
      body: Column(
        children: [
          // 내 식재료 표시
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.15),
                  spreadRadius: 1,
                  blurRadius: 5,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🧊 내 식재료',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ingredients.map((item) {
                    return Chip(
                      label: Text(item, style: const TextStyle(color: Colors.white)),
                      backgroundColor: Colors.green,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // 레시피 목록
          Expanded(
            child: recipes.isEmpty
                ? const Center(
              child: Text(
                '만들 수 있는 레시피가 없습니다.\n더 많은 식재료를 추가해 보세요!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: recipes.length,
              itemBuilder: (context, index) {
                final recipe = recipes[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  elevation: 2,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Text(
                      recipe['icon'],
                      style: const TextStyle(fontSize: 40),
                    ),
                    title: Text(
                      recipe['name'],
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(recipe['description']),
                        const SizedBox(height: 6),
                        Text(
                          '재료: ${(recipe['ingredients'] as List).join(", ")}',
                          style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}