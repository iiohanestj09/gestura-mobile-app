import 'package:flutter/material.dart';

class GesturaTheme {
  static const teal = Color(0xFF7046D8);
  static const tealDark = Color(0xFF45258C);
  static const mint = Color(0xFFEDE6FF);
  static const yellow = Color(0xFFFFC96B);
  static const ink = Color(0xFF251B35);
  static const muted = Color(0xFF80788D);
  static const canvas = Color(0xFFF8F5FC);
  static const border = Color(0xFFEAE4F1);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        fontFamily: 'sans-serif',
        scaffoldBackgroundColor: canvas,
        colorScheme: ColorScheme.fromSeed(
            seedColor: teal, primary: teal, surface: Colors.white),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
              fontFamily: 'sans-serif-rounded',
              fontSize: 28,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: ink,
              letterSpacing: -0.6),
          headlineSmall: TextStyle(
              fontFamily: 'sans-serif-rounded',
              fontSize: 22,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: ink),
          titleLarge: TextStyle(
              fontFamily: 'sans-serif-rounded',
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: ink,
              letterSpacing: -.25),
          titleMedium: TextStyle(
              fontFamily: 'sans-serif-rounded',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ink),
          bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: ink),
          bodyMedium: TextStyle(fontSize: 13, height: 1.45, color: muted),
          labelLarge: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        appBarTheme: const AppBarTheme(
            backgroundColor: canvas,
            surfaceTintColor: Colors.transparent,
            foregroundColor: ink,
            centerTitle: false,
            elevation: 0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: teal, width: 1.6)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
                backgroundColor: teal,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                textStyle:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                elevation: 3,
                shadowColor: teal.withValues(alpha: .22))),
        navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: mint,
            height: 68,
            labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
                fontSize: 11,
                fontWeight: s.contains(WidgetState.selected)
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: s.contains(WidgetState.selected) ? teal : muted))),
      );
}
