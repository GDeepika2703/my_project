import 'dart:async';
import 'dart:convert';
//import 'dart:io';
import 'dart:typed_data';   // <-- ADD THIS LINE
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart'; // <-- NEW: Best way to save files
import 'firebase_msg.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  String name = '';
  String userId = '';
  String companyName = '';
  String sector = '';
  List<String> regions = [];

  final Map<String, ValueNotifier<bool>> _hoverStates = {};

  static const Duration idleTimeout = Duration(minutes: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    _hoverStates.values.forEach((notifier) => notifier.dispose());
    _hoverStates.clear();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _checkPersistentTimeout();
      if (mounted) await _loadUserData();
    } catch (e) {
      await _logout();
    }
  }

  Future<void> _updateLastInteraction() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_active', DateTime.now().toIso8601String());
  }

  Future<void> _checkPersistentTimeout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastActiveStr = prefs.getString('last_active');
      if (lastActiveStr == null) return await _logout();

      final lastActive = DateTime.tryParse(lastActiveStr);
      if (lastActive == null) return await _logout();

      if (DateTime.now().difference(lastActive) >= idleTimeout) {
        await _logout();
      }
    } catch (e) {
      await _logout();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPersistentTimeout();
    }
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loadedRegions = prefs.getStringList('regions') ?? ['Kache'];

      _hoverStates.clear();
      for (var region in loadedRegions) {
        _hoverStates[region] = ValueNotifier<bool>(false);
      }

      if (mounted) {
        setState(() {
          name = prefs.getString('name') ?? 'No Name';
          userId = prefs.getString('user_id') ?? 'No User ID';
          companyName = prefs.getString('company_name') ?? 'TMC';
          sector = prefs.getString('sector_name') ?? 'Mining';
          regions = loadedRegions;
        });
      }

      if (userId.isEmpty || userId == 'No User ID') {
        await _logout();
        return;
      }

      final region = regions.contains('Kache') ? 'Kache' : regions.first;
      await FirebaseMsg().initFCM(userId, region, companyName);
    } catch (e) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/signin', (route) => false);
    }
  }

  void _openWebPage(String url, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebPage(
          url: url,
          title: title,
          onActivity: _updateLastInteraction,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _updateLastInteraction(),
      onPanDown: (_) => _updateLastInteraction(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard'),
          actions: [
            IconButton(icon: const Icon(Icons.exit_to_app), onPressed: _logout),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Center(
                        child: Text(
                          'Hello, $name from $companyName',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    if (regions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Wrap(
                          spacing: 12.0,
                          runSpacing: 12.0,
                          alignment: WrapAlignment.center,
                          children: regions.map((region) {
                            return ValueListenableBuilder<bool>(
                              valueListenable: _hoverStates[region]!,
                              builder: (context, isHovered, child) {
                                return MouseRegion(
                                  onEnter: (_) => _hoverStates[region]!.value = true,
                                  onExit: (_) => _hoverStates[region]!.value = false,
                                  child: Container(
                                    width: 130,
                                    height: 200,
                                    decoration: BoxDecoration(
                                      color: isHovered ? const Color(0xFF921616) : const Color(0xFF333333),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ElevatedButton(
                                      onPressed: () {
                                        _updateLastInteraction();
                                        _openWebPage(
                                          'http://104.154.141.198:5003/dashboard.html?company=$companyName&sector=$sector&region=$region',
                                          'Dashboard - $region',
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: Text(
                                        region,
                                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text('No regions assigned', style: TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _logout,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Logout', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== WEBPAGE WITH PERFECT DOWNLOAD ====================

class WebPage extends StatefulWidget {
  final String url;
  final String title;
  final VoidCallback onActivity;

  const WebPage({super.key, required this.url, required this.title, required this.onActivity});

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController controller;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ActivityChannel',
        onMessageReceived: (_) => widget.onActivity(),
      )
      ..addJavaScriptChannel(
        'DownloadChannel',
        onMessageReceived: (message) => _handleDownload(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => isLoading = true),
          onPageFinished: (_) {
            setState(() => isLoading = false);
            _injectDownloadHandler();
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _injectDownloadHandler() {
    controller.runJavaScript('''
      window.flutterDownload = function(base64Data, fileName, mimeType) {
        DownloadChannel.postMessage(JSON.stringify({
          type: 'download',
          data: base64Data,
          fileName: fileName,
          mimeType: mimeType
        }));
        return true;
      };
      console.log('Flutter download handler injected');
    ''');
  }

  void _handleDownload(String message) {
    try {
      final data = json.decode(message);
      if (data['type'] == 'download') {
        _downloadFile(
          data['data'] as String,
          data['fileName'] as String,
          data['mimeType'] as String,
        );
      }
    } catch (e) {
      _showSnackBar('Download error: $e');
    }
  }

  // PERFECT DOWNLOAD FUNCTION — WORKS EVERYWHERE
  Future<void> _downloadFile(String base64Data, String fileName, String mimeType) async {
    try {
      // Decode base64 to bytes (Uint8List)
      final Uint8List bytes = base64.decode(base64Data);

      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Mine Haul Report',
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        lockParentWindow: true,
      );

      if (outputPath != null) {
      // No need to write manually—file_picker handles it via bytes
      _showSnackBar('✅ Report downloaded successfully!\nSaved to: $fileName');
      print('File saved to: $outputPath');
    }
    // If null → user cancelled (normal, no error)
  } catch (e) {
    print('Download error details: $e');  // For debugging
    _showSnackBar('❌ Download failed: ${e.toString()}');
  }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(message.contains('success') ? Icons.check_circle : Icons.error, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: message.contains('success') ? Colors.green : Colors.red,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

/*******************************
 *  HOMEPAGE + WEBPAGE (FINAL)
 *******************************/

/*import 'dart:async';
import 'dart:convert';
import 'dart:io';
//import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
//import 'package:flutter_downloader/flutter_downloader.dart';
//import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import 'firebase_msg.dart';

// ================= HOME PAGE =================
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  String name = '';
  String userId = '';
  String companyName = '';
  String sector = '';
  List<String> regions = [];

  final Map<String, ValueNotifier<bool>> _hoverStates = {};
  static const Duration idleTimeout = Duration(minutes: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    _hoverStates.values.forEach((v) => v.dispose());
    _hoverStates.clear();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initialize() async {
    await _checkPersistentTimeout();
    if (mounted) await _loadUserData();
  }

  Future<void> _updateLastInteraction() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_active', DateTime.now().toIso8601String());
  }

  Future<void> _checkPersistentTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString('last_active');
    if (last == null) return _logout();
    final lastTime = DateTime.tryParse(last);
    if (lastTime == null) return _logout();
    if (DateTime.now().difference(lastTime) >= idleTimeout) return _logout();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPersistentTimeout();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final loadedRegions = prefs.getStringList('regions') ?? ['Kache'];

    for (var region in loadedRegions) _hoverStates[region] = ValueNotifier(false);

    if (mounted) {
      setState(() {
        name = prefs.getString('name') ?? 'No Name';
        userId = prefs.getString('user_id') ?? 'No User ID';
        companyName = prefs.getString('company_name') ?? 'TMC';
        sector = prefs.getString('sector_name') ?? 'Mining';
        regions = loadedRegions;
      });
    }

    if (userId.isEmpty || userId == 'No User ID') return _logout();

    final region = regions.contains("Kache") ? "Kache" : regions.first;
    await FirebaseMsg().initFCM(userId, region, companyName);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushNamedAndRemoveUntil(context, '/signin', (r) => false);
  }

  void _openWebPage(String url, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebPage(
          url: url,
          title: title,
          onActivity: _updateLastInteraction,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _updateLastInteraction,
      onPanDown: (_) => _updateLastInteraction(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard'),
          actions: [
            IconButton(icon: const Icon(Icons.exit_to_app), onPressed: _logout),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      "Hello, $name from $companyName",
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 20),
                    if (regions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: regions.map((region) {
                            return ValueListenableBuilder<bool>(
                              valueListenable: _hoverStates[region]!,
                              builder: (_, hover, __) {
                                return MouseRegion(
                                  onEnter: (_) => _hoverStates[region]!.value = true,
                                  onExit: (_) => _hoverStates[region]!.value = false,
                                  child: SizedBox(
                                    width: 130,
                                    height: 200,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: hover
                                            ? const Color(0xFF921616)
                                            : const Color(0xFF333333),
                                      ),
                                      onPressed: () {
                                        _updateLastInteraction();
                                        _openWebPage(
                                          'http://104.154.141.198:5003/dashboard.html?company=$companyName&sector=$sector&region=$region',
                                          'Dashboard - $region',
                                        );
                                      },
                                      child: Text(
                                        region,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ),
                      )
                    else
                      const Text("No regions assigned", style: TextStyle(color: Colors.red)),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _logout,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text("Logout", style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= WEB PAGE WITH BACKGROUND DOWNLOAD =================
// ================= WEB PAGE WITH BACKGROUND DOWNLOAD =================
// ================= WEB PAGE WITH BACKGROUND DOWNLOAD =================
// ================= WEB PAGE WITH SIMPLIFIED DOWNLOAD =================
// ================= SIMPLE WEB PAGE WITH DIRECT DOWNLOAD =================
class WebPage extends StatefulWidget {
  final String url;
  final String title;
  final VoidCallback onActivity;

  const WebPage({
    super.key,
    required this.url,
    required this.title,
    required this.onActivity,
  });

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late WebViewController controller;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _initWebView();
  }

  Future<void> _requestPermissions() async {
    // Only request storage permission
    await Permission.storage.request();
  }

  void _initWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel("DownloadChannel",
          onMessageReceived: (msg) => _handleDownload(msg.message))
      ..addJavaScriptChannel("ActivityChannel",
          onMessageReceived: (_) => widget.onActivity())
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => isLoading = true),
        onPageFinished: (_) {
          setState(() => isLoading = false);
          _injectJS();
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  void _injectJS() {
    controller.runJavaScript("""
      // Simple download function - call this from your fuel panel
      window.flutterDownload = function(base64Data, fileName) {
        if(!fileName.endsWith('.xlsx')) fileName = fileName + '.xlsx';
        DownloadChannel.postMessage(JSON.stringify({
          base64: base64Data,
          fileName: fileName
        }));
      };

      // If your fuel panel has a specific button, you can auto-intercept it
      document.addEventListener('click', function(e) {
        const target = e.target;
        const buttonText = target.textContent?.toLowerCase() || '';
        
        // Look for download report buttons
        if (buttonText.includes('download') && buttonText.includes('report')) {
          console.log('Download report button clicked');
          // The page should handle the download and call window.flutterDownload
        }
      });
    """);
  }

  Future<void> _handleDownload(String msg) async {
    try {
      final data = json.decode(msg);
      
      if (data["base64"] != null) {
        await _saveExcelFile(data["base64"], data["fileName"]);
      }
    } catch (e) {
      print("Download error: $e");
      _show("Download failed: $e");
    }
  }

  Future<void> _saveExcelFile(String base64Data, String fileName) async {
    try {
      // Request storage permission
      final storageStatus = await Permission.storage.request();
      if (!storageStatus.isGranted) {
        _show("Storage permission denied");
        return;
      }

      // Get downloads directory
      final Directory downloadsDir = Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      // Clean filename
      String cleanFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      if (!cleanFileName.endsWith('.xlsx')) {
        cleanFileName += '.xlsx';
      }

      // Decode base64 data
      final bytes = base64.decode(base64Data);
      
      // Save file directly to downloads folder
      final file = File('${downloadsDir.path}/$cleanFileName');
      await file.writeAsBytes(bytes);

      // Show success message
      _show("✅ Excel file downloaded: $cleanFileName");

      print("📁 File successfully saved to: ${file.path}");

    } catch (e) {
      print("❌ Save error: $e");
      _show("❌ Download failed: ${e.toString()}");
    }
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (isLoading) 
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}*/
/*import 'dart:async';
//import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_msg.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  String name = '';
  String userId = '';
  String companyName = '';
  String sector = '';
  List<String> regions = [];
  
  final Map<String, ValueNotifier<bool>> _hoverStates = {};

  static const Duration idleTimeout = Duration(minutes: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    print('HomePage: initState called at ${DateTime.now().toIso8601String()}');
    _initialize();
  }

  @override
  void dispose() {
    _hoverStates.values.forEach((notifier) => notifier.dispose());
    _hoverStates.clear();
    WidgetsBinding.instance.removeObserver(this);
    print('HomePage: dispose called at ${DateTime.now().toIso8601String()}');
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      print('HomePage: Initializing, checking timeout');
      await _checkPersistentTimeout();
      if (mounted) {
        print('HomePage: Loading user data');
        await _loadUserData();
      } else {
        print('HomePage: Widget not mounted after timeout check');
      }
    } catch (e) {
      print('HomePage: Error in _initialize: $e');
      await _logout();
    }
  }

  Future<void> _updateLastInteraction() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    print('HomePage: Updating last_active to $now');
    await prefs.setString('last_active', now.toIso8601String());
  }

  Future<void> _checkPersistentTimeout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastActiveStr = prefs.getString('last_active');
      print('HomePage: Checking timeout, last_active: $lastActiveStr, keys: ${prefs.getKeys()}');

      if (lastActiveStr == null) {
        print('HomePage: No last_active found, logging out');
        await _logout();
        return;
      }

      final lastActive = DateTime.tryParse(lastActiveStr);
      if (lastActive == null) {
        print('HomePage: Invalid last_active format, logging out');
        await _logout();
        return;
      }

      final diff = DateTime.now().difference(lastActive);
      print('HomePage: Inactivity duration: $diff, idleTimeout: $idleTimeout');
      if (diff >= idleTimeout) {
        print('HomePage: Inactivity exceeded timeout, logging out');
        await _logout();
      } else {
        print('HomePage: Session still valid, no logout');
      }
    } catch (e) {
      print('HomePage: Error in _checkPersistentTimeout: $e');
      await _logout();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('HomePage: AppLifecycleState changed to $state at ${DateTime.now().toIso8601String()}');
    if (state == AppLifecycleState.resumed) {
      _checkPersistentTimeout();
    }
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loadedRegions = prefs.getStringList('regions') ?? ['Kache'];
      // Dispose old hover states
      _hoverStates.values.forEach((v) => v.dispose());
      _hoverStates.clear();
      // Create new hover states for loaded regions
      for (var region in loadedRegions) {
        _hoverStates[region] = ValueNotifier<bool>(false);
      }

      if (mounted) {
        setState(() {
          name = prefs.getString('name') ?? 'No Name';
          userId = prefs.getString('user_id') ?? 'No User ID';
          companyName = prefs.getString('company_name') ?? 'TMC';
          sector = prefs.getString('sector_name') ?? 'Mining';
          regions = loadedRegions;
        });
      }
      print('HomePage: Loaded user data: userId=$userId, regions=$regions');

      if (userId.isEmpty || userId == 'No User ID') {
        print('HomePage: Invalid user data, logging out');
        await _logout();
        return;
      }

      final region = regions.contains('Kache') ? 'Kache' : regions.isNotEmpty ? regions[0] : 'Kache';
      await FirebaseMsg().initFCM(userId, region, companyName);
    } catch (e) {
      print('HomePage: Error in _loadUserData: $e');
      await _logout();
    }
  }

  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      print('HomePage: Logging out, clearing SharedPreferences');
      await prefs.clear();
      print('HomePage: SharedPreferences after clear: ${prefs.getKeys()}');
      await Future.delayed(Duration.zero); // Allow frame to stabilize
      if (mounted) {
        print('HomePage: Navigating to /signin at ${DateTime.now().toIso8601String()}');
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/signin',
          (route) => false,
        );
      } else {
        print('HomePage: Widget not mounted, cannot navigate');
      }
    } catch (e) {
      print('HomePage: Error in _logout: $e');
    }
  }

  void _openWebPage(String url, String title) {
    print('HomePage: Opening WebPage: $url');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebPage(
          url: url,
          title: title,
          onActivity: _updateLastInteraction,
        ),
      ),
    );
  }

  void _openLiveStream(String region) {
    final streamUrl = "https://player.castr.com/live_3fac23b0a44511f0ac5315bf0429e7b0";
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveStreamPage(url: streamUrl, title: "Live Stream - $region"),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print('HomePage: Building UI for userId=$userId');
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        print('HomePage: User tapped screen at ${DateTime.now().toIso8601String()}');
        if (mounted) {
          _updateLastInteraction();
        }
      },
      onPanDown: (_) {
        print('HomePage: User panned screen at ${DateTime.now().toIso8601String()}');
        if (mounted) {
          _updateLastInteraction();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard'),
          actions: [
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              onPressed: () {
                print('HomePage: Manual logout pressed at ${DateTime.now().toIso8601String()}');
                _logout();
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Center(
                        child: Text(
                          'Hello, $name from $companyName',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    if (regions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Wrap(
                          spacing: 12.0,
                          runSpacing: 12.0,
                          alignment: WrapAlignment.center,
                          children: regions.map((region) {
                            return ValueListenableBuilder<bool>(
                              valueListenable: _hoverStates[region]!,
                              builder: (context, isHovered, child) {
                                return MouseRegion(
                                  onEnter: (_) => _hoverStates[region]!.value = true,
                                  onExit: (_) => _hoverStates[region]!.value = false,
                                  child: Container(
                                    width: 130,
                                    height: 200,
                                    decoration: BoxDecoration(
                                      color: isHovered
                                          ? const Color(0xFF921616)
                                          : const Color(0xFF333333),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ElevatedButton(
                                      onPressed: () {
                                        print('HomePage: Opening dashboard for region: $region at ${DateTime.now().toIso8601String()}');
                                        _updateLastInteraction();
                                        _openWebPage(
                                          'http://10.5.48.130:5001/dashboard.html?company=$companyName&sector=$sector&region=$region',
                                          'Dashboard - $region',
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        padding: const EdgeInsets.all(8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: Text(
                                        region,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.clip,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text('No regions assigned', style: TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 20),
                    // Live Stream Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (regions.isNotEmpty) {
                            _openLiveStream(regions[0]);
                          }
                        },
                        icon: const Icon(Icons.videocam, color: Colors.white),
                        label: const Text(
                          'Watch Live Stream',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            // Logout button pushed to bottom
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    print('HomePage: Manual logout pressed at ${DateTime.now().toIso8601String()}');
                    _logout();
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Logout', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WebPage extends StatefulWidget {
  final String url;
  final String title;
  final VoidCallback onActivity;

  const WebPage({
    super.key,
    required this.url,
    required this.title,
    required this.onActivity,
  });

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ActivityChannel',
        onMessageReceived: (message) {
          print('WebPage: Activity detected at ${DateTime.now().toIso8601String()}');
          widget.onActivity();
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showErrorDialog(context, "Error loading: ${error.description}");
              }
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: WebViewWidget(controller: controller),
    );
  }
}

class LiveStreamPage extends StatefulWidget {
  final String url;
  final String title;

  const LiveStreamPage({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<LiveStreamPage> createState() => _LiveStreamPageState();
}

class _LiveStreamPageState extends State<LiveStreamPage> {
  late final WebViewController controller;
  bool isLoading=true;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() => isLoading = true);
          },
          onPageFinished: (url) {
            if (mounted) setState(() => isLoading = false);
          },
          onWebResourceError: (error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error loading stream: ${error.description}')),
              );
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}*/
/*
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_msg.dart'; // Add this import

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String name = '';
  String userId = '';
  String companyName = '';
  String sector = '';
  List<String> regions = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      name = prefs.getString('name') ?? 'No Name';
      userId = prefs.getString('user_id') ?? 'No User ID';
      companyName = prefs.getString('company_name') ?? 'TMC';
      sector = prefs.getString('sector_name') ?? 'Mining';
      regions = prefs.getStringList('regions') ?? ['Kache'];
    });

    // Initialize FCM for logged-in user
    if (userId.isNotEmpty && userId != 'No User ID') {
      final region = regions.contains('Kache')
          ? 'Kache'
          : regions.isNotEmpty
              ? regions[0]
              : 'Kache';
      await FirebaseMsg().initFCM(userId, region, companyName);
    } else {
      // Fallback: Redirect to sign-in if no user_id
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/signin');
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/signin');
    }
  }

  void _openWebPage(String url, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebPage(url: url, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: Text(
                'Hello, $name from $companyName',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
          if (regions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Wrap(
                spacing: 12.0,
                runSpacing: 12.0,
                alignment: WrapAlignment.center,
                children: regions.map((region) {
                  bool isHovered = false;
                  return StatefulBuilder(
                    builder: (context, setState) {
                      return MouseRegion(
                        onEnter: (_) => setState(() => isHovered = true),
                        onExit: (_) => setState(() => isHovered = false),
                        child: Container(
                          width: 130,
                          height: 200,
                          decoration: BoxDecoration(
                            color: isHovered
                                ? const Color(0xFF921616)
                                : const Color(0xFF333333),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              _openWebPage(
                                'http:// 192.168.56.1:5001/dashboard.html?company=$companyName&sector=$sector&region=$region',
                                'Dashboard - $region',
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.all(8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              region,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.clip,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            )
          else
            const Text(
              'No regions assigned',
              style: TextStyle(color: Colors.red),
            ),
          const Spacer(),
          ElevatedButton(
            onPressed: _logout,
            child: const Text('Logout'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class WebPage extends StatelessWidget {
  final String url;
  final String title;

  const WebPage({super.key, required this.url, required this.title});

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            _showErrorDialog(context, "Error loading: ${error.description}");
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}*/
