// lib/screens/settings_screen.dart
//
// Settings screen for Atlas server URL and API key.
// Stored securely via flutter_secure_storage — never in plaintext.

import 'package:flutter/material.dart';
import '../services/atlas_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AtlasService _atlas = AtlasService();
  final _urlController      = TextEditingController();
  final _keyController      = TextEditingController();
  final _formKey            = GlobalKey<FormState>();

  bool _obscureKey = true;
  bool _saved      = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final url = await _atlas.getServerUrl();
    final key = await _atlas.getApiKey();
    setState(() {
      _urlController.text = url ?? '';
      _keyController.text = key ?? '';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await _atlas.saveSettings(
      serverUrl: _urlController.text.trim(),
      apiKey:    _keyController.text.trim(),
    );
    setState(() => _saved = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:         Text('Settings saved'),
          backgroundColor: Color(0xFF1a6aff),
          duration:        Duration(seconds: 2),
        ),
      );
    }
  }


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
          'This will delete your saved server URL and API key from this device.',
          style: TextStyle(color: Color(0xFF8a9ab8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8a9ab8))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(color: Color(0xFFcc2200))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _atlas.clearSettings();
    setState(() {
      _urlController.text = '';
      _keyController.text = '';
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:         Text('Credentials cleared'),
          backgroundColor: Color(0xFFcc2200),
          duration:        Duration(seconds: 2),
        ),
      );
    }
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                const Text(
                  'Atlas Server',
                  style: TextStyle(
                    color:      Color(0xFF1a6aff),
                    fontSize:   13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),

                // Server URL
                TextFormField(
                  controller:  _urlController,
                  style:       const TextStyle(color: Color(0xFFc8d8e8)),
                  decoration:  _inputDecoration(
                    label: 'Server URL',
                    hint:  'http://100.x.x.x:8000',
                    icon:  Icons.dns,
                  ),
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!v.startsWith('http')) return 'Must start with http:// or https://';
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // API Key
                TextFormField(
                  controller:    _keyController,
                  obscureText:   _obscureKey,
                  style:         const TextStyle(color: Color(0xFFc8d8e8)),
                  decoration:    _inputDecoration(
                    label: 'API Key',
                    hint:  'Your Atlas API key',
                    icon:  Icons.key,
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureKey ? Icons.visibility : Icons.visibility_off,
                        color: const Color(0xFF8a9ab8),
                      ),
                      onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (v.trim().length < 16) return 'Key seems too short';
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1a6aff),
                      foregroundColor: Colors.white,
                      padding:         const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        fontSize:   16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Help text
                const Text(
                  'Server URL: your Tailscale IP and port\n'
                  'e.g. http://100.64.0.1:8000\n\n'
                  'API Key: the key stored in\n'
                  '~/.config/atlas/api_key on your computer',
                  style: TextStyle(
                    color:    Color(0xFF4a5a6a),
                    fontSize: 12,
                    height:   1.6,
                  ),
                ),


                const SizedBox(height: 32),

                // Danger zone
                const Text(
                  'DANGER ZONE',
                  style: TextStyle(
                    color:         Color(0xFFcc2200),
                    fontSize:      11,
                    fontWeight:    FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _clearSettings,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFcc2200),
                      side:    const BorderSide(color: Color(0xFFcc2200)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape:   RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Reset credentials'),
                  ),
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText:     label,
      hintText:      hint,
      labelStyle:    const TextStyle(color: Color(0xFF8a9ab8)),
      hintStyle:     const TextStyle(color: Color(0xFF4a5a6a)),
      prefixIcon:    Icon(icon, color: const Color(0xFF8a9ab8)),
      filled:        true,
      fillColor:     const Color(0xFF1a1a2e),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:   const BorderSide(color: Color(0xFF2a2a4e)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:   const BorderSide(color: Color(0xFF2a2a4e)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:   const BorderSide(color: Color(0xFF1a6aff)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:   const BorderSide(color: Color(0xFFcc2200)),
      ),
    );
  }
}
