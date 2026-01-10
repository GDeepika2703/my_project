/*import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'firebase_msg.dart'; // Add this import

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  _SignInPageState createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  String completePhone = '';
  final TextEditingController _passwordController = TextEditingController();
  bool isPasswordVisible = false;
  String appVersion = '';
  bool _isLoading = false; // Add loading state
  String? _errorMessage; // Add error message state
  bool _isPressed=false; //to track the button
  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  void _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      appVersion = '${info.version}';
    });
  }

  Future<void> signIn(String phone, String password) async {
    if (!RegExp(r'^\d{4}$').hasMatch(password)) {
      _showError('PIN must be 4 digits.');
      return;
    }

    if (phone.isEmpty || password.isEmpty) {
      _showError('Please fill in both fields.');
      return;
    }

    final url = Uri.parse('http://10.5.48.130:5001/signin');
    bool isPhone = phone.length >= 6 && phone.length <= 15;
    if (!isPhone) {
      _showError('Invalid phone number format.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone_no': phone, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final user = data['user'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('name', user['name'] ?? 'Unknown');
        await prefs.setString('user_id', user['user_id'].toString());
        await prefs.setString('company_name', user['company_name'] ?? 'TMC');
        await prefs.setString('sector_name', user['sector_name'] ?? 'Mining');
        if (user['regions'] != null) {
          List<String> regions = List<String>.from(user['regions']);
          await prefs.setStringList('regions', regions);
          // Initialize FCM with first region (or Dalli Rajhara specifically)
          final region = regions.contains('Kache') ? 'Kache' : regions.isNotEmpty ? regions[0] : 'Kache';
          await FirebaseMsg().initFCM(
            user['user_id'].toString(),
            region,
            user['company_name'] ?? 'TMC',
          );
        } else {
          await prefs.setStringList('regions', ['Kache']); // Fallback
          await FirebaseMsg().initFCM(
            user['user_id'].toString(),
            'Kache',
            user['company_name'] ?? 'TMC',
          );
        }
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        _showError(data['message'] ?? 'An error occurred');
      }
    } catch (e) {
      print('Sign-in error: $e');
      _showError('Something went wrong. Please try again later.');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String msg) {
    setState(() {
      _errorMessage = msg;
    });
  }

  Widget _buildBoxField({required Widget child}) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.lightBlueAccent, Colors.blue[300]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400),
              child: Container(
                padding: EdgeInsets.all(20),
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Login",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 20),
                    if (_errorMessage != null)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    _buildBoxField(
                      child: IntlPhoneField(
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        initialCountryCode: 'IN',
                        onChanged: (phone) {
                          completePhone = phone.completeNumber;
                        },
                      ),
                    ),
                    _buildBoxField(
                      child: TextField(
                        controller: _passwordController,
                        obscureText: !isPasswordVisible,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: InputDecoration(
                          labelText: 'PIN',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          suffixIcon: IconButton(
                            icon: Icon(
                              isPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                isPasswordVisible = !isPasswordVisible;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    _isLoading
                        ? const CircularProgressIndicator()
                        : GestureDetector(
                            onTapDown: (_) => setState(() => _isPressed = true),
                            onTapUp: (_) => setState(() => _isPressed = false),
                            onTapCancel: () => setState(() => _isPressed = false),
                            onTap: () {
                              setState(() => _isPressed = false);
                              signIn(
                                completePhone,
                                _passwordController.text.trim(),
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              curve: Curves.easeInOut,
                              height: 50,
                              width: double.infinity,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _isPressed
                                    ? Colors.blue[800]
                                    : Colors.blue[600],
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _isPressed
                                    ? []
                                    : [
                                        BoxShadow(
                                          color: Colors.black26,
                                          offset: const Offset(0, 4),
                                          blurRadius: 6,
                                        ),
                                      ],
                              ),
                              child: const Text(
                                'Sign In',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                    SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/forgot'),
                      child: Text(
                        "Forgot Password?",
                        style: TextStyle(decoration: TextDecoration.underline),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/signup'),
                      child: Text(
                        "Don't have an account? Sign Up",
                        style: TextStyle(decoration: TextDecoration.underline),
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'App Version: $appVersion',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}*/

/*import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'firebase_msg.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  _SignInPageState createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  String completePhone = '';
  final TextEditingController _passwordController = TextEditingController();
  bool isPasswordVisible = false;
  String appVersion = '';
  bool _isLoading = false;
  String? _errorMessage;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  void _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      appVersion = info.version;
    });
  }

  Future<void> signIn(String phone, String password) async {
    if (!RegExp(r'^\d{4}$').hasMatch(password)) {
      _showError('PIN must be 4 digits.');
      return;
    }

    if (phone.isEmpty || password.isEmpty) {
      _showError('Please fill in both fields.');
      return;
    }

    final url = Uri.parse('http://104.154.141.198:5003/signin');
    bool isPhone = phone.length >= 6 && phone.length <= 15;
    if (!isPhone) {
      _showError('Invalid phone number format.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone_no': phone, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final user = data['user'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('name', user['name'] ?? 'Unknown');
        await prefs.setString('user_id', user['user_id'].toString());
        await prefs.setString('company_name', user['company_name'] ?? 'TMC');
        await prefs.setString('sector_name', user['sector_name'] ?? 'Mining');
        await prefs.setString('last_active', DateTime.now().toIso8601String()); // Set last_active
        List<String> regions = ['Kache']; // Fallback
        if (user['regions'] != null) {
          regions = List<String>.from(user['regions']);
          await prefs.setStringList('regions', regions);
        } else {
          await prefs.setStringList('regions', regions);
        }

        // Initialize FCM with first region (or Kache specifically)
        final region = regions.contains('Kache') ? 'Kache' : regions.isNotEmpty ? regions[0] : 'Kache';
        await FirebaseMsg().initFCM(
          user['user_id'].toString(),
          region,
          user['company_name'] ?? 'TMC',
        );

        // Navigate to home and clear navigation stack
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/home',
            (route) => false, // Remove all previous routes
          );
        }
      } else {
        _showError(data['message'] ?? 'Login failed. Please try again.');
      }
    } catch (e) {
      print('Sign-in error: $e');
      if (e.toString().contains('SocketException')) {
        _showError('Network error. Please check your connection and try again.');
      } else {
        _showError('Something went wrong. Please try again later.');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String msg) {
    setState(() {
      _errorMessage = msg;
    });
  }

  Widget _buildBoxField({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.lightBlueAccent, Colors.blue[300]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Login",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    _buildBoxField(
                      child: IntlPhoneField(
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        initialCountryCode: 'IN',
                        onChanged: (phone) {
                          completePhone = phone.completeNumber;
                        },
                      ),
                    ),
                    _buildBoxField(
                      child: TextField(
                        controller: _passwordController,
                        obscureText: !isPasswordVisible,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: InputDecoration(
                          labelText: 'PIN',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          suffixIcon: IconButton(
                            icon: Icon(
                              isPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                isPasswordVisible = !isPasswordVisible;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _isLoading
                        ? const CircularProgressIndicator()
                        : GestureDetector(
                            onTapDown: (_) => setState(() => _isPressed = true),
                            onTapUp: (_) => setState(() => _isPressed = false),
                            onTapCancel: () => setState(() => _isPressed = false),
                            onTap: () {
                              setState(() => _isPressed = false);
                              signIn(
                                completePhone,
                                _passwordController.text.trim(),
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              curve: Curves.easeInOut,
                              height: 50,
                              width: double.infinity,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _isPressed
                                    ? Colors.blue[800]
                                    : Colors.blue[600],
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _isPressed
                                    ? []
                                    : const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          offset: Offset(0, 4),
                                          blurRadius: 6,
                                        ),
                                      ],
                              ),
                              child: const Text(
                                'Sign In',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/forgot'),
                      child: const Text(
                        "Forgot Password?",
                        style: TextStyle(decoration: TextDecoration.underline),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/signup'),
                      child: const Text(
                        "Don't have an account? Sign Up",
                        style: TextStyle(decoration: TextDecoration.underline),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'App Version: $appVersion',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}*/


/*import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'firebase_msg.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  _SignInPageState createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  String selectedCountryCode = "+91";
  String _initialPhoneValue = '';  // ← NEW: For pre-filling phone number
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool isPasswordVisible = false;
  String appVersion = '';
  bool _isLoading = false;
  String? _errorMessage;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadSavedCredentials();
  }

  void _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      appVersion = info.version;
    });
  }

  /// Load last saved phone and password
  void _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPhone = prefs.getString("saved_phone");
    final savedPass = prefs.getString("saved_pass");
    final savedCode = prefs.getString("saved_country_code");

    if (savedPhone != null && savedPass != null && savedCode != null) {
      if (mounted) {
        setState(() {
          selectedCountryCode = savedCode;
          _initialPhoneValue = savedPhone;  // ← Use initialValue for phone
          _passwordController.text = savedPass;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Auto-filled last login credentials"),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Save phone + password
  Future<void> _saveCredentials(
      String phone, String password, String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("saved_phone", phone);
    await prefs.setString("saved_pass", password);
    await prefs.setString("saved_country_code", code);
  }

  Future<void> signIn(String phone, String password) async {
    if (!RegExp(r'^\d{4}$').hasMatch(password)) {
      _showError('PIN must be 4 digits.');
      return;
    }

    if (phone.isEmpty || password.isEmpty) {
      _showError('Please fill in both fields.');
      return;
    }

    final url = Uri.parse('http://104.154.141.198:5003/signin');
    bool isPhone = phone.length >= 6 && phone.length <= 15;
    if (!isPhone) {
      _showError('Invalid phone number format.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone_no': phone, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await _saveCredentials(
          _phoneController.text.trim(),
          password,
          selectedCountryCode,
        );

        final user = data['user'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('name', user['name'] ?? 'Unknown');
        await prefs.setString('user_id', user['user_id'].toString());
        await prefs.setString('company_name', user['company_name'] ?? 'TMC');
        await prefs.setString('sector_name', user['sector_name'] ?? 'Mining');
        await prefs.setString(
            'last_active', DateTime.now().toIso8601String());

        List<String> regions = ['Kache'];
        if (user['regions'] != null) {
          regions = List<String>.from(user['regions']);
        }
        await prefs.setStringList('regions', regions);

        final region =
            regions.contains('Kache') ? 'Kache' : (regions.isNotEmpty ? regions[0] : 'Kache');

        await FirebaseMsg().initFCM(
          user['user_id'].toString(),
          region,
          user['company_name'] ?? 'TMC',
        );

        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/home',
            (route) => false,
          );
        }
      } else {
        _showError(data['message'] ?? 'Login failed. Please try again.');
      }
    } catch (e) {
      if (e.toString().contains('SocketException')) {
        _showError('Network error. Please check your connection.');
      } else {
        _showError('Something went wrong.');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String msg) {
    setState(() {
      _errorMessage = msg;
    });
  }

  Widget _buildBoxField({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.lightBlueAccent, Colors.blue[300]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Login",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),

                    /// Phone Field with ALL country codes
                    _buildBoxField(
                      child: IntlPhoneField(
                        initialValue: _initialPhoneValue,  // ← NEW: Prefills the number part
                        initialCountryCode: selectedCountryCode.replaceAll("+", ""),  // ← NEW: Prefills country
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        onCountryChanged: (country) {
                          selectedCountryCode = "+${country.dialCode}";
                        },
                      ),
                    ),

                    /// Password Field
                    _buildBoxField(
                      child: TextField(
                        controller: _passwordController,
                        obscureText: !isPasswordVisible,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: InputDecoration(
                          labelText: 'PIN',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          suffixIcon: IconButton(
                            icon: Icon(
                                isPasswordVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                isPasswordVisible = !isPasswordVisible;
                              });
                            },
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    /// Sign In Button
                    _isLoading
                        ? const CircularProgressIndicator()
                        : GestureDetector(
                            onTapDown: (_) => setState(() => _isPressed = true),
                            onTapUp: (_) => setState(() => _isPressed = false),
                            onTapCancel: () => setState(() => _isPressed = false),
                            onTap: () {
                              setState(() => _isPressed = false);

                              final fullPhone =
                                  "$selectedCountryCode${_phoneController.text.trim()}";

                              signIn(fullPhone, _passwordController.text.trim());
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              curve: Curves.easeInOut,
                              height: 50,
                              width: double.infinity,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color:
                                    _isPressed ? Colors.blue[800] : Colors.blue[600],
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _isPressed
                                    ? []
                                    : const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          offset: Offset(0, 4),
                                          blurRadius: 6,
                                        ),
                                      ],
                              ),
                              child: const Text(
                                'Sign In',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                    const SizedBox(height: 10),

                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/forgot'),
                      child: const Text(
                        "Forgot Password?",
                        style: TextStyle(decoration: TextDecoration.underline),
                      ),
                    ),

                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/signup'),
                      child: const Text(
                        "Don't have an account? Sign Up",
                        style: TextStyle(decoration: TextDecoration.underline),
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'App Version: $appVersion',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}*/


/*import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'firebase_msg.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  String completePhone = '';
  String nationalNumber = '';
  String selectedDialCode = "+91";

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool isPasswordVisible = false;
  String appVersion = '1.0.0';
  bool _isLoading = false;
  String? _errorMessage;
  bool _isPressed = false;
  bool _rememberMe = true;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadSavedCredentials();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => appVersion = info.version);
    } catch (e) {
      setState(() => appVersion = '1.0.0');
    }
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final savedPhone = await _secureStorage.read(key: 'saved_phone');
      final savedPassword = await _secureStorage.read(key: 'saved_password');
      final rememberMe = await _secureStorage.read(key: 'remember_me');

      if (savedPhone != null && savedPhone.isNotEmpty) {
        final digits = savedPhone.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length >= 10) {
          final tenDigits = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
          setState(() {
            nationalNumber = tenDigits;
            _phoneController.text = tenDigits;
            completePhone = savedPhone;
          });
        }
      }

      if (savedPassword != null && savedPassword.isNotEmpty && rememberMe == 'true') {
        setState(() {
          _passwordController.text = savedPassword;
          _rememberMe = true;
        });
      } else {
        setState(() {
          _rememberMe = rememberMe == 'true';
        });
      }
    } catch (e) {
      print('Error loading saved credentials: $e');
    }
  }

  String _getFullPhoneNumber() {
    final digits = nationalNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) {
      return '$selectedDialCode$digits';
    }
    return completePhone.isNotEmpty ? completePhone : '$selectedDialCode$digits';
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  Future<void> signIn() async {
    final password = _passwordController.text.trim();

    if (!RegExp(r'^\d{4}$').hasMatch(password)) {
      _showError('PIN must be exactly 4 digits.');
      return;
    }
    if (nationalNumber.length != 10) {
      _showError('Please enter a valid 10-digit phone number.');
      return;
    }

    final hasInternet = await _checkInternetConnection();
    if (!hasInternet) {
      _showError('No internet connection. Please check your network and try again.');
      return;
    }

    final fullPhone = _getFullPhoneNumber();
    print('Sending to backend: $fullPhone');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('http://104.154.141.198:5003/signin'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone_no': fullPhone, 'password': password}),
      ).timeout(const Duration(seconds: 30));

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['user'] != null) {
        final user = data['user'];
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString('name', user['name'] ?? 'User');
        await prefs.setString('user_id', user['user_id'].toString());
        await prefs.setString('company_name', user['company_name'] ?? 'TMC');
        await prefs.setString('sector_name', user['sector_name'] ?? 'Mining');
        await prefs.setString('last_active', DateTime.now().toIso8601String());

        if (_rememberMe) {
          await _secureStorage.write(key: 'saved_phone', value: fullPhone);
          await _secureStorage.write(key: 'saved_password', value: password);
          await _secureStorage.write(key: 'remember_me', value: 'true');
        } else {
          await _secureStorage.delete(key: 'saved_phone');
          await _secureStorage.delete(key: 'saved_password');
          await _secureStorage.write(key: 'remember_me', value: 'false');
        }

        List<String> regions = ['Kache'];
        if (user['regions'] != null && user['regions'] is List) {
          regions = List<String>.from(user['regions']);
        }
        await prefs.setStringList('regions', regions);

        final region = regions.contains('Kache')
            ? 'Kache'
            : regions.isNotEmpty
                ? regions[0]
                : 'Kache';

        await FirebaseMsg().initFCM(
          user['user_id'].toString(),
          region,
          user['company_name'] ?? 'TMC',
        );

        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        }
      } else {
        final errorMsg = data['message'] ?? 'Invalid credentials. Please check your phone number and PIN.';
        _showError(errorMsg);
      }
    } on SocketException catch (e) {
      _showError('Network error: Unable to connect to server. Please check your internet connection.');
      print('SocketException: $e');
    } on http.ClientException catch (e) {
      _showError('Connection failed. Please check if the server is running and try again.');
      print('ClientException: $e');
    } on FormatException catch (e) {
      _showError('Invalid response from server. Please contact support.');
      print('FormatException: $e');
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('timed out')) {
        _showError('Request timeout. Server is taking too long to respond. Please try again.');
      } else {
        _showError('An unexpected error occurred. Please try again.');
      }
      print('Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      setState(() => _errorMessage = msg);
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) setState(() => _errorMessage = null);
      });
    }
  }

  Future<void> _clearSavedCredentials() async {
    await _secureStorage.delete(key: 'saved_phone');
    await _secureStorage.delete(key: 'saved_password');
    await _secureStorage.write(key: 'remember_me', value: 'false');
    
    setState(() {
      _phoneController.clear();
      _passwordController.clear();
      nationalNumber = '';
      completePhone = '';
      _rememberMe = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved credentials cleared')),
    );
  }

  Widget _buildBoxField({required Widget child}) =>
      Container(margin: const EdgeInsets.symmetric(vertical: 8), child: child);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.lightBlueAccent, Colors.blue],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Login", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),

                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error, color: Colors.red),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                                  if (_errorMessage!.contains('internet') || _errorMessage!.contains('network'))
                                    const SizedBox(height: 4),
                                  if (_errorMessage!.contains('internet') || _errorMessage!.contains('network'))
                                    Text(
                                      'Check your WiFi or mobile data',
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    _buildBoxField(
                      child: Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: (value) => setState(() => _rememberMe = value ?? true),
                          ),
                          const Text('Remember me'),
                          const SizedBox(width: 8),
                          Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                          const Spacer(),
                          GestureDetector(
                            onTap: _clearSavedCredentials,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Clear',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    _buildBoxField(
                      child: AutofillGroup(
                        child: TextField(
                          controller: _phoneController,
                          autofillHints: const [AutofillHints.telephoneNumberNational],
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Phone Number',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                            prefixIcon: CountryCodePicker(
                              onChanged: (code) {
                                setState(() {
                                  selectedDialCode = code.dialCode ?? "+91";
                                });
                              },
                              initialSelection: 'IN',
                              favorite: const ['IN'],
                              showFlag: true,
                              showDropDownButton: true,
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              nationalNumber = value;
                              completePhone = value.length == 10 ? '$selectedDialCode$value' : '';
                            });
                          },
                        ),
                      ),
                    ),

                    _buildBoxField(
                      child: TextField(
                        controller: _passwordController,
                        obscureText: !isPasswordVisible,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.password],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: InputDecoration(
                          labelText: '4-Digit PIN',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          suffixIcon: IconButton(
                            icon: Icon(isPasswordVisible ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => isPasswordVisible = !isPasswordVisible),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    _isLoading
                        ? const Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Connecting to server...', style: TextStyle(color: Colors.grey)),
                            ],
                          )
                        : GestureDetector(
                            onTapDown: (_) => setState(() => _isPressed = true),
                            onTapUp: (_) => setState(() => _isPressed = false),
                            onTapCancel: () => setState(() => _isPressed = false),
                            onTap: signIn,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              height: 54,
                              width: double.infinity,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _isPressed ? Colors.blue[800] : Colors.blue,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: _isPressed
                                    ? null
                                    : [
                                        const BoxShadow(
                                          color: Color(0x666495ED),
                                          blurRadius: 10,
                                          offset: Offset(0, 5),
                                        )
                                      ],
                              ),
                              child: const Text(
                                'Sign In',
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),

                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/forgot'),
                      child: const Text("Forgot PIN?"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/signup'),
                      child: const Text("Don't have an account? Sign Up"),
                    ),
                    const SizedBox(height: 10),
                    Text('v$appVersion', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}*/

import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'firebase_msg.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  _SignInPageState createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final TextEditingController _passwordController = TextEditingController();
  bool isPasswordVisible = false;
  String appVersion = '';
  bool _isLoading = false;
  String? _errorMessage;
  bool _isPressed = false;
  bool _rememberMe = true;

  // Controllers for phone field
  final TextEditingController _phoneController = TextEditingController();

  // Secure storage for credentials
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadSavedCredentials();
  }

  void _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      appVersion = info.version;
    });
  }

  // Load saved phone and password
  Future<void> _loadSavedCredentials() async {
    try {
      final savedPhone = await _secureStorage.read(key: 'saved_phone');
      final savedPassword = await _secureStorage.read(key: 'saved_password');
      final rememberMe = await _secureStorage.read(key: 'remember_me');

      if (savedPhone != null && savedPhone.isNotEmpty) {
        // Extract just the national number (remove country code)
        final nationalNumber = _extractNationalNumber(savedPhone);
        
        print('🔍 Loading saved credentials:');
        print('   Saved phone: $savedPhone');
        print('   National number: $nationalNumber');
        
        // Set the phone controller text with just the national number (10 digits)
        _phoneController.text = nationalNumber;
      }

      if (savedPassword != null && savedPassword.isNotEmpty && rememberMe == 'true') {
        setState(() {
          _passwordController.text = savedPassword;
          _rememberMe = true;
        });
      } else {
        setState(() {
          _rememberMe = rememberMe == 'true';
        });
      }
    } catch (e) {
      print('Error loading saved credentials: $e');
    }
  }

  // Extract national number from complete phone (remove country code)
  String _extractNationalNumber(String completePhone) {
    // If it starts with +91, remove it directly
    if (completePhone.startsWith('+91') && completePhone.length > 3) {
      return completePhone.substring(3); // Remove '+91'
    }
    
    // Remove all non-digit characters first
    final digits = completePhone.replaceAll(RegExp(r'[^0-9]'), '');
    
    // For Indian numbers (91), remove the first 2 digits (91)
    if (digits.startsWith('91') && digits.length >= 12) {
      return digits.substring(2); // Returns just the 10-digit number
    }
    
    return digits; // Fallback
  }

  Future<void> signIn() async {
    final password = _passwordController.text.trim();
    final nationalNumber = _phoneController.text.trim();

    // Validate inputs
    if (nationalNumber.length != 10) {
      _showError('Phone number must be exactly 10 digits.');
      return;
    }

    if (!RegExp(r'^\d{4}$').hasMatch(password)) {
      _showError('PIN must be 4 digits.');
      return;
    }

    // Try different phone formats that your backend might accept
    final phoneFormats = [
      '+91$nationalNumber', // +911234567890 (correct format for your database)
      '91$nationalNumber',  // 911234567890
      nationalNumber,       // 1234567890
    ];

    print('🚀 Testing different phone formats:');
    for (int i = 0; i < phoneFormats.length; i++) {
      print('   Format ${i + 1}: ${phoneFormats[i]}');
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Try each format until one works
    for (int i = 0; i < phoneFormats.length; i++) {
      final phoneToSend = phoneFormats[i];
      
      print('\n🔑 Attempting sign in with format ${i + 1}:');
      print('   Phone: $phoneToSend');
      print('   Password: $password');

      final result = await _attemptSignIn(phoneToSend, password);
      
      if (result['success']) {
        // Success! Save the working format
        if (_rememberMe) {
          await _secureStorage.write(key: 'saved_phone', value: phoneToSend);
          await _secureStorage.write(key: 'saved_password', value: password);
          await _secureStorage.write(key: 'remember_me', value: 'true');
          print('💾 Saved working phone format: $phoneToSend');
        }
        return;
      }
      
      if (i == phoneFormats.length - 1) {
        // Last attempt failed
        _showError(result['message'] ?? 'Invalid credentials. Please check your phone number and PIN.');
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<Map<String, dynamic>> _attemptSignIn(String phone, String password) async {
    final url = Uri.parse('http://104.154.141.198:5003/signin');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone_no': phone,
          'password': password
        }),
      ).timeout(const Duration(seconds: 30));

      print('📡 API Response for $phone:');
      print('   Status Code: ${response.statusCode}');
      print('   Response Body: ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['user'] != null) {
        final user = data['user'];
        final prefs = await SharedPreferences.getInstance();
        
        // Save user data
        await prefs.setString('name', user['name'] ?? 'Unknown');
        await prefs.setString('user_id', user['user_id'].toString());
        await prefs.setString('company_name', user['company_name'] ?? 'TMC');
        await prefs.setString('sector_name', user['sector_name'] ?? 'Mining');
        await prefs.setString('last_active', DateTime.now().toIso8601String());
        
        // Save regions
        List<String> regions = ['Kache'];
        if (user['regions'] != null) {
          regions = List<String>.from(user['regions']);
          await prefs.setStringList('regions', regions);
        } else {
          await prefs.setStringList('regions', regions);
        }

        // Initialize FCM
        final region = regions.contains('Kache') ? 'Kache' : regions.isNotEmpty ? regions[0] : 'Kache';
        await FirebaseMsg().initFCM(
          user['user_id'].toString(),
          region,
          user['company_name'] ?? 'TMC',
        );

        // Navigate to home
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/home',
            (route) => false,
          );
        }
        
        return {'success': true};
      } else {
        final errorMsg = data['message'] ?? 'Invalid credentials';
        return {
          'success': false,
          'message': errorMsg
        };
      }
    } catch (e) {
      print('❌ Sign-in error for $phone: $e');
      return {
        'success': false,
        'message': 'Network error. Please check your connection.'
      };
    }
  }

  // Clear saved credentials
  Future<void> _clearSavedCredentials() async {
    await _secureStorage.delete(key: 'saved_phone');
    await _secureStorage.delete(key: 'saved_password');
    await _secureStorage.write(key: 'remember_me', value: 'false');
    
    setState(() {
      _phoneController.clear();
      _passwordController.clear();
      _rememberMe = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved credentials cleared')),
    );
  }

  void _showError(String msg) {
    if (mounted) {
      setState(() {
        _errorMessage = msg;
      });
    }
  }

  Widget _buildBoxField({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.lightBlueAccent, Colors.blue[300]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Login",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error, color: Colors.red, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),

                    _buildBoxField(
                      child: IntlPhoneField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          counterText: "", // Hide character counter
                        ),
                        initialCountryCode: 'IN',
                        onChanged: (phone) {
                          // We don't need to store country code separately
                        },
                        onCountryChanged: (country) {
                          // We don't need to store country code separately
                        },
                      ),
                    ),
                    
                    _buildBoxField(
                      child: TextField(
                        controller: _passwordController,
                        obscureText: !isPasswordVisible,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: InputDecoration(
                          labelText: 'PIN',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          suffixIcon: IconButton(
                            icon: Icon(
                              isPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.grey[600],
                            ),
                            onPressed: () {
                              setState(() {
                                isPasswordVisible = !isPasswordVisible;
                              });
                            },
                          ),
                        ),
                      ),
                    ),

                    // ✅ "REMEMBER ME" OPTION - MOVED AFTER PIN BOX
                    _buildBoxField(
                      child: Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: (value) => setState(() => _rememberMe = value ?? true),
                          ),
                          const Text('Remember me'),
                          const SizedBox(width: 8),
                          Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                          const Spacer(),
                          GestureDetector(
                            onTap: _clearSavedCredentials,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Clear',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    _isLoading
                        ? const Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Signing in...', style: TextStyle(color: Colors.grey)),
                            ],
                          )
                        : GestureDetector(
                            onTapDown: (_) => setState(() => _isPressed = true),
                            onTapUp: (_) => setState(() => _isPressed = false),
                            onTapCancel: () => setState(() => _isPressed = false),
                            onTap: signIn,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              curve: Curves.easeInOut,
                              height: 50,
                              width: double.infinity,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _isPressed
                                    ? Colors.blue[800]
                                    : Colors.blue[600],
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _isPressed
                                    ? []
                                    : const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          offset: Offset(0, 4),
                                          blurRadius: 6,
                                        ),
                                      ],
                              ),
                              child: const Text(
                                'Sign In',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                    
                    const SizedBox(height: 16),
                    
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/forgot'),
                      child: const Text(
                        "Forgot Password?",
                        style: TextStyle(decoration: TextDecoration.underline),
                      ),
                    ),
                    
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/signup'),
                      child: const Text(
                        "Don't have an account? Sign Up",
                        style: TextStyle(decoration: TextDecoration.underline),
                      ),
                    ),
                    
                    const SizedBox(height: 10),
                    
                    Text(
                      'App Version: $appVersion',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
