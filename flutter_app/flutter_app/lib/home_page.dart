import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
//import 'package:intl/intl.dart';
class HomePage extends StatefulWidget {
const HomePage({super.key}); // :white_check_mark: Fix: added key parameter
@override
HomePageState createState() => HomePageState(); // :white_check_mark: Fix: public state class
}
class HomePageState extends State<HomePage> {
String name = '';
String userId = '';
String companyName = '';
String sectorName = '';
bool isLoading = false;
bool isWebViewLoaded = false;
late final WebViewController _webViewController;
@override
void initState() {
super.initState();
_loadUserData();
_webViewController = WebViewController()
..setJavaScriptMode(JavaScriptMode.unrestricted)
..setNavigationDelegate(
NavigationDelegate(
onPageStarted: (url) {
setState(() {
isLoading = true;
isWebViewLoaded = false;
});
},
onPageFinished: (url) {
setState(() {
isLoading = false;
isWebViewLoaded = true;
});
},
onWebResourceError: (error) {
_showErrorDialog('Error loading web resource: ${error.description}');
},
),
);
}

Future<void> _loadUserData() async {
final prefs = await SharedPreferences.getInstance();
setState(() {
name = prefs.getString('name') ?? 'No Name';
userId = prefs.getString('user_id') ?? 'No User ID';
companyName = prefs.getString('company_name') ?? 'No Company Name';
sectorName = prefs.getString('sector_name')?.toLowerCase() ?? '';
});
}
void _showErrorDialog(String message) {
showDialog(
context: context,
builder: (BuildContext context) => AlertDialog(
title: const Text('Error'),
content: Text(message),
actions: <Widget>[
TextButton(
onPressed: () => Navigator.of(context).pop(),
child: const Text('OK'),
),
],
),
);
}
Future<void> _logout() async {
final prefs = await SharedPreferences.getInstance();
await prefs.clear();
if (!mounted) return; // :white_check_mark: Fix: prevent context use after unmounted
Navigator.pushReplacementNamed(context, '/');
}
/*Future<void> _loadDashboard() async {
    if (companyName.isEmpty || sectorName.isEmpty) {
      _showErrorDialog('Company or Sector data missing.');
      return;
    }
    /*final effectiveSector = 
  (sectorName.toLowerCase() == 'fleet' || sectorName.toLowerCase() == 'fuel')
    ? 'mining'
    : sectorName.toLowerCase();*/

    final url = 'http://104.154.141.198:5001/dashboards/$sectorName.html'
        '?company=${Uri.encodeComponent(companyName)}'
        '&sector=${Uri.encodeComponent(sectorName)}';
    Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DashboardScreen(url: url),
    ),
  );
  }*/
  Future<void> _loadDashboard() async {
  const  url = 'http://104.154.141.198:5002/dashboards/mining.html';
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const DashboardScreen(url: url),
    ),
  );
}

  Future<void> _loadFleetManagement() async {
  try {
    final htmlString = await rootBundle.loadString('assets/dashboard/fleet.html');
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardScreen(htmlContent: htmlString, isLocal: true),
      ),
    );
  } catch (e) {
    _showErrorDialog('Failed to load Fleet Management: $e');
  }
}



Future<void> _loadFuelManagement() async {
  try {
    final htmlString = await rootBundle.loadString('assets/dashboard/fuel.html');
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardScreen(htmlContent: htmlString, isLocal: true),
      ),
    );
  } catch (e) {
    _showErrorDialog('Failed to load Fuel Management: $e');
  }
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
      body: Center(
  child: Column(
    mainAxisSize: MainAxisSize.max,
    mainAxisAlignment: MainAxisAlignment.start,
    children: [
      const SizedBox(height: 16),

      Text(
        'Hello, $name from $companyName',
        style: const TextStyle(fontSize: 16),
      ),

      const SizedBox(height: 8),

      ElevatedButton(
        onPressed: _loadDashboard,
        /*: Text(
  '${toBeginningOfSentenceCase(sectorName) ?? sectorName} Overview',
),*/
      child: const Text('Mining Overview'),
      ),
      const SizedBox(height: 12),
      ElevatedButton(
        onPressed: _loadFleetManagement,
        child: const Text('Fleet Management'),

      ),
      const SizedBox(height: 12),
      ElevatedButton(
        onPressed: _loadFuelManagement,
        child: const Text('Fuel Management'),
      ),
      Expanded(
        child: isWebViewLoaded
            ? WebViewWidget(controller: _webViewController)
            : Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Welcome to Velastra Dashboard',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 20),
                  Image.asset(
                    'assets/dashboard/velastra_logo.png',
                    width: 500,
                  ),
                ],
              ),
      ),
      
      if (isWebViewLoaded && !isLoading)
        const Text('WebView Loaded!'),

      const SizedBox(height: 20),

      ElevatedButton(
        onPressed: _logout,
        child: const Text('Logout'),
      ),
    ],
  ),
      ),
    );

  }
}
class DashboardScreen extends StatefulWidget {
  final String? url;
  final String? htmlContent;
  final bool isLocal;

  const DashboardScreen({
    super.key,
    this.url,
    this.htmlContent,
    this.isLocal = false,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
        ),
      );

    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      if (widget.isLocal && widget.htmlContent != null) {
        await _controller.loadHtmlString(widget.htmlContent!);
      } else if (widget.url != null) {
        await _controller.loadRequest(Uri.parse(widget.url!));
      }
    } catch (e) {
      _showErrorDialog('Failed to load dashboard: $e');
    }
  }

  void _showErrorDialog(String message) {
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
      appBar: AppBar(
        title: const Text('Dashboard View'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
