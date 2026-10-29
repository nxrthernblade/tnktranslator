import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HiaTranslatorApp());
}

class HiaTranslatorApp extends StatelessWidget {
  const HiaTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TNK Translator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepPurpleAccent,
          secondary: Colors.amberAccent,
        ),
      ),
      home: const MangaBrowserScreen(),
    );
  }
}

class TextBlock {
  final int ymin, xmin, ymax, xmax;
  final String text;

  TextBlock({
    required this.ymin,
    required this.xmin,
    required this.ymax,
    required this.xmax,
    required this.text,
  });

  factory TextBlock.fromJson(Map json) {
    final List box = List.from(json['box_2d'] ?? [0, 0, 100, 100]);
    return TextBlock(
      ymin: (box[0] as num).toInt().clamp(0, 1000),
      xmin: (box[1] as num).toInt().clamp(0, 1000),
      ymax: (box[2] as num).toInt().clamp(0, 1000),
      xmax: (box[3] as num).toInt().clamp(0, 1000),
      text: json['text']?.toString() ?? '',
    );
  }
}

class TranslatedPageData {
  final Uint8List cleanedImageBytes;
  final int imageWidth;
  final int imageHeight;
  final List blocks;

  TranslatedPageData({
    required this.cleanedImageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.blocks,
  });
}

Map cleanMangaImageIsolate(Map params) {
  final Uint8List bytes = params['bytes'] as Uint8List;
  final List rawBlocks = params['blocks'] as List;

  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return {'bytes': bytes, 'width': 1, 'height': 1};
  }

  for (final dynamic b in rawBlocks) {
    final Map blockMap = b as Map;
    final List box = blockMap['box_2d'] as List;
    final int x1 = ((box[1] as num) * decoded.width ~/ 1000).clamp(0, decoded.width - 1);
    final int y1 = ((box[0] as num) * decoded.height ~/ 1000).clamp(0, decoded.height - 1);
    final int x2 = ((box[3] as num) * decoded.width ~/ 1000).clamp(0, decoded.width - 1);
    final int y2 = ((box[2] as num) * decoded.height ~/ 1000).clamp(0, decoded.height - 1);

    int rSum = 0, gSum = 0, bSum = 0, count = 0;
    for (int x = x1; x <= x2; x += 2) {
      final pTop = decoded.getPixel(x, y1);
      final pBot = decoded.getPixel(x, y2);
      rSum += pTop.r.toInt() + pBot.r.toInt();
      gSum += pTop.g.toInt() + pBot.g.toInt();
      bSum += pTop.b.toInt() + pBot.b.toInt();
      count += 2;
    }
    for (int y = y1; y <= y2; y += 2) {
      final pLeft = decoded.getPixel(x1, y);
      final pRight = decoded.getPixel(x2, y);
      rSum += pLeft.r.toInt() + pRight.r.toInt();
      gSum += pLeft.g.toInt() + pRight.g.toInt();
      bSum += pLeft.b.toInt() + pRight.b.toInt();
      count += 2;
    }

    final int bgR = count != 0 ? (rSum ~/ count) : 255;
    final int bgG = count != 0 ? (gSum ~/ count) : 255;
    final int bgB = count != 0 ? (bSum ~/ count) : 255;
    final double bgLum = 0.299 * bgR + 0.587 * bgG + 0.114 * bgB;

    for (int y = y1; y <= y2; y++) {
      for (int x = x1; x <= x2; x++) {
        final p = decoded.getPixel(x, y);
        final double lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        if ((lum - bgLum).abs() >= 28) {
          decoded.setPixelRgb(x, y, bgR, bgG, bgB);
        }
      }
    }
  }

  return {
    'bytes': Uint8List.fromList(img.encodeJpg(decoded, quality: 90)),
    'width': decoded.width,
    'height': decoded.height,
  };
}

class MangaBrowserScreen extends StatefulWidget {
  const MangaBrowserScreen({super.key});

  @override
  State createState() => _MangaBrowserScreenState();
}

class _MangaBrowserScreenState extends State {
  InAppWebViewController? _webViewController;
  final TextEditingController _urlController =
      TextEditingController(text: 'https://manganato.com');
  String _apiKey = '';
  String _selectedModel = 'gemini-2.5-flash';
  bool _isWorking = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKey = prefs.getString('gemini_api_key') ?? '';
      _selectedModel = prefs.getString('gemini_model') ?? 'gemini-2.5-flash';
    });
  }

  Future _saveSettings(String key, String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key.trim());
    await prefs.setString('gemini_model', model.trim());
    setState(() {
      _apiKey = key.trim();
      _selectedModel = model.trim();
    });
  }

  void _openSettingsDialog() {
    final keyCtrl = TextEditingController(text: _apiKey);
    final modelCtrl = TextEditingController(text: _selectedModel);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ตั้งค่าระบบแปล (TNK Translator)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: keyCtrl,
              decoration: const InputDecoration(
                labelText: 'Gemini API Key',
                hintText: 'AIzaSy...',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modelCtrl,
              decoration: const InputDecoration(
                labelText: 'ชื่อโมเดล Gemini',
                hintText: 'gemini-2.5-flash หรือ gemini-1.5-flash',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '* คีย์ถูกเซฟไว้ในความจำมือถือเครื่องนี้เท่านั้น ปลอดภัย 100%',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              _saveSettings(keyCtrl.text, modelCtrl.text);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('บันทึกตั้งค่าเรียบร้อย!')),
              );
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  Future _extractAndTranslatePage() async {
    if (_apiKey.isEmpty) {
      _openSettingsDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ใส่ Gemini API Key ก่อนนะเฮีย!')),
      );
      return null;
    }

    if (_webViewController == null) return null;

    setState(() {
      _isWorking = true;
      _statusMessage = 'กำลังเจาะดึงรูปภาพการ์ตูนจากหน้าเว็บ...';
    });

    try {
      const String jsExtractor = """
      (async function() {
        const imgs = Array.from(document.querySelectorAll('img'));
        const mangaImgs = imgs.filter(function(img) {
          const w = img.naturalWidth || img.width || img.clientWidth;
          const h = img.naturalHeight || img.height || img.clientHeight;
          return w >= 280 && h >= 350;
        });

        const results = [];
        for (const img of mangaImgs) {
          const src = img.currentSrc || img.src || img.dataset.src || img.getAttribute('data-lazy-src');
          if (!src) continue;

          try {
            const canvas = document.createElement('canvas');
            canvas.width = img.naturalWidth || img.width;
            canvas.height = img.naturalHeight || img.height;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(img, 0, 0);
            const dataUrl = canvas.toDataURL('image/jpeg', 0.88);
            results.push(dataUrl.split(',')[1]);
          } catch (err) {
            try {
              const resp = await fetch(src, { credentials: 'include' });
              const blob = await resp.blob();
              const b64 = await new Promise(function(resolve) {
                const reader = new FileReader();
                reader.onloadend = function() {
                  resolve(reader.result.split(',')[1]);
                };
                reader.readAsDataURL(blob);
              });
              if (b64) results.push(b64);
            } catch (e2) {
              results.push("URL:" + src);
            }
          }
        }
        return JSON.stringify(results);
      })();
      """;

      final rawResult = await _webViewController!.evaluateJavascript(source: jsExtractor);
      if (rawResult == null) throw Exception('ไม่สามารถดึงข้อมูลจากหน้าเว็บได้');

      final List extractedList = jsonDecode(rawResult.toString()) as List;
      if (extractedList.isEmpty) {
        throw Exception('ไม่พบรูปหน้าการ์ตูนในหน้านี้ ลองเลื่อนหน้าจอให้รูปโหลดก่อนนะเฮีย');
      }

      final currentUrl = (await _webViewController!.getUrl())?.toString() ?? '';
      final List imageBytesList = [];
      final List limitedList = extractedList.take(8).toList();

      for (final dynamic rawItem in limitedList) {
        final String item = rawItem.toString();
        if (item.startsWith('URL:')) {
          final imgUrl = item.substring(4);
          final resp = await http.get(
            Uri.parse(imgUrl),
            headers: {
              'Referer': currentUrl,
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
            },
          );
          if (resp.statusCode == 200) {
            imageBytesList.add(resp.bodyBytes);
          }
        } else {
          imageBytesList.add(base64Decode(item));
        }
      }

      final List finalPages = [];
      int pageIndex = 0;

      for (final dynamic pageBytesObj in imageBytesList) {
        pageIndex++;
        setState(() {
          _statusMessage = 'กำลังคลีนและแปลหน้าที่ $pageIndex / ${imageBytesList.length}...';
        });

        final Uint8List pageBytes = pageBytesObj as Uint8List;
        final List rawBlocks = (await _callGeminiTranslate(pageBytes)) as List;

        final Map cleanedResult = await compute(cleanMangaImageIsolate, {
          'bytes': pageBytes,
          'blocks': rawBlocks,
        });

        finalPages.add(
          TranslatedPageData(
            cleanedImageBytes: cleanedResult['bytes'] as Uint8List,
            imageWidth: cleanedResult['width'] as int,
            imageHeight: cleanedResult['height'] as int,
            blocks: rawBlocks.map((e) => TextBlock.fromJson(Map.from(e as Map))).toList(),
          ),
        );
      }

      if (!mounted) return null;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TranslatedReaderScreen(pages: finalPages),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
          _statusMessage = '';
        });
      }
    }
    return null;
  }

  Future _callGeminiTranslate(Uint8List imageBytes) async {
    final String b64Image = base64Encode(imageBytes);
    final Uri endpoint = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_selectedModel:generateContent?key=$_apiKey',
    );

    const String prompt = '''
คุณคือนักแปลมังงะและมันฮวามืออาชีพ สแกนหาบอลลูนคำพูดและข้อความทั้งหมดในภาพนี้ แล้วแปลเป็นภาษาไทยที่เป็นธรรมชาติ เข้ากับบริบทตัวละคร ไม่แปลแข็งทื่อ
ส่งค่ากลับมาเป็น JSON Array เท่านั้น ตามโครงสร้างนี้:
[
  {
    "box_2d": [ymin, xmin, ymax, xmax],
    "text": "คำแปลภาษาไทย"
  }
]
โดยพิกัด box_2d ต้องเป็นตัวเลขสเกล 0 ถึง 1000 ที่ครอบทับตัวอักษรต้นฉบับพอดี ห้ามใส่ข้อความอธิบายอื่นนอกเหนือจาก JSON
''';

    final response = await http.post(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': b64Image,
                }
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.2,
          'responseMimeType': 'application/json',
        }
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Gemini API Error (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return [];

    String rawJson = candidates[0]['content']['parts'][0]['text'].toString().trim();
    rawJson = rawJson.replaceAll('```json', '').replaceAll('```', '').trim();

    final List parsed = jsonDecode(rawJson) as List;
    return parsed.map((e) => Map.from(e as Map)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: TextField(
          controller: _urlController,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            filled: true,
            fillColor: Colors.black26,
            hintText: 'ใส่ลิงก์เว็บอ่านมังงะ/มันฮวา...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: () {
                String url = _urlController.text.trim();
                if (!url.startsWith('http')) url = 'https://$url';
                _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
              },
            ),
          ),
          onSubmitted: (val) {
            String url = val.trim();
            if (!url.startsWith('http')) url = 'https://$url';
            _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _webViewController?.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_urlController.text)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              useWideViewPort: true,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              userAgent:
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
            ),
            onWebViewCreated: (controller) => _webViewController = controller,
            onLoadStop: (controller, url) {
              if (url != null) {
                setState(() => _urlController.text = url.toString());
              }
            },
          ),
          if (_isWorking)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.amberAccent),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.sarabun(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isWorking ? null : _extractAndTranslatePage,
        backgroundColor: Colors.deepPurpleAccent,
        icon: const Icon(Icons.translate, color: Colors.white),
        label: Text(
          'คลีน & แปลไทย',
          style: GoogleFonts.sarabun(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }
}

class TranslatedReaderScreen extends StatelessWidget {
  final List pages;

  const TranslatedReaderScreen({super.key, required this.pages});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'โหมดอ่านแปลไทย (${pages.length} หน้า)',
          style: GoogleFonts.sarabun(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView.builder(
        itemCount: pages.length,
        itemBuilder: (context, index) {
          final TranslatedPageData page = pages[index] as TranslatedPageData;
          return LayoutBuilder(
            builder: (context, constraints) {
              final double displayW = constraints.maxWidth;
              final double displayH = displayW * (page.imageHeight / page.imageWidth);

              return SizedBox(
                width: displayW,
                height: displayH,
                child: Stack(
                  children: [
                    Image.memory(
                      page.cleanedImageBytes,
                      width: displayW,
                      height: displayH,
                      fit: BoxFit.contain,
                    ),
                    ...page.blocks.map((b) {
                      final TextBlock block = b as TextBlock;
                      final double left = (block.xmin / 1000.0) * displayW;
                      final double top = (block.ymin / 1000.0) * displayH;
                      final double width = ((block.xmax - block.xmin) / 1000.0) * displayW;
                      final double height = ((block.ymax - block.ymin) / 1000.0) * displayH;

                      return Positioned(
                        left: left,
                        top: top,
                        width: width.clamp(24.0, displayW),
                        height: height.clamp(20.0, displayH),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: width.clamp(40.0, displayW),
                              ),
                              child: Text(
                                block.text,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.sarabun(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  height: 1.15,
                                  shadows: const [
                                    Shadow(color: Colors.white, blurRadius: 3),
                                    Shadow(color: Colors.white, blurRadius: 6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
