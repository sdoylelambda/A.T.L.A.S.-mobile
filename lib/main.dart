// lib/main.dart
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'services/atlas_service.dart';
import 'services/ssh_key_manager.dart';

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
      home: const _AppEntry(),
    );
  }
}

class _AppEntry extends StatefulWidget {
  const _AppEntry();
  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final configured = await AtlasService().isConfigured();
    final hasKey     = await SshKeyManager.hasKey();

    if (!mounted) return;

    if (!configured) {
      // not set up at all — go to settings first
      Navigator.pushReplacementNamed(context, '/settings');
      return;
    }

    if (!hasKey) {
      // configured but no SSH key — show setup screen
      await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const SetupScreen()));
    }
    // proceed to home regardless — password fallback handles no-key case
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}


// lib/main.dart

// import 'package:flutter/material.dart';
// import 'screens/home_screen.dart';

// void main() {
//   runApp(const AtlasApp());
// }

// class AtlasApp extends StatelessWidget {
//   const AtlasApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title:        'A.T.L.A.S.',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(
//         colorScheme: ColorScheme.dark(
//           primary:   const Color(0xFF1a6aff),
//           surface:   const Color(0xFF0a0a0f),
//           onSurface: const Color(0xFFc8d8e8),
//         ),
//         useMaterial3: true,
//       ),
//       home: const HomeScreen(),
//     );
//   }
// }
