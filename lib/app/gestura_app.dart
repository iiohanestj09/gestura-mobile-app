import 'package:flutter/material.dart';
import '../core/gestura_theme.dart';
import '../features/auth/auth_pages.dart';
import '../widgets/gestura_widgets.dart';

class GesturaApp extends StatelessWidget {
  const GesturaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'Gestura',
      debugShowCheckedModeBanner: false,
      theme: GesturaTheme.light,
      home: const SplashPage());
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const WelcomePage()));
      }
    });
  }

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
