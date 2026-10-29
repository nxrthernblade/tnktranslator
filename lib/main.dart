import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TnkBrowserApp());
}

class TnkBrowserApp extends StatelessWidget {
  const TnkBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TNK Browser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF131314),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8AB4F8),
          secondary: Color(0xFFC58AF9),
          surface: Color(0xFF1E1F22),
        ),
      ),
      home: const ChromeBrowserScreen(),
    );
  }
}

class ChromeBrowserScreen extends StatefulWidget {
  const ChromeBrowserScreen({super.key});

  @override
  State createState() => _ChromeBrowserScreenState();
}

class _ChromeBrowserScreenState extends State {
  InAppWebViewController? _webController;
  final TextEditingController _omniboxController = TextEditingController();
  final TextEditingController _homeSearchController = TextEditingController();

  bool _isHome = true;
  bool _isLoading = false;
  double _progress = 0.0;
  String _currentUrl = '';
  String _currentTitle = 'หน้าหลัก';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isDesktopMode = false;

  String _apiKey = '';
  String _selectedModel = 'gemini-2.5-flash';

  bool _isTranslating = false;
  bool _cancelRequested = false;
  String _translateStatus = '';

  List _shortcuts = [];
  List _bookmarks = [];
  List _history = [];

  static const String _mobileUA =
      'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
  static const String _desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedShortcuts = prefs.getString('tnk_shortcuts');
    final savedBookmarks = prefs.getString('tnk_bookmarks');
    final savedHistory = prefs.getString('tnk_history');

    List defaultShortcuts = [
      {'title': 'Google', 'url': 'https://www.google.com'},
      {'title': 'MangaDex', 'url': 'https://mangadex.org'},
      {'title': 'Webtoons', 'url': 'https://www.webtoons.com'},
      {'title': 'Naver Webtoon', 'url': 'https://m.comic.naver.com'},
      {'title': 'KakaoPage', 'url': 'https://page.kakao.com'},
      {'title': 'Reddit', 'url': 'https://www.reddit.com'},
    ];

    setState(() {
      _apiKey = prefs.getString('gemini_api_key') ?? '';
      _selectedModel = prefs.getString('gemini_model') ?? 'gemini-2.5-flash';
      _shortcuts = savedShortcuts != null
          ? (jsonDecode(savedShortcuts) as List)
          : defaultShortcuts;
      _bookmarks =
          savedBookmarks != null ? (jsonDecode(savedBookmarks) as List) : [];
      _history =
          savedHistory != null ? (jsonDecode(savedHistory) as List) : [];
    });
  }

  Future _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tnk_shortcuts', jsonEncode(_shortcuts));
    await prefs.setString('tnk_bookmarks', jsonEncode(_bookmarks));
    await prefs.setString('tnk_history', jsonEncode(_history));
  }

  Future _saveApiSettings(String key, String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key.trim());
    await prefs.setString('gemini_model', model.trim());
    setState(() {
      _apiKey = key.trim();
      _selectedModel = model.trim();
    });
  }

  void _navigateToInput(String rawInput) {
    final String input = rawInput.trim();
    if (input.isEmpty) return;

    String targetUrl;
    final bool hasSpace = input.contains(' ');
    final bool hasDot = input.contains('.');

    if (input.startsWith('http://') || input.startsWith('https://')) {
      targetUrl = input;
    } else if (!hasSpace && hasDot) {
      targetUrl = 'https://$input';
    } else {
      targetUrl =
          'https://www.google.com/search?q=${Uri.encodeComponent(input)}';
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isHome = false;
      _currentUrl = targetUrl;
      _omniboxController.text = targetUrl;
    });

    _webController?.loadUrl(urlRequest: URLRequest(url: WebUri(targetUrl)));
  }

  void _goHome() {
    FocusScope.of(context).unfocus();
    setState(() {
      _isHome = true;
      _omniboxController.clear();
      _homeSearchController.clear();
    });
  }

  void _addHistoryItem(String title, String url) {
    if (url.isEmpty || url == 'about:blank') return;
    _history.removeWhere((item) => (item as Map)['url'] == url);
    _history.insert(0, {
      'title': title.isEmpty ? url : title,
      'url': url,
    });
    if (_history.length >= 40) {
      _history = _history.take(40).toList();
    }
    _saveData();
  }

  bool _isBookmarked() {
    return _bookmarks.any((item) => (item as Map)['url'] == _currentUrl);
  }

  void _toggleBookmark() {
    if (_isHome || _currentUrl.isEmpty) return;
    setState(() {
      if (_isBookmarked()) {
        _bookmarks.removeWhere((item) => (item as Map)['url'] == _currentUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบออกจากบุ๊กมาร์กแล้ว')),
        );
      } else {
        _bookmarks.insert(0, {
          'title': _currentTitle.isEmpty ? _currentUrl : _currentTitle,
          'url': _currentUrl,
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกบุ๊กมาร์กเรียบร้อย')),
        );
      }
    });
    _saveData();
  }

  void _toggleDesktopMode() async {
    setState(() {
      _isDesktopMode = !_isDesktopMode;
    });
    if (_webController != null) {
      await _webController!.setSettings(
        settings: InAppWebViewSettings(
          userAgent: _isDesktopMode ? _desktopUA : _mobileUA,
          preferredContentMode: _isDesktopMode
              ? UserPreferredContentMode.DESKTOP
              : UserPreferredContentMode.RECOMMENDED,
        ),
      );
      await _webController!.reload();
    }
  }

  Future _refreshNavigationState() async {
    if (_webController == null) return;
    final back = await _webController!.canGoBack();
    final forward = await _webController!.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  void _showAddShortcutDialog() {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F22),
        title: Text('เพิ่มทางลัดหน้าหลัก', style: GoogleFonts.sarabun()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'ชื่อเว็บ (เช่น MangaDex)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: 'ลิงก์ URL (เช่น mangadex.org)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              String u = urlCtrl.text.trim();
              if (u.isEmpty) return;
              if (!u.startsWith('http')) u = 'https://$u';
              final String t =
                  titleCtrl.text.trim().isEmpty ? u : titleCtrl.text.trim();
              setState(() {
                _shortcuts.add({'title': t, 'url': u});
              });
              _saveData();
              Navigator.pop(ctx);
            },
            child: const Text('เพิ่ม'),
          ),
        ],
      ),
    );
  }

  void _openSettingsDialog() {
    final keyCtrl = TextEditingController(text: _apiKey);
    final modelCtrl = TextEditingController(text: _selectedModel);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F22),
        title: Text(
          'ตั้งค่า AI แปลมังงะ',
          style: GoogleFonts.sarabun(fontWeight: FontWeight.bold),
        ),
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
                labelText: 'รุ่นโมเดล (Model)',
                hintText: 'gemini-2.5-flash',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'แนะนำใช้ gemini-2.5-flash หรือ gemini-2.0-flash เพื่อความเร็วและแม่นยำในการสแกนกรอบคำพูด',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              _saveApiSettings(keyCtrl.text, modelCtrl.text);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('บันทึกการตั้งค่าเรียบร้อย')),
              );
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  void _openBookmarksAndHistorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1F22),
      isScrollControlled: true,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.bookmark), text: 'บุ๊กมาร์ก'),
                  Tab(icon: Icon(Icons.history), text: 'ประวัติเข้าเว็บ'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _bookmarks.isEmpty
                        ? const Center(child: Text('ยังไม่มีบุ๊กมาร์กที่บันทึกไว้'))
                        : ListView.builder(
                            itemCount: _bookmarks.length,
                            itemBuilder: (c, i) {
                              final item = _bookmarks[i] as Map;
                              return ListTile(
                                leading: const Icon(Icons.bookmark,
                                    color: Color(0xFF8AB4F8)),
                                title: Text(
                                  item['title'].toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  item['url'].toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () {
                                    setState(() {
                                      _bookmarks.removeAt(i);
                                    });
                                    _saveData();
                                    Navigator.pop(ctx);
                                    _openBookmarksAndHistorySheet();
                                  },
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _navigateToInput(item['url'].toString());
                                },
                              );
                            },
                          ),
                    _history.isEmpty
                        ? const Center(child: Text('ยังไม่มีประวัติการเข้าชม'))
                        : Column(
                            children: [
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () {
                                    setState(() => _history.clear());
                                    _saveData();
                                    Navigator.pop(ctx);
                                  },
                                  icon: const Icon(Icons.delete_sweep),
                                  label: const Text('ล้างประวัติทั้งหมด'),
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _history.length,
                                  itemBuilder: (c, i) {
                                    final item = _history[i] as Map;
                                    return ListTile(
                                      leading: const Icon(Icons.public,
                                          color: Colors.grey),
                                      title: Text(
                                        item['title'].toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        item['url'].toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _navigateToInput(
                                            item['url'].toString());
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future _translateCurrentPageInPlace() async {
    if (_isHome || _webController == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปิดหน้าเว็บการ์ตูนก่อนกดแปลนะเฮีย')),
      );
      return;
    }

    if (_apiKey.isEmpty) {
      _openSettingsDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรอก Gemini API Key ก่อนเริ่มแปลนะครับ')),
      );
      return;
    }

    setState(() {
      _isTranslating = true;
      _cancelRequested = false;
      _translateStatus = 'กำลังสแกนหารูปการ์ตูนในหน้าเว็บ...';
    });

    try {
      const String jsFindAndExtract = """
      (async function() {
        const allImgs = Array.from(document.querySelectorAll('img'));
        const targets = [];
        let idx = 0;

        for (const img of allImgs) {
          idx++;
          const w = img.naturalWidth || img.width || img.clientWidth;
          const h = img.naturalHeight || img.height || img.clientHeight;
          if (!(w >= 260 && h >= 320)) continue;
          if (img.dataset.tnkTranslated === '1') continue;

          const rect = img.getBoundingClientRect();
          const dist = Math.abs(rect.top);
          const id = img.dataset.tnkId || ('tnk_img_' + Date.now() + '_' + idx);
          img.dataset.tnkId = id;

          const src = img.currentSrc || img.src || img.dataset.src || img.getAttribute('data-lazy-src') || '';
          if (!src) continue;

          targets.push({ img: img, id: id, src: src, dist: dist });
        }

        targets.sort(function(a, b) { return a.dist - b.dist; });
        const batch = targets.slice(0, 8);
        const output = [];

        for (const item of batch) {
          const im = item.img;
          let b64 = '';
          try {
            const c = document.createElement('canvas');
            c.width = im.naturalWidth || im.width;
            c.height = im.naturalHeight || im.height;
            const ctx = c.getContext('2d');
            ctx.drawImage(im, 0, 0);
            b64 = c.toDataURL('image/jpeg', 0.86).split(',')[1];
          } catch (e1) {
            try {
              const r = await fetch(item.src, { credentials: 'include' });
              const blob = await r.blob();
              b64 = await new Promise(function(res) {
                const reader = new FileReader();
                reader.onloadend = function() {
                  res(reader.result.split(',')[1]);
                };
                reader.readAsDataURL(blob);
              });
            } catch (e2) {
              b64 = 'URL:' + item.src;
            }
          }
          output.push({ id: item.id, data: b64 });
        }
        return JSON.stringify(output);
      })();
      """;

      final rawExtract =
          await _webController!.evaluateJavascript(source: jsFindAndExtract);
      if (rawExtract == null) {
        throw Exception('ไม่สามารถดึงข้อมูลจากหน้าเว็บได้');
      }

      final List items = jsonDecode(rawExtract.toString()) as List;
      if (items.isEmpty) {
        throw Exception(
            'ไม่พบรูปหน้าการ์ตูนใหม่ให้แปล (ลองเลื่อนหน้าจอลงไปหน้าถัดไปดูนะเฮีย)');
      }

      int count = 0;
      for (final dynamic rawItem in items) {
        if (_cancelRequested) break;
        count++;
        final Map itemMap = rawItem as Map;
        final String imgId = itemMap['id'].toString();
        String imgData = itemMap['data'].toString();

        setState(() {
          _translateStatus =
              'กำลังคลีนและแปลหน้า $count / ${items.length} ทับลงในเว็บ...';
        });

        if (imgData.startsWith('URL:')) {
          final String url = imgData.substring(4);
          final resp = await http.get(
            Uri.parse(url),
            headers: {
              'Referer': _currentUrl,
              'User-Agent': _isDesktopMode ? _desktopUA : _mobileUA,
            },
          );
          if (resp.statusCode == 200) {
            imgData = base64Encode(resp.bodyBytes);
          } else {
            continue;
          }
        }

        final List blocks = (await _requestGeminiBoxes(imgData)) as List;
        if (_cancelRequested) break;

        await _injectTranslatedCanvasIntoWeb(imgId, imgData, blocks);
      }

      if (mounted && !_cancelRequested) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('แปลทับในหน้าเว็บเสร็จแล้ว $count หน้า! เลื่อนอ่านต่อได้เลย'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTranslating = false;
          _translateStatus = '';
        });
      }
    }
  }

  Future _requestGeminiBoxes(String base64Jpeg) async {
    final Uri uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_selectedModel:generateContent?key=$_apiKey',
    );

    const String prompt = '''
คุณคือนักแปลมังงะและมันฮวามืออาชีพ สแกนหาบอลลูนคำพูดและข้อความสำคัญในภาพนี้ แล้วแปลเป็นภาษาไทยที่ลื่นไหล เข้ากับอารมณ์ตัวละคร
ส่งกลับมาเป็น JSON Array เท่านั้น ตามโครงสร้างนี้:
[
  {
    "box_2d": [ymin, xmin, ymax, xmax],
    "text": "คำแปลภาษาไทย"
  }
]
โดยพิกัด box_2d เป็นสเกล 0 ถึง 1000 ที่คลุมเฉพาะตัวอักษรต้นฉบับในบอลลูน ห้ามใส่ข้อความอื่นนอกเหนือจาก JSON
''';

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Jpeg,
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
      throw Exception('API Error (${response.statusCode}): ${response.body}');
    }

    final Map decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final List? candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return [];

    String rawJson =
        candidates[0]['content']['parts'][0]['text'].toString().trim();
    rawJson = rawJson.replaceAll('```json', '').replaceAll('```', '').trim();

    final List parsed = jsonDecode(rawJson) as List;
    return parsed;
  }

  Future _injectTranslatedCanvasIntoWeb(
      String imgId, String base64Image, List blocks) async {
    final String blocksB64 = base64Encode(utf8.encode(jsonEncode(blocks)));

    final String jsRender = """
    (async function() {
      const targetImg = document.querySelector('img[data-tnk-id="$imgId"]');
      if (!targetImg) return;

      const blocks = JSON.parse(new TextDecoder().decode(
        Uint8Array.from(atob('$blocksB64'), function(c) { return c.charCodeAt(0); })
      ));

      const loader = new Image();
      await new Promise(function(res, rej) {
        loader.onload = res;
        loader.onerror = rej;
        loader.src = 'data:image/jpeg;base64,$base64Image';
      });

      const W = loader.naturalWidth || loader.width;
      const H = loader.naturalHeight || loader.height;
      const canvas = document.createElement('canvas');
      canvas.width = W;
      canvas.height = H;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(loader, 0, 0);

      for (const b of blocks) {
        const box = b.box_2d || [0, 0, 0, 0];
        const txt = (b.text || '').trim();
        if (!txt) continue;

        const y1 = Math.max(0, Math.floor((box[0] / 1000) * H));
        const x1 = Math.max(0, Math.floor((box[1] / 1000) * W));
        const y2 = Math.min(H - 1, Math.ceil((box[2] / 1000) * H));
        const x2 = Math.min(W - 1, Math.ceil((box[3] / 1000) * W));
        const bw = x2 - x1;
        const bh = y2 - y1;
        if (!(bw >= 12 && bh >= 12)) continue;

        const imgData = ctx.getImageData(x1, y1, bw, bh);
        const data = imgData.data;

        let rSum = 0, gSum = 0, bSum = 0, cnt = 0;
        for (let x = 0; bw > x; x += 2) {
          const topIdx = x * 4;
          const botIdx = ((bh - 1) * bw + x) * 4;
          rSum += data[topIdx] + data[botIdx];
          gSum += data[topIdx + 1] + data[botIdx + 1];
          bSum += data[topIdx + 2] + data[botIdx + 2];
          cnt += 2;
        }
        for (let y = 0; bh > y; y += 2) {
          const leftIdx = (y * bw) * 4;
          const rightIdx = (y * bw + (bw - 1)) * 4;
          rSum += data[leftIdx] + data[rightIdx];
          gSum += data[leftIdx + 1] + data[rightIdx + 1];
          bSum += data[leftIdx + 2] + data[rightIdx + 2];
          cnt += 2;
        }

        const bgR = cnt ? Math.round(rSum / cnt) : 255;
        const bgG = cnt ? Math.round(gSum / cnt) : 255;
        const bgB = cnt ? Math.round(bSum / cnt) : 255;
        const bgLum = 0.299 * bgR + 0.587 * bgG + 0.114 * bgB;

        const totalPx = bw * bh * 4;
        for (let idx = 0; totalPx > idx; idx += 4) {
          const lum = 0.299 * data[idx] + 0.587 * data[idx + 1] + 0.114 * data[idx + 2];
          if (Math.abs(lum - bgLum) >= 22) {
            data[idx] = bgR;
            data[idx + 1] = bgG;
            data[idx + 2] = bgB;
          }
        }
        ctx.putImageData(imgData, x1, y1);

        ctx.fillStyle = 'rgb(' + bgR + ',' + bgG + ',' + bgB + ')';
        const padX = Math.floor(bw * 0.04);
        const padY = Math.floor(bh * 0.04);
        ctx.fillRect(x1 + padX, y1 + padY, Math.max(4, bw - padX * 2), Math.max(4, bh - padY * 2));

        const graphemes = [];
        for (const ch of txt) {
          const code = ch.charCodeAt(0);
          const isCombining = (code >= 0x0E31 && 0x0E3A >= code) || (code >= 0x0E47 && 0x0E4E >= code);
          if (isCombining && graphemes.length) {
            graphemes[graphemes.length - 1] += ch;
          } else {
            graphemes.push(ch);
          }
        }

        let fontSize = Math.min(44, Math.max(14, Math.floor(Math.sqrt((bw * bh) / Math.max(4, graphemes.length)) * 0.85)));
        let lines = [];

        while (fontSize >= 12) {
          ctx.font = 'bold ' + fontSize + 'px sans-serif';
          lines = [];
          let curLine = '';
          for (const g of graphemes) {
            const testLine = curLine + g;
            if (ctx.measureText(testLine).width >= bw * 0.94 && curLine.length) {
              lines.push(curLine);
              curLine = g;
            } else {
              curLine = testLine;
            }
          }
          if (curLine) lines.push(curLine);
          if (bh * 0.95 >= lines.length * fontSize * 1.22) break;
          fontSize -= 2;
        }

        ctx.font = 'bold ' + fontSize + 'px sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.lineJoin = 'round';
        ctx.lineWidth = Math.max(3, Math.floor(fontSize * 0.24));

        const lineHeight = fontSize * 1.22;
        const totalTextH = lines.length * lineHeight;
        let startY = y1 + (bh - totalTextH) / 2 + lineHeight / 2;
        const centerX = x1 + bw / 2;

        const isDarkBg = 128 > bgLum;
        ctx.strokeStyle = isDarkBg ? '#000000' : '#FFFFFF';
        ctx.fillStyle = isDarkBg ? '#FFFFFF' : '#000000';

        for (const line of lines) {
          ctx.strokeText(line, centerX, startY);
          ctx.fillText(line, centerX, startY);
          startY += lineHeight;
        }
      }

      targetImg.removeAttribute('srcset');
      targetImg.removeAttribute('data-src');
      targetImg.removeAttribute('data-lazy-src');
      targetImg.src = canvas.toDataURL('image/jpeg', 0.92);
      targetImg.dataset.tnkTranslated = '1';
    })();
    """;

    await _webController?.evaluateJavascript(source: jsRender);
  }

  Widget _buildChromeTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1F22),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isHome ? Icons.home : Icons.home_outlined,
                  color: _isHome ? const Color(0xFF8AB4F8) : Colors.white70,
                ),
                tooltip: 'หน้าหลัก',
                onPressed: _goHome,
              ),
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF28292E),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _omniboxController,
                    textInputAction: TextInputAction.go,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'ค้นหาด้วย Google หรือพิมพ์ URL',
                      hintStyle:
                          const TextStyle(fontSize: 14, color: Colors.white54),
                      prefixIcon: Icon(
                        _isHome ? Icons.search : Icons.lock_outline,
                        size: 18,
                        color: Colors.white54,
                      ),
                      suffixIcon: _omniboxController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _omniboxController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: _navigateToInput,
                  ),
                ),
              ),
              if (!_isHome)
                IconButton(
                  icon: Icon(_isLoading ? Icons.close : Icons.refresh),
                  onPressed: () {
                    if (_isLoading) {
                      _webController?.stopLoading();
                    } else {
                      _webController?.reload();
                    }
                  },
                ),
              PopupMenuButton(
                icon: const Icon(Icons.more_vert),
                color: const Color(0xFF28292E),
                onSelected: (val) async {
                  if (val == 'bookmark') {
                    _toggleBookmark();
                  } else if (val == 'history') {
                    _openBookmarksAndHistorySheet();
                  } else if (val == 'desktop') {
                    _toggleDesktopMode();
                  } else if (val == 'clear_cache') {
                    await InAppWebViewController.clearAllCache();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ล้างแคชเว็บเรียบร้อย')),
                      );
                    }
                  } else if (val == 'settings') {
                    _openSettingsDialog();
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'bookmark',
                    child: Row(
                      children: [
                        Icon(
                          _isBookmarked()
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          color: _isBookmarked()
                              ? const Color(0xFF8AB4F8)
                              : Colors.white,
                        ),
                        const SizedBox(width: 12),
                        const Text('เพิ่ม/ลบบุ๊กมาร์กหน้านี้'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'history',
                    child: Row(
                      children: [
                        Icon(Icons.history),
                        SizedBox(width: 12),
                        Text('บุ๊กมาร์ก & ประวัติเข้าเว็บ'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'desktop',
                    child: Row(
                      children: [
                        Icon(
                          _isDesktopMode
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: _isDesktopMode
                              ? const Color(0xFF8AB4F8)
                              : Colors.white,
                        ),
                        const SizedBox(width: 12),
                        const Text('ขอหน้าเว็บแบบเดสก์ท็อป (PC)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear_cache',
                    child: Row(
                      children: [
                        Icon(Icons.cleaning_services_outlined),
                        SizedBox(width: 12),
                        Text('ล้างแคชของเบราว์เซอร์'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.key, color: Color(0xFFC58AF9)),
                        SizedBox(width: 12),
                        Text('ตั้งค่า Gemini API Key'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_isLoading && !_isHome)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: const Color(0xFF8AB4F8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHomeDashboard() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      children: [
        const SizedBox(height: 16),
        Center(
          child: Text(
            'TNK Browser',
            style: GoogleFonts.poppins(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'เบราว์เซอร์อ่านการ์ตูน & แปลไทยด้วย AI ในหน้าเว็บ',
            style: GoogleFonts.sarabun(fontSize: 14, color: Colors.white60),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF28292E),
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
            ],
          ),
          child: TextField(
            controller: _homeSearchController,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: 'ค้นหาผ่าน Google หรือวางลิงก์เว็บการ์ตูน...',
              border: InputBorder.none,
              icon: const Icon(Icons.search, color: Color(0xFF8AB4F8)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded,
                    color: Color(0xFF8AB4F8)),
                onPressed: () => _navigateToInput(_homeSearchController.text),
              ),
            ),
            onSubmitted: _navigateToInput,
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ทางลัดเว็บด่วน (กดค้างเพื่อลบ)',
              style: GoogleFonts.sarabun(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            TextButton.icon(
              onPressed: _showAddShortcutDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('เพิ่มเว็บ'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _shortcuts.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemBuilder: (ctx, i) {
            final item = _shortcuts[i] as Map;
            final String title = item['title'].toString();
            final String url = item['url'].toString();
            final String firstChar =
                title.isNotEmpty ? title.substring(0, 1).toUpperCase() : 'W';

            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _navigateToInput(url),
              onLongPress: () {
                setState(() => _shortcuts.removeAt(i));
                _saveData();
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF28292E),
                    child: Text(
                      firstChar,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8AB4F8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1F22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Icon(
                _apiKey.isNotEmpty ? Icons.verified_user : Icons.warning_amber,
                color:
                    _apiKey.isNotEmpty ? Colors.greenAccent : Colors.amberAccent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _apiKey.isNotEmpty
                          ? 'พร้อมแปลภาษาไทย ($_selectedModel)'
                          : 'ยังไม่ได้ตั้งค่า Gemini API Key',
                      style: GoogleFonts.sarabun(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'เปิดหน้าเว็บการ์ตูนเรื่องไหนก็ได้ แล้วกดปุ่ม "แปลหน้านี้" ด้านล่างเพื่อแปลทับในหน้าเว็บทันที',
                      style: GoogleFonts.sarabun(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _openSettingsDialog,
                child: const Text('ตั้งค่า'),
              ),
            ],
          ),
        ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'เข้าชมล่าสุด',
            style: GoogleFonts.sarabun(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          ..._history.take(5).map((item) {
            final Map h = item as Map;
            return Card(
              color: const Color(0xFF1E1F22),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.history, color: Colors.white54),
                title: Text(
                  h['title'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  h['url'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
                onTap: () => _navigateToInput(h['url'].toString()),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildBottomChromeBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1F22),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: (!_isHome && _canGoBack)
                  ? () => _webController?.goBack()
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 20),
              onPressed: (!_isHome && _canGoForward)
                  ? () => _webController?.goForward()
                  : null,
            ),
            ElevatedButton.icon(
              onPressed: _isTranslating ? null : _translateCurrentPageInPlace,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8AB4F8),
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                'แปลหน้านี้',
                style: GoogleFonts.sarabun(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                _isBookmarked() ? Icons.bookmark : Icons.bookmark_border,
                color:
                    _isBookmarked() ? const Color(0xFF8AB4F8) : Colors.white70,
              ),
              onPressed: _isHome ? null : _toggleBookmark,
            ),
            IconButton(
              icon: const Icon(Icons.collections_bookmark_outlined),
              onPressed: _openBookmarksAndHistorySheet,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_isHome && _webController != null) {
          final canBack = await _webController!.canGoBack();
          if (canBack) {
            await _webController!.goBack();
            return;
          } else {
            _goHome();
            return;
          }
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildChromeTopBar(),
              Expanded(
                child: Stack(
                  children: [
                    InAppWebView(
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        useWideViewPort: true,
                        loadWithOverviewMode: true,
                        builtInZoomControls: true,
                        displayZoomControls: false,
                        supportZoom: true,
                        mixedContentMode:
                            MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                        userAgent: _mobileUA,
                      ),
                      onWebViewCreated: (ctrl) => _webController = ctrl,
                      onLoadStart: (ctrl, url) {
                        if (url != null && url.toString() != 'about:blank') {
                          setState(() {
                            _isLoading = true;
                            _currentUrl = url.toString();
                            _omniboxController.text = url.toString();
                          });
                        }
                        _refreshNavigationState();
                      },
                      onProgressChanged: (ctrl, p) {
                        setState(() {
                          _progress = p / 100.0;
                          if (p == 100) _isLoading = false;
                        });
                      },
                      onLoadStop: (ctrl, url) async {
                        setState(() => _isLoading = false);
                        if (url != null && url.toString() != 'about:blank') {
                          final title = await ctrl.getTitle() ?? '';
                          setState(() {
                            _currentUrl = url.toString();
                            _currentTitle = title;
                            _omniboxController.text = url.toString();
                          });
                          _addHistoryItem(title, url.toString());
                        }
                        _refreshNavigationState();
                      },
                    ),
                    if (_isHome)
                      Container(
                        color: const Color(0xFF131314),
                        child: _buildHomeDashboard(),
                      ),
                    if (_isTranslating)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Material(
                          elevation: 8,
                          borderRadius: BorderRadius.circular(16),
                          color: const Color(0xFF28292E),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Color(0xFF8AB4F8),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    _translateStatus,
                                    style: GoogleFonts.sarabun(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() => _cancelRequested = true);
                                  },
                                  child: const Text(
                                    'หยุด',
                                    style: TextStyle(color: Colors.redAccent),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _buildBottomChromeBar(),
            ],
          ),
        ),
      ),
    );
  }
}
