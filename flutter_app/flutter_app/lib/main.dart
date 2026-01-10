/*import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'signin_page.dart';
import 'home_page.dart';
import 'signup_page.dart';
import 'forgot_password_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Check if user is logged in
  final prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getString('user_id') != null;

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: isLoggedIn ? '/home' : '/signin',
      routes: {
        '/': (context) => SignInPage(),
        '/home': (context) => HomePage(),
        '/signin': (context) => SignInPage(),
        '/signup': (context) => SignUpPage(),
        '/forgot': (context) => ForgotPasswordPage(),
      },
    );
  }
}*/


import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'signin_page.dart';
import 'home_page.dart';
import 'signup_page.dart';
import 'forgot_password_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final prefs = await SharedPreferences.getInstance();
  final String? userId = prefs.getString('user_id');
  final String? lastActiveStr = prefs.getString('last_active');
  bool isLoggedIn = false;

 

  if (userId != null && lastActiveStr != null) {
    final lastActive = DateTime.tryParse(lastActiveStr);
    if (lastActive != null) {
      final diff = DateTime.now().difference(lastActive);
      const idleTimeout = Duration(minutes: 20); // Ensure 2 minutes
      isLoggedIn = diff < idleTimeout;
      print('main.dart: Inactivity duration=$diff, idleTimeout=$idleTimeout, isLoggedIn=$isLoggedIn');
    } else {
      print('main.dart: Invalid last_active format, clearing SharedPreferences');
      await prefs.clear();
      print('main.dart: SharedPreferences after clear: ${prefs.getKeys()}');
    }
  } else {
    print('main.dart: Missing userId or last_active, clearing SharedPreferences');
    await prefs.clear();
    print('main.dart: SharedPreferences after clear: ${prefs.getKeys()}');
  }

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    print('main.dart: Setting initialRoute to ${isLoggedIn ? '/home' : '/signin'}');
    return MaterialApp(
      title: 'Flutter App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: isLoggedIn ? '/home' : '/signin',
      routes: {
        '/signin': (context) => const SignInPage(),
        '/home': (context) => const HomePage(),
        '/signup': (context) => SignUpPage(),
        '/forgot': (context) => ForgotPasswordPage(),
      },
    );
  }
}

/*import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'signin_page.dart';
import 'home_page.dart';
import 'signup_page.dart';
import 'forgot_password_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ============================
  // 1. Initialize Firebase only
  // ============================
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ============================
  // 2. Session logic
  // ============================
  final prefs = await SharedPreferences.getInstance();
  final String? userId = prefs.getString('user_id');
  final String? lastActiveStr = prefs.getString('last_active');

  bool isLoggedIn = false;

  if (userId != null && lastActiveStr != null) {
    final lastActive = DateTime.tryParse(lastActiveStr);

    if (lastActive != null) {
      final diff = DateTime.now().difference(lastActive);
      const idleTimeout = Duration(minutes: 20);

      isLoggedIn = diff < idleTimeout;

      print(
        "main.dart → Session valid? $isLoggedIn   (inactive for: $diff)",
      );
    } else {
      print("main.dart → last_active is corrupted → clearing prefs");
      await prefs.clear();
    }
  } else {
    print("main.dart → No session found → clearing prefs");
    await prefs.clear();
  }

  // ============================
  // 3. Start App
  // ============================
  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    final route = isLoggedIn ? '/home' : '/signin';
    print("main.dart → Opening initial route: $route");

    return MaterialApp(
      title: 'V-APP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      initialRoute: route,
      routes: {
        '/signin': (context) => const SignInPage(),
        '/home': (context) => const HomePage(),
        '/signup': (_) => SignUpPage(),
        '/forgot': (_) => ForgotPasswordPage(),
      },
    );
  }
}*/
