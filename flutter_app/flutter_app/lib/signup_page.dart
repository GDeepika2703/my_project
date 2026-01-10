import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key}); // Add const constructor
  @override
  _SignUpPageState createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  
  String _completePhone = '';
  String? _selectedSector;
  List<String> _sectors = [];

  String? _selectedCompany;
  List<String> _companies = [];

  List<Map<String, String>> _regions = [];
  List<String> _selectedRegionIds = [];

  // ✅ Email regex for validation
  final RegExp _emailRegex =
      RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  // ✅ For hiding/showing PIN fields
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;
  bool _isSignUpPressed=false;
  @override
  void initState() {
    super.initState();
    fetchSectors();
  }

  Future<void> fetchSectors() async {
    try {
      final resp =
          await http.get(Uri.parse('http://104.154.141.198:5003/sectors'));
      if (resp.statusCode == 200) {
        final List<dynamic> data = json.decode(resp.body);
        setState(() {
          _sectors = data.map((s) => s['sector_name'].toString()).toList();
        });
      } else {
        _showAlert('Failed to load sectors.');
      }
    } catch (e) {
      _showAlert('Error fetching sectors.');
    }
  }

  Future<void> fetchCompaniesBySector(String sector) async {
    try {
      final resp = await http.get(Uri.parse(
          'http://104.154.141.198:5003/getcompanies?sector=$sector'));
      if (resp.statusCode == 200) {
        final List<dynamic> data = json.decode(resp.body);
        setState(() {
          _companies = data.map((c) => c['company_name'].toString()).toList();
          _selectedCompany = null;
          _regions = [];
          _selectedRegionIds = [];
        });
      } else {
        _showAlert('Failed to load companies.');
      }
    } catch (e) {
      _showAlert('Error fetching companies.');
    }
  }

  Future<void> fetchRegionsByCompany(String company) async {
    try {
      final resp = await http
          .get(Uri.parse('http://104.154.141.198:5003/getregions?company=$company'));
      if (resp.statusCode == 200) {
        final List<dynamic> data = json.decode(resp.body);
        setState(() {
          _regions = data
              .map((r) => {
                    'id': r['region_id'].toString(),
                    'name': r['region_name'].toString(),
                  })
              .toList();
          _selectedRegionIds = [];
          if (_regions.isEmpty) {
            _showAlert('No regions available for this company.');
          }
        });
      } else {
        _showAlert('Failed to load regions.');
      }
    } catch (e) {
      _showAlert('Error fetching regions.');
    }
  }

  Future<void> signUp() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final fullName = "$firstName $lastName".trim();
    final phone = _completePhone;
    final email = _emailController.text.trim();
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    final sectorName = _selectedSector ?? '';
    final companyName = _selectedCompany ?? '';

    if ([firstName, lastName, phone, email, pin, confirmPin, sectorName, companyName]
            .any((e) => e.isEmpty) ||
        _selectedRegionIds.isEmpty) {
      _showAlert('Please fill in all fields and select at least one region.');
      return;
    }

    // ✅ Email validation before submitting
    if (!_emailRegex.hasMatch(email)) {
      _showAlert('Please enter a valid email address.');
      return;
    }

    if (pin != confirmPin) {
      _showAlert('PIN and Confirm PIN do not match.');
      return;
    }

    final url = Uri.parse('http://104.154.141.198:5003/register');
    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': fullName,
          'phone_no': phone,
          'email': email,
          'password': pin,
          'sector_name': sectorName,
          'company_name': companyName,
          'region_ids': _selectedRegionIds,
        }),
      );

      final data = json.decode(resp.body);
      if (resp.statusCode == 201 && data['status'] == 'success') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('name', data['name']);
        await prefs.setString('user_id', data['user_id'].toString());
        await prefs.setString('company_name', data['company_name']);

        _showAlert('User successfully registered. You will get access once verified.',
            onOk: () {
          Navigator.pushReplacementNamed(context, '/');
        });
      } else {
        _showAlert(data['message'] ?? 'Registration failed.');
      }
    } catch (e) {
      _showAlert('Error during registration.');
    }
  }

  void _showAlert(String msg, {VoidCallback? onOk}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (onOk != null) onOk();
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  // ✅ updated to allow optional inputFormatters
  Widget _buildBoxField(TextEditingController ctl, String label,
      {TextInputType type = TextInputType.text,
       List<TextInputFormatter>? inputFormatters}) {
    return TextField(
      controller: ctl,
      keyboardType: type,
      inputFormatters: inputFormatters,
      style: TextStyle(color: Colors.black),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  // ✅ Updated PIN field with eye icon
  Widget _buildPinField(TextEditingController ctl, String label,
      {required bool obscureText, required VoidCallback toggleVisibility}) {
    return TextField(
      controller: ctl,
      obscureText: obscureText,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      style: TextStyle(color: Colors.black),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
        suffixIcon: IconButton(
          icon: Icon(
            obscureText ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: toggleVisibility,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext ctx) {
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
              constraints: BoxConstraints(maxWidth: 380),
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
                  children: [
                    Text("Registration",
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    SizedBox(height: 20),
                    _buildBoxField(_firstNameController, 'First Name'),
                    SizedBox(height: 10),
                    _buildBoxField(_lastNameController, 'Last Name'),
                    SizedBox(height: 10),
                    IntlPhoneField(
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      initialCountryCode: 'IN',
                      onChanged: (phone) {
                        setState(() {
                          _completePhone = phone.completeNumber;
                        });
                      },
                    ),
                    SizedBox(height: 10),
                    _buildBoxField(
                      _emailController,
                      'Email',
                      type: TextInputType.emailAddress,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r"\s")),
                      ],
                    ),
                    SizedBox(height: 10),
                    // ✅ PIN field with eye icon
                    _buildPinField(
                      _pinController,
                      'PIN (Only 4-Digits)',
                      obscureText: _obscurePin,
                      toggleVisibility: () {
                        setState(() {
                          _obscurePin = !_obscurePin;
                        });
                      },
                    ),
                    SizedBox(height: 10),
                    // ✅ Confirm PIN field with eye icon
                    _buildPinField(
                      _confirmPinController,
                      'Confirm PIN',
                      obscureText: _obscureConfirmPin,
                      toggleVisibility: () {
                        setState(() {
                          _obscureConfirmPin = !_obscureConfirmPin;
                        });
                      },
                    ),
                    SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _selectedSector,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: "Select Sector",
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: _sectors.map((s) {
                        return DropdownMenuItem(value: s, child: Text(s));
                      }).toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedSector = v;
                          _companies = [];
                          _selectedCompany = null;
                          _regions = [];
                          _selectedRegionIds = [];
                        });
                        if (v != null) fetchCompaniesBySector(v);
                      },
                    ),
                    SizedBox(height: 10),
                    if (_companies.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: _selectedCompany,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: "Select Company",
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: _companies.map((c) {
                          return DropdownMenuItem(value: c, child: Text(c));
                        }).toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedCompany = v;
                            _regions = [];
                            _selectedRegionIds = [];
                          });
                          if (v != null) fetchRegionsByCompany(v);
                        },
                      ),
                    SizedBox(height: 10),
                    if (_regions.isNotEmpty)
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              title: Text('Select All'),
                              value: _selectedRegionIds.length == _regions.length &&
                                  _regions.isNotEmpty,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedRegionIds =
                                        _regions.map((r) => r['id']!).toList();
                                  } else {
                                    _selectedRegionIds.clear();
                                  }
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            ..._regions.map((region) {
                              return CheckboxListTile(
                                title: Text(region['name']!),
                                value: _selectedRegionIds.contains(region['id']),
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedRegionIds.add(region['id']!);
                                    } else {
                                      _selectedRegionIds.remove(region['id']);
                                    }
                                  });
                                },
                                controlAffinity: ListTileControlAffinity.leading,
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    SizedBox(height: 20),
                    GestureDetector(
                      onTapDown: (_) {
                        setState(() {
                          _isSignUpPressed = true;
                        });
                      },
                      onTapUp: (_) {
                        setState(() {
                          _isSignUpPressed = false;
                        });
                        signUp(); // Trigger your existing signup logic
                      },
                      onTapCancel: () {
                        setState(() {
                          _isSignUpPressed = false;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeInOut,
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          color: _isSignUpPressed ? Colors.blue[800] : Colors.blue[600],
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            if (!_isSignUpPressed)
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 6,
                                offset: Offset(0, 3),
                              ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Sign Up',
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
                      onPressed: () =>
                          Navigator.pushReplacementNamed(context, '/signin'),
                      child: Text(
                        "Already registered? Sign In",
                        style: TextStyle(decoration: TextDecoration.underline),
                      ),
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
