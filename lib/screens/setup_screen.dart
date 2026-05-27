// lib/screens/setup_screen.dart
//
// Shown on first launch or when no SSH key exists.
// Generates keypair and shows public key as QR code for
// scanning with computer camera to add to authorized_keys.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/ssh_key_manager.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  String? _publicKey;
  bool    _generating = true;
  bool    _copied     = false;

  @override
  void initState() {
    super.initState();
    _generateKey();
  }

  Future<void> _generateKey() async {
    await SshKeyManager.generateAndStore();
    final pubKey = await SshKeyManager.getPublicKeyLine();
    setState(() {
      _publicKey  = pubKey;
      _generating = false;
    });
  }

  void _copy() {
    if (_publicKey == null) return;
    Clipboard.setData(ClipboardData(text: _publicKey!));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2),
        () { if (mounted) setState(() => _copied = false); });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0f),
        title: const Text('One-time Setup',
          style: TextStyle(color: Color(0xFFc8d8e8))),
        iconTheme: const IconThemeData(color: Color(0xFF8a9ab8)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _generating
              ? const Center(child: CircularProgressIndicator(
                  color: Color(0xFF1a6aff)))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // Title
                    const Text('Add SSH Key to Your Computer',
                      style: TextStyle(color: Color(0xFFc8d8e8),
                        fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'This allows Atlas to start automatically without '
                      'a password. Do this once — you\'ll never need to '
                      'type your password again.',
                      style: TextStyle(color: Color(0xFF8a9ab8),
                        fontSize: 13, height: 1.5)),

                    const SizedBox(height: 28),

                    // Step 1 — QR
                    _stepLabel('Step 1', 'Scan this QR code with your computer camera'),
                    const SizedBox(height: 4),
                    const Text(
                      'Or use any QR reader app on your computer.',
                      style: TextStyle(color: Color(0xFF4a5a6a), fontSize: 11)),
                    const SizedBox(height: 16),

                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:        Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data:            _publicKey ?? '',
                          version:         QrVersions.auto,
                          size:            220,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Copy button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _copy,
                        icon: Icon(
                          _copied ? Icons.check : Icons.copy,
                          size: 16,
                          color: _copied
                              ? const Color(0xFF00cc66)
                              : const Color(0xFF8a9ab8)),
                        label: Text(
                          _copied ? 'Copied!' : 'Copy public key',
                          style: TextStyle(
                            color: _copied
                                ? const Color(0xFF00cc66)
                                : const Color(0xFF8a9ab8))),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: _copied
                                ? const Color(0xFF00cc66)
                                : const Color(0xFF2a2a4e)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Step 2 — run on computer
                    _stepLabel('Step 2', 'Run this on your computer'),
                    const SizedBox(height: 8),
                    Container(
                      width:   double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:        const Color(0xFF1a1a2e),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2a2a4e)),
                      ),
                      child: const Text(
                        '# paste the public key into authorized_keys:\n'
                        'mkdir -p ~/.ssh\n'
                        'echo "<paste key here>" >> ~/.ssh/authorized_keys\n'
                        'chmod 600 ~/.ssh/authorized_keys',
                        style: TextStyle(
                          color:      Color(0xFF4499ff),
                          fontSize:   11,
                          fontFamily: 'monospace',
                          height:     1.6,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Step 3 — done
                    _stepLabel('Step 3', 'Tap Done — Atlas will start automatically from now on'),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1a6aff),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Done — I\'ve added the key',
                          style: TextStyle(fontSize: 15,
                            fontWeight: FontWeight.bold)),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Skip — use password instead
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text(
                          'Skip — I\'ll use my password instead',
                          style: TextStyle(color: Color(0xFF4a5a6a),
                            fontSize: 12)),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _stepLabel(String step, String label) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:        const Color(0xFF1a6aff),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(step,
          style: const TextStyle(color: Colors.white, fontSize: 11,
            fontWeight: FontWeight.bold)),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(label,
          style: const TextStyle(color: Color(0xFFc8d8e8), fontSize: 13)),
      ),
    ]);
  }
}
