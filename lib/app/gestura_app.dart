import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/gestura_theme.dart';
import '../features/auth/auth_pages.dart';
import '../features/home/app_shell.dart';
import '../data/firebase_service.dart';
import '../widgets/gestura_widgets.dart';

class GesturaApp extends StatelessWidget {
  const GesturaApp({this.firebaseError, super.key});

  final String? firebaseError;

  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'Gestura',
      debugShowCheckedModeBanner: false,
      theme: GesturaTheme.light,
      home: firebaseError == null
          ? const AuthGate()
          : FirebaseSetupPage(error: firebaseError!));
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
      stream: FirebaseService.auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return FirebaseSetupPage(error: snapshot.error.toString());
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashPage();
        }
        if (snapshot.data != null) {
          return const AppShell(onLogout: FirebaseService.signOut);
        }
        return const WelcomePage();
      });
}

class FirebaseSetupPage extends StatelessWidget {
  const FirebaseSetupPage({required this.error, super.key});

  final String error;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      size: 64, color: GesturaTheme.teal),
                  const SizedBox(height: 18),
                  Text('Firebase belum terhubung',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  const Text(
                    'Ikuti langkah konfigurasi di FIREBASE_SETUP.md, lalu jalankan ulang aplikasi.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(error,
                      style: const TextStyle(color: GesturaTheme.muted),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      );
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
      body: Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF8C6AE8), Color(0xFF49288F)])),
          child: const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            BrandMark(size: 76),
            SizedBox(height: 18),
            Text('gestura',
                style: TextStyle(
                    fontSize: 34,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1)),
            SizedBox(height: 6),
            Text('Belajar bahasa dengan gerakan',
                style: TextStyle(color: Colors.white70))
          ]))));
}
