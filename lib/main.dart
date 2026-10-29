import 'dart:convert';
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
        scaffoldBackgroundColor: const Color(0xFF1F1F1F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFA8C7FA),
          secondary: Color(0xFFD0BCFF),
          surface: Color(0xFF28292A),
        ),
      ),
      home: const ModernBrowserScreen(),
    );
  }
}

class ModernBrowserScreen extends StatefulWidget {
  const ModernBrowserScreen({super.key});

  @override
  State createState() => _ModernBrowserScreenState();
}

class _ModernBrowserScreenState extends State {
  InAppWebViewController? _webController;
  final TextEditingController _omniboxController = TextEditingController();
  final TextEditingController _homeSearchController = TextEditingController();
  final FocusNode _omniboxFocus = FocusNode();

  final ValueNotifier _progressNotifier = ValueNotifier(0.0);

  bool _isHome = true;
  String _currentUrl = '';
  String _currentTitle = 'New tab';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isDesktopMode = false;
  bool _showQuickTranslatePill = true;

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
    _omniboxFocus.addListener(() {
      if (_omniboxFocus.hasFocus) {
        _omniboxController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _omniboxController.text.length,
        );
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _omniboxController.dispose();
    _homeSearchController.dispose();
    _omniboxFocus.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  List _extractListSafely(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw;
    if (raw is Map) {
      for (final dynamic val in raw.values) {
        if (val is List) return val;
      }
      return [];
    }
    if (raw is String) {
      String cleaned =
          raw.replaceAll('```json', '').replaceAll('```', '').trim();
      if (cleaned.isEmpty) return [];
      try {
        final dynamic decoded = jsonDecode(cleaned);
        return _extractListSafely(decoded);
      } catch (_) {
        final int start = cleaned.indexOf('[');
        final int end = cleaned.lastIndexOf(']');
        if (start != -1 && end != -1 && end != start) {
          try {
            final dynamic sub = jsonDecode(cleaned.substring(start, end + 1));
            if (sub is List) return sub;
          } catch (_) {}
        }
      }
    }
    return [];
  }

  Future _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedShortcuts = prefs.getString('tnk_shortcuts');
    final savedBookmarks = prefs.getString('tnk_bookmarks');
    final savedHistory = prefs.getString('tnk_history');

    final List defaultShortcuts = [
      {'title': 'Google', 'url': 'https://www.google.com'},
      {'title': 'MangaDex', 'url': 'https://mangadex.org'},
      {'title': 'Webtoons', 'url': 'https://www.webtoons.com'},
      {'title': 'ManhuaUS', 'url': 'https://manhuaus.com'},
      {'title': 'Asura', 'url': 'https://asuracomic.net'},
      {'title': 'Naver', 'url': 'https://m.comic.naver.com'},
    ];

    setState(() {
      _apiKey = prefs.getString('gemini_api_key') ?? '';
      _selectedModel = prefs.getString('gemini_model') ?? 'gemini-2.5-flash';
      _showQuickTranslatePill = prefs.getBool('tnk_quick_pill') ?? true;
      _shortcuts = savedShortcuts != null
          ? _extractListSafely(savedShortcuts)
          : defaultShortcuts;
      _bookmarks =
          savedBookmarks != null ? _extractListSafely(savedBookmarks) : [];
      _history = savedHistory != null ? _extractListSafely(savedHistory) : [];
    });
  }

  Future _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tnk_shortcuts', jsonEncode(_shortcuts));
    await prefs.setString('tnk_bookmarks', jsonEncode(_bookmarks));
    await prefs.setString('tnk_history', jsonEncode(_history));
    await prefs.setBool('tnk_quick_pill', _showQuickTranslatePill);
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

  String _formatCleanUrl(String url) {
    if (url.isEmpty) return '';
    return url
        .replaceFirst('https://', '')
        .replaceFirst('http://', '')
        .replaceFirst('www.', '');
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
      _omniboxController.text = _formatCleanUrl(targetUrl);
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
    _history.removeWhere((item) => (item is Map) && item['url'] == url);
    _history.insert(0, {
      'title': title.isEmpty ? url : title,
      'url': url,
    });
    if (_history.length >= 50) {
      _history = _history.take(50).toList();
    }
    _saveData();
  }

  bool _isBookmarked() {
    if (_isHome || _currentUrl.isEmpty) return false;
    return _bookmarks
        .any((item) => (item is Map) && item['url'] == _currentUrl);
  }

  void _toggleBookmark() {
    if (_isHome || _currentUrl.isEmpty) return;
    setState(() {
      if (_isBookmarked()) {
        _bookmarks.removeWhere(
            (item) => (item is Map) && item['url'] == _currentUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบออกจากบุ๊กมาร์กแล้ว')),
        );
      } else {
        _bookmarks.insert(0, {
          'title': _currentTitle.isEmpty ? _currentUrl : _currentTitle,
          'url': _currentUrl,
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เพิ่มในบุ๊กมาร์กเรียบร้อย')),
        );
      }
    });
    _saveData();
  }

  Future _toggleDesktopMode() async {
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
    if (mounted && (back != _canGoBack || forward != _canGoForward)) {
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  void _openBraveStyleMenu() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Menu',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, anim1, anim2) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 10),
              child: Material(
                color: const Color(0xFF2B2C2E),
                elevation: 14,
                borderRadius: BorderRadius.circular(22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 285,
                    maxWidth: 285,
                    maxHeight: 560,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildCircleTopAction(
                                icon: Icons.arrow_back,
                                enabled: !_isHome && _canGoBack,
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _webController?.goBack();
                                },
                              ),
                              _buildCircleTopAction(
                                icon: Icons.arrow_forward,
                                enabled: !_isHome && _canGoForward,
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _webController?.goForward();
                                },
                              ),
                              _buildCircleTopAction(
                                icon: _isBookmarked()
                                    ? Icons.star
                                    : Icons.star_border,
                                activeColor: _isBookmarked()
                                    ? const Color(0xFFA8C7FA)
                                    : null,
                                enabled: !_isHome,
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _toggleBookmark();
                                },
                              ),
                              _buildCircleTopAction(
                                icon: Icons.home_outlined,
                                enabled: true,
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _goHome();
                                },
                              ),
                              _buildCircleTopAction(
                                icon: Icons.refresh,
                                enabled: !_isHome,
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _webController?.reload();
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Divider(color: Colors.white12, height: 1),
                        _buildMenuItem(
                          icon: Icons.add_box_outlined,
                          title: 'New tab (หน้าหลัก)',
                          onTap: () {
                            Navigator.pop(ctx);
                            _goHome();
                          },
                        ),
                        _buildMenuItem(
                          icon: Icons.g_translate,
                          title: 'Translate... (แปลหน้านี้เป็นไทย)',
                          highlight: true,
                          onTap: () {
                            Navigator.pop(ctx);
                            _translateCurrentPageInPlace();
                          },
                        ),
                        _buildMenuItem(
                          icon: _showQuickTranslatePill
                              ? Icons.visibility
                              : Icons.visibility_off_outlined,
                          title: _showQuickTranslatePill
                              ? 'ซ่อนปุ่มแปลลอยมุมจอ'
                              : 'แสดงปุ่มแปลลอยมุมจอ',
                          onTap: () {
                            Navigator.pop(ctx);
                            setState(() {
                              _showQuickTranslatePill =
                                  !_showQuickTranslatePill;
                            });
                            _saveData();
                          },
                        ),
                        const Divider(color: Colors.white12, height: 1),
                        _buildMenuItem(
                          icon: Icons.history,
                          title: 'History (ประวัติการเข้าเว็บ)',
                          onTap: () {
                            Navigator.pop(ctx);
                            _openBookmarksAndHistorySheet(initialIndex: 1);
                          },
                        ),
                        _buildMenuItem(
                          icon: Icons.star_outline,
                          title: 'Bookmarks (บุ๊กมาร์กที่บันทึก)',
                          onTap: () {
                            Navigator.pop(ctx);
                            _openBookmarksAndHistorySheet(initialIndex: 0);
                          },
                        ),
                        _buildMenuItem(
                          icon: Icons.delete_outline,
                          title: 'Delete browsing data (ล้างแคช)',
                          onTap: () async {
                            Navigator.pop(ctx);
                            await InAppWebViewController.clearAllCache();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('ล้างแคชเรียบร้อย')),
                              );
                            }
                          },
                        ),
                        const Divider(color: Colors.white12, height: 1),
                        _buildMenuItem(
                          icon: _isDesktopMode
                              ? Icons.check_box
                              : Icons.desktop_windows_outlined,
                          title: 'Desktop site (โหมดคอมพิวเตอร์)',
                          onTap: () {
                            Navigator.pop(ctx);
                            _toggleDesktopMode();
                          },
                        ),
                        _buildMenuItem(
                          icon: Icons.key_outlined,
                          title: 'AI Translator Settings (ตั้งค่าคีย์)',
                          onTap: () {
                            Navigator.pop(ctx);
                            _openSettingsDialog();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCircleTopAction({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    Color? activeColor,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Color(0xFF3A3B3E),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 21,
          color: enabled
              ? (activeColor ?? Colors.white)
              : Colors.white.withOpacity(0.28),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: highlight ? const Color(0xFFA8C7FA) : Colors.white,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.sarabun(
                  fontSize: 15,
                  fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                  color: highlight ? const Color(0xFFA8C7FA) : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddShortcutDialog() {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF28292A),
        title: Text('เพิ่มทางลัดหน้าหลัก', style: GoogleFonts.sarabun()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'ชื่อเว็บ (เช่น ManhuaUS)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: 'URL (เช่น manhuaus.com)',
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
        backgroundColor: const Color(0xFF28292A),
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
                labelText: 'ชื่อโมเดล (Model)',
                hintText: 'gemini-2.5-flash',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'แนะนำ gemini-2.5-flash หรือ gemini-2.0-flash แปลไวและแม่นยำ',
              style: TextStyle(fontSize: 12, color: Colors.white60),
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
                const SnackBar(content: Text('บันทึกตั้งค่าเรียบร้อย')),
              );
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  void _openBookmarksAndHistorySheet({int initialIndex = 0}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF28292A),
      isScrollControlled: true,
      builder: (ctx) => DefaultTabController(
        initialIndex: initialIndex,
        length: 2,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.star_outline), text: 'Bookmarks'),
                  Tab(icon: Icon(Icons.history), text: 'History'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _bookmarks.isEmpty
                        ? const Center(child: Text('ยังไม่มีบุ๊กมาร์ก'))
                        : ListView.builder(
                            itemCount: _bookmarks.length,
                            itemBuilder: (c, i) {
                              final Map item = Map.from(_bookmarks[i] as Map);
                              return ListTile(
                                leading: const Icon(Icons.star,
                                    color: Color(0xFFA8C7FA)),
                                title: Text(
                                  item['title']?.toString() ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  item['url']?.toString() ?? '',
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
                                    _openBookmarksAndHistorySheet(
                                        initialIndex: 0);
                                  },
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _navigateToInput(
                                      item['url']?.toString() ?? '');
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
                                    final Map item =
                                        Map.from(_history[i] as Map);
                                    return ListTile(
                                      leading: const Icon(Icons.public,
                                          color: Colors.white54),
                                      title: Text(
                                        item['title']?.toString() ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        item['url']?.toString() ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _navigateToInput(
                                            item['url']?.toString() ?? '');
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
        const SnackBar(content: Text('ใส่ Gemini API Key ก่อนเริ่มแปลนะครับ')),
      );
      return;
    }

    setState(() {
      _isTranslating = true;
      _cancelRequested = false;
      _translateStatus = 'กำลังดึงภาพหน้าการ์ตูน...';
    });

    try {
      await _webController!.evaluateJavascript(source: """
      window._tnkExtractState = 'WORKING';
      window._tnkExtractPayload = '[]';
      (async function() {
        try {
          const allImgs = Array.from(document.querySelectorAll('img'));
          const targets = [];
          let idx = 0;

          for (const img of allImgs) {
            idx++;
            const rect = img.getBoundingClientRect();
            const w = img.naturalWidth || img.width || rect.width;
            const h = img.naturalHeight || img.height || rect.height;
            if (!(w >= 220 && h >= 260)) continue;
            if (img.dataset.tnkTranslated === '1') continue;

            const dist = Math.abs(rect.top);
            const id = img.dataset.tnkId || ('tnk_img_' + Date.now() + '_' + idx);
            img.dataset.tnkId = id;

            const src = img.currentSrc || img.src || img.dataset.src || img.getAttribute('data-lazy-src') || img.getAttribute('data-original') || '';
            if (!src) continue;

            targets.push({ img: img, id: id, src: src, dist: dist });
          }

          targets.sort(function(a, b) { return a.dist - b.dist; });
          const batch = targets.slice(0, 6);
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
              b64 = c.toDataURL('image/jpeg', 0.85).split(',')[1];
            } catch (e1) {
              try {
                const r = await fetch(item.src, { credentials: 'include' });
                const blob = await r.blob();
                b64 = await new Promise(function(res) {
                  const reader = new FileReader();
                  reader.onloadend = function() {
                    const resStr = reader.result || '';
                    res(resStr.indexOf(',') !== -1 ? resStr.split(',')[1] : '');
                  };
                  reader.readAsDataURL(blob);
                });
              } catch (e2) {
                b64 = 'URL:' + item.src;
              }
            }
            if (b64) {
              output.push({ id: item.id, data: b64 });
            }
          }
          window._tnkExtractPayload = JSON.stringify(output);
          window._tnkExtractState = 'DONE';
        } catch (err) {
          window._tnkExtractPayload = 'ERROR:' + String(err);
          window._tnkExtractState = 'ERROR';
        }
      })();
      """);

      String stateStr = 'WORKING';
      int attempts = 0;
      while (stateStr == 'WORKING' && 50 != attempts && !_cancelRequested) {
        await Future.delayed(const Duration(milliseconds: 200));
        final st = await _webController!
            .evaluateJavascript(source: 'window._tnkExtractState');
        stateStr = st?.toString() ?? 'WORKING';
        attempts++;
      }

      final rawPayload = await _webController!
          .evaluateJavascript(source: 'window._tnkExtractPayload');
      final String payloadStr = rawPayload?.toString() ?? '[]';

      if (payloadStr.startsWith('ERROR:')) {
        throw Exception(payloadStr.substring(6));
      }

      final List items = _extractListSafely(payloadStr);
      if (items.isEmpty) {
        throw Exception(
            'ไม่พบรูปหน้าการ์ตูนใหม่ให้แปล (เลื่อนหน้าจอให้รูปโหลดก่อนนะเฮีย)');
      }

      int count = 0;
      for (final dynamic rawItem in items) {
        if (_cancelRequested) break;
        if (rawItem is! Map) continue;
        count++;

        final Map itemMap = Map.from(rawItem);
        final String imgId = itemMap['id']?.toString() ?? '';
        String imgData = itemMap['data']?.toString() ?? '';
        if (imgId.isEmpty || imgData.isEmpty) continue;

        setState(() {
          _translateStatus =
              'กำลังคลีน & แปลหน้า $count / ${items.length}...';
        });

        if (imgData.startsWith('URL:')) {
          final String url = imgData.substring(4).trim();
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

        final List blocks = await _requestGeminiBoxes(imgData);
        if (_cancelRequested) break;

        if (blocks.isNotEmpty) {
          await _injectTranslatedCanvasIntoWeb(imgId, imgData, blocks);
        }
      }

      if (mounted && !_cancelRequested) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('แปลทับลงในเว็บเรียบร้อย $count หน้า!'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 2),
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
คุณคือนักแปลมังงะและมันฮวามืออาชีพ สแกนหาบอลลูนคำพูดและข้อความสำคัญในภาพนี้ แล้วแปลเป็นภาษาไทยที่ลื่นไหลเป็นธรรมชาติ เข้ากับบริบทตัวละคร
ส่งกลับมาเป็น JSON Array เท่านั้น ตามโครงสร้างนี้:
[
  {
    "box_2d": [ymin, xmin, ymax, xmax],
    "text": "คำแปลภาษาไทย"
  }
]
โดยพิกัด box_2d เป็นตัวเลข 0 ถึง 1000 ที่คลุมเฉพาะตัวอักษรต้นฉบับในบอลลูน ห้ามใส่ข้อความอื่นนอกจาก JSON Array
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
      throw Exception('API Error (${response.statusCode})');
    }

    final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) return [];

    final List candidates = _extractListSafely(decoded['candidates']);
    if (candidates.isEmpty) return [];

    final dynamic firstCand = candidates[0];
    if (firstCand is! Map) return [];
    final dynamic content = firstCand['content'];
    if (content is! Map) return [];
    final List parts = _extractListSafely(content['parts']);
    if (parts.isEmpty) return [];

    final dynamic firstPart = parts[0];
    if (firstPart is! Map) return [];
    final String rawJson = firstPart['text']?.toString() ?? '[]';

    return _extractListSafely(rawJson);
  }

  Future _injectTranslatedCanvasIntoWeb(
      String imgId, String base64Image, List blocks) async {
    final String blocksB64 = base64Encode(utf8.encode(jsonEncode(blocks)));

    final String jsRender = """
    (async function() {
      const targetImg = document.querySelector('img[data-tnk-id="$imgId"]');
      if (!targetImg) return;

      const rawJsonStr = new TextDecoder().decode(
        Uint8Array.from(atob('$blocksB64'), function(c) { return c.charCodeAt(0); })
      );
      const parsedBlocks = JSON.parse(rawJsonStr);
      const blocks = Array.isArray(parsedBlocks) ? parsedBlocks : [];

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
        if (!b || !Array.isArray(b.box_2d)) continue;
        const box = b.box_2d;
        const txt = String(b.text || '').trim();
        if (!txt) continue;

        const y1 = Math.max(0, Math.floor((Number(box[0]) / 1000) * H));
        const x1 = Math.max(0, Math.floor((Number(box[1]) / 1000) * W));
        const y2 = Math.min(H - 1, Math.ceil((Number(box[2]) / 1000) * H));
        const x2 = Math.min(W - 1, Math.ceil((Number(box[3]) / 1000) * W));
        const bw = x2 - x1;
        const bh = y2 - y1;
        if (!(bw >= 12 && bh >= 12)) continue;

        const imgData = ctx.getImageData(x1, y1, bw, bh);
        const data = imgData.data;

        let rSum = 0, gSum = 0, bSum = 0, cnt = 0;
        for (let x = 0; bw != x && bw >= x; x += 2) {
          const topIdx = x * 4;
          const botIdx = ((bh - 1) * bw + x) * 4;
          rSum += data[topIdx] + data[botIdx];
          gSum += data[topIdx + 1] + data[botIdx + 1];
          bSum += data[topIdx + 2] + data[botIdx + 2];
          cnt += 2;
        }
        for (let y = 0; bh != y && bh >= y; y += 2) {
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
        for (let idx = 0; totalPx != idx && totalPx >= idx; idx += 4) {
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
          const isComb = (code >= 0x0E31 && 0x0E3A >= code) || (code >= 0x0E47 && 0x0E4E >= code);
          if (isComb && graphemes.length) {
            graphemes[graphemes.length - 1] += ch;
          } else {
            graphemes.push(ch);
          }
        }

        let fontSize = Math.min(42, Math.max(14, Math.floor(Math.sqrt((bw * bh) / Math.max(4, graphemes.length)) * 0.85)));
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

        const isDarkBg = 128 >= bgLum;
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

  Widget _buildMinimalTopBar() {
    return Container(
      color: const Color(0xFF1F1F1F),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF303134),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _omniboxController,
                          focusNode: _omniboxFocus,
                          textInputAction: TextInputAction.go,
                          style: const TextStyle(
                            fontSize: 15.5,
                            color: Color(0xFFE8EAED),
                            fontWeight: FontWeight.w400,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search or type URL',
                            hintStyle: TextStyle(
                              fontSize: 15.5,
                              color: Color(0xFF9AA0A6),
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                          onSubmitted: _navigateToInput,
                        ),
                      ),
                      if (_omniboxFocus.hasFocus &&
                          _omniboxController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _omniboxController.clear();
                            setState(() {});
                          },
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.close,
                                size: 19, color: Colors.white70),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _goHome,
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: const Color(0xFFE8EAED), width: 1.8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '1',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE8EAED),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.more_vert,
                  color: Color(0xFFE8EAED),
                  size: 24,
                ),
                onPressed: _openBraveStyleMenu,
              ),
            ],
          ),
          ValueListenableBuilder(
            valueListenable: _progressNotifier,
            builder: (context, value, child) {
              final double prog = value as double;
              if (_isHome || prog == 0.0 || prog >= 1.0) {
                return const SizedBox(height: 2);
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(
                  value: prog,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: const Color(0xFFA8C7FA),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHomeDashboard() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
      children: [
        const SizedBox(height: 24),
        Center(
          child: Text(
            'TNK',
            style: GoogleFonts.poppins(
              fontSize: 42,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFE8EAED),
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: const Color(0xFF303134),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Color(0xFF9AA0A6)),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _homeSearchController,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Search Google or type URL',
                    hintStyle: TextStyle(color: Color(0xFF9AA0A6)),
                    border: InputBorder.none,
                  ),
                  onSubmitted: _navigateToInput,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _shortcuts.length + 1,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemBuilder: (ctx, i) {
            if (i == _shortcuts.length) {
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _showAddShortcutDialog,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        color: Color(0xFF303134),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: Color(0xFFA8C7FA)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add site',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9AA0A6)),
                    ),
                  ],
                ),
              );
            }

            final Map item = Map.from(_shortcuts[i] as Map);
            final String title = item['title']?.toString() ?? 'Site';
            final String url = item['url']?.toString() ?? '';
            final String firstChar =
                title.isNotEmpty ? title.substring(0, 1).toUpperCase() : 'W';

            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _navigateToInput(url),
              onLongPress: () {
                setState(() => _shortcuts.removeAt(i));
                _saveData();
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFF303134),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      firstChar,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFA8C7FA),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFE8EAED)),
                  ),
                ],
              ),
            );
          },
        ),
      ],
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
              _buildMinimalTopBar(),
              Expanded(
                child: Stack(
                  children: [
                    InAppWebView(
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        databaseEnabled: true,
                        useHybridComposition: true,
                        hardwareAcceleration: true,
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
                          _progressNotifier.value = 0.05;
                          final String u = url.toString();
                          if (u != _currentUrl) {
                            setState(() {
                              _currentUrl = u;
                              if (!_omniboxFocus.hasFocus) {
                                _omniboxController.text = _formatCleanUrl(u);
                              }
                            });
                          }
                        }
                        _refreshNavigationState();
                      },
                      onProgressChanged: (ctrl, p) {
                        _progressNotifier.value = p / 100.0;
                      },
                      onLoadStop: (ctrl, url) async {
                        _progressNotifier.value = 1.0;
                        if (url != null && url.toString() != 'about:blank') {
                          final title = await ctrl.getTitle() ?? '';
                          final String u = url.toString();
                          setState(() {
                            _currentUrl = u;
                            _currentTitle = title;
                            if (!_omniboxFocus.hasFocus) {
                              _omniboxController.text = _formatCleanUrl(u);
                            }
                          });
                          _addHistoryItem(title, u);
                        }
                        _refreshNavigationState();
                      },
                    ),
                    if (_isHome)
                      Container(
                        color: const Color(0xFF1F1F1F),
                        child: _buildHomeDashboard(),
                      ),
                    if (!_isHome && _showQuickTranslatePill && !_isTranslating)
                      Positioned(
                        right: 14,
                        bottom: 20,
                        child: FloatingActionButton.small(
                          backgroundColor:
                              const Color(0xFF28292A).withOpacity(0.92),
                          foregroundColor: const Color(0xFFA8C7FA),
                          elevation: 6,
                          tooltip: 'แปลหน้านี้',
                          onPressed: _translateCurrentPageInPlace,
                          child: const Icon(Icons.g_translate, size: 20),
                        ),
                      ),
                    if (_isTranslating)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 18,
                        child: Material(
                          elevation: 10,
                          borderRadius: BorderRadius.circular(28),
                          color: const Color(0xFF28292A),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 10),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Color(0xFFA8C7FA),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    _translateStatus,
                                    style: GoogleFonts.sarabun(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
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
            ],
          ),
        ),
      ),
    );
  }
}
