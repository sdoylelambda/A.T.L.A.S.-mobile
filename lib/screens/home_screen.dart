// lib/screens/home_screen.dart
//
// Main Atlas mobile UI.
// Hold mic button to speak → STT → POST /command → TTS speaks response.

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/atlas_service.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {

  final AtlasService _atlas   = AtlasService();
  final SpeechToText _stt     = SpeechToText();
  final FlutterTts   _tts     = FlutterTts();

  // UI state
  String  _statusText   = 'Checking Atlas...';
  String  _responseText = '';
  String  _heardText    = '';
  bool    _isListening  = false;
  bool    _isThinking   = false;
  bool    _atlasOnline  = false;
  bool    _sttReady     = false;

  // Animation for the orb
  late AnimationController _orbController;
  late Animation<double>   _orbAnimation;

  // Atlas state colours — mirrors the desktop orb states
  static const _colSleeping  = Color(0xFF1a1a2e);
  static const _colListening = Color(0xFF1a6aff);
  static const _colThinking  = Color(0xFFffa500);
  static const _colSpeaking  = Color(0xFF00cc66);
  static const _colError     = Color(0xFFcc2200);

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _orbAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _orbController, curve: Curves.easeInOut),
    );
    _initStt();
    _initTts();
    _checkStatus();
  }

  @override
  void dispose() {
    _orbController.dispose();
    _tts.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  Future<void> _initStt() async {
    final available = await _stt.initialize(
      onError: (e) => _setStatus('STT error: ${e.errorMsg}'),
    );
    setState(() => _sttReady = available);
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-GB');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      setState(() => _statusText = 'Ready');
    });
  }

  Future<void> _checkStatus() async {
    final status = await _atlas.getStatus();
    setState(() {
      _atlasOnline  = status.isRunning;
      _statusText   = status.isRunning
          ? 'Atlas online — hold to speak'
          : 'Atlas ${status.state}';
    });
  }

  // ---------------------------------------------------------------------------
  // STT
  // ---------------------------------------------------------------------------

  Future<void> _startListening() async {
    if (!_sttReady || _isThinking) return;
    await _tts.stop();
    setState(() {
      _isListening  = true;
      _heardText    = '';
      _statusText   = 'Listening...';
    });

    await _stt.listen(
      onResult: (result) {
        setState(() => _heardText = result.recognizedWords);
      },
      listenFor:       const Duration(seconds: 30),
      pauseFor:        const Duration(seconds: 3),
      partialResults:  true,
      cancelOnError:   true,
    );
  }

  Future<void> _stopListening() async {
    await _stt.stop();
    setState(() => _isListening = false);

    final text = _heardText.trim();
    if (text.isEmpty) {
      setState(() => _statusText = 'Nothing heard — try again');
      return;
    }
    await _sendCommand(text);
  }

  // ---------------------------------------------------------------------------
  // Command
  // ---------------------------------------------------------------------------

  Future<void> _sendCommand(String text) async {
    setState(() {
      _isThinking   = true;
      _statusText   = 'Thinking...';
      _responseText = '';
    });

    final response = await _atlas.sendCommand(text);

    setState(() {
      _isThinking   = false;
      _responseText = response.text;
      _statusText   = response.success ? 'Speaking...' : 'Error';
      _atlasOnline  = response.success;
    });

    await _speak(response.text);
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  void _setStatus(String msg) => setState(() => _statusText = msg);

  // ---------------------------------------------------------------------------
  // Orb colour
  // ---------------------------------------------------------------------------

  Color get _orbColor {
    if (!_atlasOnline)  return _colError;
    if (_isThinking)    return _colThinking;
    if (_isListening)   return _colListening;
    if (_statusText == 'Speaking...') return _colSpeaking;
    return _colSleeping;
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
          'A.T.L.A.S.',
          style: TextStyle(
            color:       Color(0xFF1a6aff),
            fontWeight:  FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
        actions: [
          IconButton(
            icon:    const Icon(Icons.settings, color: Color(0xFF8a9ab8)),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _checkStatus(); // re-check after returning from settings
            },
          ),
          IconButton(
            icon:    const Icon(Icons.refresh, color: Color(0xFF8a9ab8)),
            tooltip: 'Check status',
            onPressed: _checkStatus,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [

            // Status bar
            Container(
              width:   double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              color:   const Color(0xFF1a1a2e),
              child: Row(
                children: [
                  Container(
                    width:  8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _atlasOnline
                          ? const Color(0xFF00cc66)
                          : const Color(0xFFcc2200),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _statusText,
                    style: const TextStyle(
                      color:    Color(0xFF8a9ab8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            // Orb
            Expanded(
              flex: 3,
              child: Center(
                child: GestureDetector(
                  onTapDown:  (_) => _startListening(),
                  onTapUp:    (_) => _stopListening(),
                  onTapCancel:   () => _stopListening(),
                  child: AnimatedBuilder(
                    animation: _orbAnimation,
                    builder: (_, __) => Transform.scale(
                      scale: _isListening ? _orbAnimation.value : 1.0,
                      child: Container(
                        width:  180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _orbColor.withOpacity(0.15),
                          border: Border.all(
                            color: _orbColor,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:       _orbColor.withOpacity(0.4),
                              blurRadius:  _isListening ? 40 : 20,
                              spreadRadius: _isListening ? 10 : 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          _isThinking
                              ? Icons.psychology
                              : _isListening
                                  ? Icons.mic
                                  : Icons.mic_none,
                          color: _orbColor,
                          size:  64,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Heard text (what STT captured)
            if (_heardText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '"$_heardText"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color:      Color(0xFF4499ff),
                    fontSize:   14,
                    fontStyle:  FontStyle.italic,
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // Response text
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _isThinking
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFffa500),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Text(
                          _responseText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color:    Color(0xFFc8d8e8),
                            fontSize: 16,
                            height:   1.5,
                          ),
                        ),
                      ),
              ),
            ),

            // Hint
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Text(
                _isListening
                    ? 'Release to send'
                    : 'Tap and hold to speak',
                style: const TextStyle(
                  color:    Color(0xFF4a5a6a),
                  fontSize: 13,
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}
