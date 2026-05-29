// lib/screens/settings_screen.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/atlas_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AtlasService _atlas = AtlasService();

  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  final _sshHostController = TextEditingController();
  final _sshUserController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    _sshHostController.dispose();
    _sshUserController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Load
  // ---------------------------------------------------------------------------

  Future<void> _loadSettings() async {
    final url = await _atlas.getServerUrl();
    final key = await _atlas.getApiKey();
    final sshHost = await _atlas.getSshHost();
    final sshUser = await _atlas.getSshUser();

    if (!mounted) return;

    setState(() {
      _urlController.text = url ?? '';
      _keyController.text = key ?? '';
      _sshHostController.text = sshHost ?? '';
      _sshUserController.text = sshUser ?? '';
    });
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    await _atlas.saveSettings(
      serverUrl: _urlController.text.trim(),
      apiKey: _keyController.text.trim(),
      sshHost: _sshHostController.text.trim(),
      sshUser: _sshUserController.text.trim(),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved'),
        backgroundColor: Color(0xFF1a6aff),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Clear
  // ---------------------------------------------------------------------------

  Future<void> _clearSettings() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text(
          'Reset credentials?',
          style: TextStyle(color: Color(0xFFc8d8e8)),
        ),
        content: const Text(
          'This will delete all saved Atlas credentials from this device.',
          style: TextStyle(color: Color(0xFF8a9ab8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF8a9ab8)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Reset',
              style: TextStyle(color: Color(0xFFcc2200)),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _atlas.clearSettings();

    setState(() {
      _urlController.clear();
      _keyController.clear();
      _sshHostController.clear();
      _sshUserController.clear();
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Credentials cleared'),
        backgroundColor: Color(0xFFcc2200),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // QR Scanner
  // ---------------------------------------------------------------------------

  Future<void> _scanQrCode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );

    if (result == null || result.isEmpty) return;

    try {
      final data = jsonDecode(result);

      if (data is Map) {
        if (data.containsKey('server')) {
          _urlController.text = data['server'];
        }

        if (data.containsKey('apikey')) {
          _keyController.text = data['apikey'];
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Server URL + API key scanned — tap Save to confirm',
              ),
              backgroundColor: Color(0xFF00cc66),
              duration: Duration(seconds: 3),
            ),
          );
        }

        setState(() {});
        return;
      }
    } catch (_) {}

    setState(() {
      _keyController.text = result;
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('API key scanned — tap Save to confirm'),
        backgroundColor: Color(0xFF00cc66),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0f),
        title: const Text(
          'Settings',
          style: TextStyle(color: Color(0xFFc8d8e8)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF8a9ab8)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('CONNECTION'),

                const SizedBox(height: 12),

                TextFormField(
                  controller: _urlController,
                  style: const TextStyle(color: Color(0xFFc8d8e8)),
                  keyboardType: TextInputType.url,
                  decoration: _inputDecoration(
                    label: 'Server URL',
                    hint: 'http://100.x.x.x:8000',
                    icon: Icons.dns,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Required';
                    }

                    final uri = Uri.tryParse(v.trim());

                    if (uri == null ||
                        !uri.hasScheme ||
                        uri.host.isEmpty) {
                      return 'Enter a valid URL';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 20),

                TextFormField(
                  controller: _sshHostController,
                  style: const TextStyle(color: Color(0xFFc8d8e8)),
                  decoration: _inputDecoration(
                    label: 'SSH Host',
                    hint: '100.x.x.x',
                    icon: Icons.computer,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Required';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                TextFormField(
                  controller: _sshUserController,
                  style: const TextStyle(color: Color(0xFFc8d8e8)),
                  decoration: _inputDecoration(
                    label: 'SSH Username',
                    hint: 'sean',
                    icon: Icons.person,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Required';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _keyController,
                        obscureText: _obscureKey,
                        style: const TextStyle(color: Color(0xFFc8d8e8)),
                        decoration: _inputDecoration(
                          label: 'API Key',
                          hint: 'Paste or scan QR code',
                          icon: Icons.key,
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureKey
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: const Color(0xFF8a9ab8),
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureKey = !_obscureKey;
                              });
                            },
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Required';
                          }

                          if (v.trim().length < 16) {
                            return 'Key seems too short';
                          }

                          return null;
                        },
                      ),
                    ),

                    const SizedBox(width: 10),

                    Tooltip(
                      message: 'Scan QR code',
                      child: InkWell(
                        onTap: _scanQrCode,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 58,
                          width: 58,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1a1a2e),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF2a2a4e),
                            ),
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner,
                            color: Color(0xFF1a6aff),
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                const Text(
                  'Generate QR on your computer:\n'
                  'python3 ~/dev/A.T.L.A.S./api/gen_qr.py',
                  style: TextStyle(
                    color: Color(0xFF4a5a6a),
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1a6aff),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                _sectionLabel(
                  'DANGER ZONE',
                  color: const Color(0xFFcc2200),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _clearSettings,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFcc2200),
                      side: const BorderSide(
                        color: Color(0xFFcc2200),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Reset credentials'),
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await _atlas.resetSshFingerprint();

                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'SSH fingerprint reset — next connection will re-verify',
                          ),
                          backgroundColor: Color(0xFFffa500),
                        ),
                      );
                    },
                    icon: const Icon(Icons.security, size: 16),
                    label: const Text('Reset SSH fingerprint'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFffa500),
                      side: const BorderSide(
                        color: Color(0xFFffa500),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _sectionLabel(
    String text, {
    Color color = const Color(0xFF1a6aff),
  }) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Color(0xFF8a9ab8)),
      hintStyle: const TextStyle(color: Color(0xFF4a5a6a)),
      prefixIcon: Icon(
        icon,
        color: const Color(0xFF8a9ab8),
      ),
      filled: true,
      fillColor: const Color(0xFF1a1a2e),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: Color(0xFF2a2a4e),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: Color(0xFF1a6aff),
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: Color(0xFFcc2200),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QR Scan Screen
// ---------------------------------------------------------------------------

class _QrScanScreen extends StatefulWidget {
  const _QrScanScreen();

  @override
  State<_QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<_QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();

  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;

    final value = capture.barcodes.firstOrNull?.rawValue;

    if (value != null && value.isNotEmpty) {
      _scanned = true;
      _controller.stop();

      Navigator.pop(context, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0f),
        title: const Text(
          'Scan API Key QR',
          style: TextStyle(color: Color(0xFFc8d8e8)),
        ),
        iconTheme: const IconThemeData(
          color: Color(0xFF8a9ab8),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF1a6aff),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Text(
              'Point at the QR code on your computer screen',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFc8d8e8),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
