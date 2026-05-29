// lib/screens/setup_screen.dart
//
// Shown on first launch when no SSH key exists.
// Generates ed25519 keypair, installs it on computer automatically
// via SSH password auth (one time). After this, every launch requires
// password + key auth together (two factors).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dartssh2/dartssh2.dart';
import '../services/atlas_service.dart';
import '../services/ssh_key_manager.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _passwordController = TextEditingController();

  String? _publicKey;
  bool    _generating   = true;
  bool    _installing   = false;
  bool    _installed    = false;
  bool    _obscurePass  = true;
  String? _installError;

  @override
  void initState() {
    super.initState();
    _generateKey();
  }

  @override
  void dispose() {
    _passwordController.clear();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _generateKey() async {
    if (!await SshKeyManager.hasKey()) {
      await SshKeyManager.generateAndStore();
    }
    final pubKey = await SshKeyManager.getPublicKeyLine();
    setState(() {
      _publicKey  = pubKey;
      _generating = false;
    });
  }

  Future<void> _installKey() async {
    if (_publicKey == null) return;
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _installError = 'Please enter your computer password.');
      return;
    }

    setState(() { _installing = true; _installError = null; });

    SSHSocket? socket;
    SSHClient? client;

    try {
      final atlas = AtlasService();
      final host  = await atlas.getSshHost();
      final user  = await atlas.getSshUser();

      if (host == null || host.isEmpty || user == null || user.isEmpty) {
        setState(() {
          _installing   = false;
          _installError = 'SSH host/username not set. Go to Settings first.';
        });
        return;
      }

      socket = await SSHSocket.connect(
        host, 22, timeout: const Duration(seconds: 15));

      final storedFp = await atlas.getSshFingerprint();

      client = SSHClient(
        socket,
        username:          user,
        onPasswordRequest: () => password,
        onVerifyHostKey: (hostKey, fingerprint) async {
          final fp = base64.encode(fingerprint);
          if (storedFp == null || storedFp.isEmpty) {
            await const FlutterSecureStorage().write(
              key: 'atlas_ssh_fingerprint', value: fp);
            return true;
          }
          return fp == storedFp;
        },
      );

      await client.authenticated;

      // install public key — idempotent (won't add duplicates)
      final escapedKey = _publicKey!.replaceAll("'", "'\\''");
      final session = await client.execute(
        "mkdir -p ~/.ssh && "
        "chmod 700 ~/.ssh && "
        "grep -qF '$escapedKey' ~/.ssh/authorized_keys 2>/dev/null || "
        "echo '$escapedKey' >> ~/.ssh/authorized_keys && "
        "chmod 600 ~/.ssh/authorized_keys",
      );
      await session.stdout.drain();
      await session.done;

      setState(() { _installing = false; _installed = true; });

    } on SSHAuthFailError {
      setState(() {
        _installing   = false;
        _installError = 'Incorrect password. Try again.';
      });
    } catch (e) {
      setState(() {
        _installing   = false;
        _installError = 'Could not connect. Check Settings and try again.';
      });
    } finally {
      _passwordController.clear(); // remove password from controller
      client?.close();
      socket?.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0f),
        title: const Text('One-time SSH Setup',
          style: TextStyle(color: Color(0xFFc8d8e8))),
        iconTheme: const IconThemeData(color: Color(0xFF8a9ab8)),
        automaticallyImplyLeading: false, // no back button — must complete
      ),
      body: SafeArea(
        child: _generating
          ? const Center(child: CircularProgressIndicator(
              color: Color(0xFF1a6aff)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // header
                  const Text('SSH Key Setup',
                    style: TextStyle(color: Color(0xFFc8d8e8),
                      fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'This installs a secure key on your computer. '
                    'You\'ll still enter your password every time you '
                    'open the app — but the key adds a second layer of '
                    'security. One time setup only.',
                    style: TextStyle(color: Color(0xFF8a9ab8),
                      fontSize: 13, height: 1.5)),

                  const SizedBox(height: 28),

                  // step 1 — key generated
                  _stepLabel('Step 1',
                    'SSH key generated on your phone',
                    done: true),
                  const SizedBox(height: 8),
                  Container(
                    width:   double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:        const Color(0xFF1a1a2e),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2a2a4e)),
                    ),
                    child: SelectableText(
                      _publicKey ?? '',
                      style: const TextStyle(
                        color:      Color(0xFF4499ff),
                        fontSize:   10,
                        fontFamily: 'monospace',
                        height:     1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Stored securely in Android Keystore — never leaves your device.',
                    style: TextStyle(color: Color(0xFF4a5a6a),
                      fontSize: 11, height: 1.4)),

                  const SizedBox(height: 28),

                  // step 2 — enter password to install
                  _stepLabel('Step 2',
                    'Enter your computer password to install the key',
                    done: _installed),
                  const SizedBox(height: 12),

                  if (!_installed) ...[
                    TextField(
                      controller:  _passwordController,
                      obscureText: _obscurePass,
                      style:       const TextStyle(color: Color(0xFFc8d8e8)),
                      decoration: InputDecoration(
                        hintText:  'Linux password',
                        hintStyle: const TextStyle(color: Color(0xFF4a5a6a)),
                        filled:    true,
                        fillColor: const Color(0xFF1a1a2e),
                        border: const OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF2a2a4e))),
                        enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF2a2a4e))),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF1a6aff))),
                        prefixIcon: const Icon(Icons.lock,
                          color: Color(0xFF8a9ab8)),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePass
                              ? Icons.visibility
                              : Icons.visibility_off,
                            color: const Color(0xFF8a9ab8)),
                          onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                        ),
                      ),
                      onSubmitted: (_) => _installKey(),
                    ),

                    const SizedBox(height: 8),
                    const Text(
                      'Used once to install the key. Never stored.',
                      style: TextStyle(color: Color(0xFF4a5a6a),
                        fontSize: 11)),

                    const SizedBox(height: 16),

                    if (_installError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          width:   double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color:        const Color(0xFF2a0a0a),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFcc2200)),
                          ),
                          child: Text(_installError!,
                            style: const TextStyle(
                              color: Color(0xFFff6b6b),
                              fontSize: 12)),
                        ),
                      ),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _installing ? null : _installKey,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1a6aff),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                          disabledBackgroundColor:
                            const Color(0xFF1a2a4e),
                        ),
                        child: _installing
                          ? const SizedBox(height: 20, width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                          : const Text('Install Key on Computer',
                              style: TextStyle(fontSize: 15,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),

                  ] else ...[
                    // installed success
                    Container(
                      width:   double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color:        const Color(0xFF0a2a1a),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00cc66)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.check_circle,
                          color: Color(0xFF00cc66), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Key installed successfully.',
                            style: TextStyle(color: Color(0xFF00cc66),
                              fontSize: 13, height: 1.4)),
                        ),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // step 3 — how it works going forward
                  _stepLabel('Step 3',
                    'Every launch: enter password to start Atlas',
                    done: _installed),
                  const SizedBox(height: 8),
                  const Text(
                    'Your password + SSH key together provide two-factor '
                    'security. Even if someone has your phone, they cannot '
                    'access Atlas without your computer password.',
                    style: TextStyle(color: Color(0xFF8a9ab8),
                      fontSize: 13, height: 1.5)),

                  const SizedBox(height: 28),

                  // continue button — only enabled after install
                  if (_installed)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00cc66),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Continue to Atlas',
                          style: TextStyle(fontSize: 15,
                            fontWeight: FontWeight.bold)),
                      ),
                    ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
      ),
    );
  }

  Widget _stepLabel(String step, String label, {bool done = false}) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:        done
            ? const Color(0xFF00cc66)
            : const Color(0xFF1a6aff),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(step,
          style: const TextStyle(color: Colors.white,
            fontSize: 11, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(label,
          style: TextStyle(
            color: done
              ? const Color(0xFF00cc66)
              : const Color(0xFFc8d8e8),
            fontSize: 13)),
      ),
      if (done)
        const Icon(Icons.check, color: Color(0xFF00cc66), size: 16),
    ]);
  }
}
