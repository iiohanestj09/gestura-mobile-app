import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/gestura_theme.dart';
import '../features/auth/auth_pages.dart';
import '../features/home/app_shell.dart';
import '../data/firebase_service.dart';
import '../widgets/gestura_widgets.dart';

class GesturaApp extends StatelessWidget {
  const GesturaApp({
    required this.appLinks,
    this.firebaseError,
    super.key,
  });

  final AppLinks appLinks;
  final String? firebaseError;

  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'Gestura',
      debugShowCheckedModeBanner: false,
      theme: GesturaTheme.light,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      home: firebaseError == null
          ? EmailActionLinkHandler(
              appLinks: appLinks,
              child: const AuthGate(),
            )
          : FirebaseSetupPage(error: firebaseError!));
}

final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class EmailActionLinkHandler extends StatefulWidget {
  const EmailActionLinkHandler({
    required this.appLinks,
    required this.child,
    super.key,
  });

  final AppLinks appLinks;
  final Widget child;

  @override
  State<EmailActionLinkHandler> createState() => _EmailActionLinkHandlerState();
}

class _EmailActionLinkHandlerState extends State<EmailActionLinkHandler> {
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _linkSubscription = widget.appLinks.uriLinkStream.listen(
      _handleLink,
      onError: (Object error) {
        appScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Tautan aplikasi gagal dibaca: $error')),
        );
      },
    );
  }

  Future<void> _handleLink(Uri link) async {
    try {
      final handled = await FirebaseService.handleEmailVerificationLink(link);
      if (handled) {
        appScaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Email terverifikasi. Selamat belajar di Gestura!'),
          ),
        );
      }
    } on FirebaseAuthException catch (error) {
      appScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            error.message ?? 'Verifikasi email gagal (${error.code}).',
          ),
        ),
      );
    } on FormatException catch (error) {
      appScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
      stream: FirebaseService.auth.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return FirebaseSetupPage(error: snapshot.error.toString());
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashPage();
        }
        final user = snapshot.data;
        if (user != null && FirebaseService.canAccessApp(user)) {
          return const AppShell(onLogout: FirebaseService.signOut);
        }
        if (user != null) {
          return EmailVerificationPage(email: user.email ?? '');
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
            Text('Gestura',
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
