// lib/main.dart

import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const AtlasApp());
}

class AtlasApp extends StatelessWidget {
  const AtlasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:        'A.T.L.A.S.',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary:   const Color(0xFF1a6aff),
          surface:   const Color(0xFF0a0a0f),
          onSurface: const Color(0xFFc8d8e8),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
