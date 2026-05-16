// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/atlas_service.dart';
import '../widgets/orb_painter.dart';
import '../widgets/conversation_drawer.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {

  final AtlasService _atlas  = AtlasService();
  final SpeechToText _stt    = SpeechToText();
  final FlutterTts   _tts    = FlutterTts();
  final Random       _rng    = Random();
  final TextEditingController _textController = TextEditingController();
  final ScrollController      _drawerScroll   = ScrollController();
  final List<ConversationEntry> _conversation  = [];

  // Orb state
  List<Particle> _particles   = [];
  String  _orbState           = 'listening';
  String  _targetOrbState     = 'listening';
  double  _breathPhase        = 0.0;
  Color   _currentColor       = const Color(0xFF3366FF);
  Color   _targetColor        = const Color(0xFF3366FF);
  double  _currentRadius      = 1.0;
  double  _targetRadius       = 1.0;
  int     _targetParticleCount = 400;
  List<(int, int, double)> _beams = [];
  int     _beamCounter        = 0;

  // Animation controllers
  late AnimationController _orbTicker;
  late AnimationController _textFieldSlide;
  late AnimationController _drawerSlide;

  // App state
  bool   _atlasOnline      = false;
  bool   _isListening      = false;
  bool   _isThinking       = false;
  bool   _isSpeaking       = false;
  bool   _alwaysListen     = false;
  bool   _sttReady         = false;
  bool   _showTextField    = false;
  bool   _showDrawer       = false;
  bool   _muted            = false;
  String _statusText       = 'Connecting...';
  String _heardText        = '';
  String _responseText     = '';
  String _finalText        = '';
  String _accumulatedText  = ''; // builds up across restarts (5 second Samsung built-in)
  bool   _holdingButton    = false;

  static const _rotSpeed = 0.002;

  @override
  void initState() {
    super.initState();
    _initParticles(400);

    // Orb animation ticker — 60fps
    _orbTicker = AnimationController(vsync: this, duration: const Duration(days: 999))
      ..addListener(_tickOrb)
      ..forward();

    // Text field slide animation
    _textFieldSlide = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 250));

    // Conversation drawer slide
    _drawerSlide = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));

    _initStt();
    _initTts();
    _checkStatus();
  }

  @override
  void dispose() {
    _orbTicker.dispose();
    _textFieldSlide.dispose();
    _drawerSlide.dispose();
    _textController.dispose();
    _drawerScroll.dispose();
    _tts.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  void _initParticles(int count) {
    _particles = List.generate(count, (_) => Particle.random(_rng));
  }

  Future<void> _initStt() async {
    final ok = await _stt.initialize(
  onError: (e) {
    if (e.errorMsg == 'error_no_match' ||
        e.errorMsg == 'error_speech_timeout' ||
        e.errorMsg == 'error_client') {
      // not real errors — restart if still listening
      if (_isListening && !_isThinking) _startListening();
      return;
    }
    _setStatus('STT: ${e.errorMsg}');
  },
);
    setState(() => _sttReady = ok);
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-GB');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    _tts.setCompletionHandler(() {
      setState(() { _isSpeaking = false; _setOrbState('listening'); });
      if (_alwaysListen) _startListening();
    });
  }

  Future<void> _checkStatus() async {
    final status = await _atlas.getStatus();
    setState(() {
      _atlasOnline = status.isRunning;
      _statusText  = status.isRunning ? 'Ready' : status.state;
    });
    if (!status.isRunning) _setOrbState('error');
  }

  // ---------------------------------------------------------------------------
  // Orb tick — runs every frame
  // ---------------------------------------------------------------------------

  void _tickOrb() {
    if (!mounted) return;
    setState(() {
      // Rotate particles
      final cosA = cos(_rotSpeed);
      final sinA = sin(_rotSpeed);
      for (final p in _particles) { p.rotateY(cosA, sinA); }

      // Breathe
      final cfg = kOrbStates[_orbState] ?? kOrbStates['listening']!;
      _breathPhase += cfg.breathSpeed;
      if (_breathPhase > 2 * pi) _breathPhase -= 2 * pi;

      // Smooth color transition
      _currentColor = Color.lerp(_currentColor, _targetColor, 0.04)!;

      // Smooth radius
      _currentRadius += (_targetRadius - _currentRadius) * 0.03;

      // Particle count transition
      if (_particles.length < _targetParticleCount) {
        final add = min(10, _targetParticleCount - _particles.length);
        _particles.addAll(List.generate(add, (_) => Particle.random(_rng)));
      } else if (_particles.length > _targetParticleCount) {
        _particles.removeRange(_targetParticleCount, _particles.length);
      }

      // Recompute beams every 5 frames
      _beamCounter++;
      if (_beamCounter % 5 == 0) _computeBeams();
    });
  }

  void _setOrbState(String state) {
    if (_orbState == state) return;
    final cfg = kOrbStates[state] ?? kOrbStates['listening']!;
    setState(() {
      _orbState            = state;
      _targetColor         = cfg.color;
      _targetRadius        = cfg.radiusScale;
      _targetParticleCount = cfg.particleCount;
    });
  }

  void _computeBeams() {
    final cfg     = kOrbStates[_orbState] ?? kOrbStates['listening']!;
    final subset  = _particles.take(150).toList();
    final newBeams = <(int, int, double)>[];
    for (int i = 0; i < subset.length; i++) {
      for (int j = i + 1; j < subset.length; j++) {
        final dx = subset[i].x - subset[j].x;
        final dy = subset[i].y - subset[j].y;
        final dz = subset[i].z - subset[j].z;
        final d  = sqrt(dx*dx + dy*dy + dz*dz);
        if (d < cfg.lineMaxDist) {
          final alpha = (1.0 - d / cfg.lineMaxDist) * cfg.lineMaxAlpha;
          newBeams.add((i, j, alpha));
        }
      }
    }
    newBeams.shuffle(_rng);
    _beams = newBeams.take(newBeams.length ~/ 5).toList();
  }

  // ---------------------------------------------------------------------------
  // STT
  // ---------------------------------------------------------------------------

  Future<void> _startListening() async {
  if (!_sttReady || _isThinking || _isSpeaking) return;
  await _tts.stop();
  setState(() {
    _isListening = true;
    _heardText   = '';
    _statusText  = 'Listening...';
  });
  _setOrbState('listening');
  await _listenOnce();
}

Future<void> _listenOnce() async {
  if (!_isListening) return;

  await _stt.listen(
    onResult: (r) {
      setState(() {
        // show accumulated + current chunk
        _heardText = (_accumulatedText + ' ' + r.recognizedWords).trim();
      });
      if (r.finalResult && r.recognizedWords.isNotEmpty) {
        _accumulatedText = (_accumulatedText + ' ' + r.recognizedWords).trim();
      }
    },
    listenFor:      const Duration(seconds: 10),
    pauseFor:       const Duration(seconds: 5),
    partialResults: true,
    cancelOnError:  false,
    listenMode:     ListenMode.dictation,
  );

  // auto-restart if button still held or always-listen active
  if (_isListening && (_holdingButton || _alwaysListen)) {
    await Future.delayed(const Duration(milliseconds: 100));
    await _listenOnce();
  }
}

    await _stt.listen(
      onResult: (r) {
        setState(() => _heardText = r.recognizedWords);
        // only store final results for sending
        if (r.finalResult) _finalText = r.recognizedWords;
      },
      listenFor:      const Duration(seconds: 120), // holds as long as button held
      pauseFor:       const Duration(seconds: 10),  // only auto-stop after 10s silence
      partialResults: true,
      cancelOnError:  false,   // ← don't kill on error_no_match
      listenMode:     ListenMode.dictation, // ← keeps mic open longer
    );

    // Always-listen: auto-submit when speech pauses
    if (_alwaysListen) {
      _stt.statusListener = (status) {
        if (status == 'done' || status == 'notListening') {
          if (_heardText.trim().isNotEmpty) _stopListeningAndSend();
        }
      };
    }
  }

  Future<void> _stopListeningAndSend() async {
    await _stt.stop();
    setState(() => _isListening = false);
    // new — prefer final result, fall back to partial if final is empty
    final text = (_finalText.isNotEmpty ? _finalText : _heardText).trim();
    _finalText = ''; // reset for next command
    if (text.isEmpty) {
      setState(() => _statusText = 'Nothing heard');
      if (_alwaysListen) Future.delayed(const Duration(seconds: 1), _startListening);
      return;
    }
    await _sendCommand(text);
  }

  // ---------------------------------------------------------------------------
  // Command
  // ---------------------------------------------------------------------------

  Future<void> _sendCommand(String text) async {
    _addConversation('you', text);
    setState(() {
      _isThinking  = true;
      _statusText  = 'Thinking...';
      _heardText   = '';
      _responseText = '';
    });
    _setOrbState('thinking');

    final response = await _atlas.sendCommand(text);

    setState(() {
      _isThinking = false;
      _atlasOnline = response.success;
    });

    if (response.success) {
      _addConversation('atlas', response.text);
      _setOrbState('speaking');
      setState(() { _isSpeaking = true; _statusText = 'Speaking...'; });
      setState(() {
      _isThinking  = false;
      _atlasOnline = response.success;
      _responseText = response.text;  
      });
      if (!_muted) {
        await _tts.speak(response.text);
      } else {
        setState(() { _isSpeaking = false; _setOrbState('listening'); });
        if (_alwaysListen) _startListening();
      }
    } else {
      _setOrbState('error');
      setState(() => _statusText = 'Error');
      _addConversation('atlas', response.text);
      Future.delayed(const Duration(seconds: 2), () => _setOrbState('listening'));
    }
  }

  Future<void> _cancel() async {
    await _stt.stop();
    await _tts.stop();
    await _atlas.cancelCommand();
    setState(() {
      _isListening = false;
      _isThinking  = false;
      _isSpeaking  = false;
      _statusText  = 'Cancelled';
      _heardText   = '';
    });
    _setOrbState('listening');
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _statusText = 'Ready');
      if (_alwaysListen) _startListening();
    });
  }

  Future<void> _releaseButton() async {
    _holdingButton = false;
    await _stt.stop();
    setState(() => _isListening = false);

    final text = _accumulatedText.trim();
    _accumulatedText = '';

    if (text.isEmpty) {
      setState(() => _statusText = 'Nothing heard');
      return;
    }
    await _sendCommand(text);
  }

  void _addConversation(String role, String text) {
    setState(() {
      _conversation.add(ConversationEntry(role: role, text: text, time: DateTime.now()));
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_drawerScroll.hasClients) {
        _drawerScroll.animateTo(
          _drawerScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _setStatus(String s) => setState(() => _statusText = s);

  // ---------------------------------------------------------------------------
  // UI toggles
  // ---------------------------------------------------------------------------

  void _toggleTextField() {
    setState(() => _showTextField = !_showTextField);
    if (_showTextField) _textFieldSlide.forward();
    else { _textFieldSlide.reverse(); FocusScope.of(context).unfocus(); }
  }

  void _toggleDrawer() {
    setState(() => _showDrawer = !_showDrawer);
    if (_showDrawer) _drawerSlide.forward();
    else _drawerSlide.reverse();
  }

  void _toggleAlwaysListen() {
    setState(() => _alwaysListen = !_alwaysListen);
    if (_alwaysListen) _startListening();
    else _stt.stop();
  }

  void _toggleMute() => setState(() => _muted = !_muted);

  void _submitText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    _toggleTextField();
    _sendCommand(text);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildStatusBar(),
                Expanded(child: _buildOrb()),
                if (_heardText.isNotEmpty) _buildHeardText(),
                _buildStateLabel(),
                _buildButtons(),
                if (_heardText.isNotEmpty) _buildHeardText(),
                if (_responseText.isNotEmpty) _buildResponseText(),
                if (!_alwaysListen) _buildPushToTalk(),
                const SizedBox(height: 16),
              ],
            ),

            // Conversation drawer — slides up from bottom
            if (_showDrawer) _buildDrawer(),

            // Text field — slides up from bottom
            if (_showTextField) _buildTextField(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0a0a0f),
      title: const Text('A.T.L.A.S.',
        style: TextStyle(color: Color(0xFF1a6aff),
          fontWeight: FontWeight.bold, letterSpacing: 4)),
      actions: [
        // Conversation history
        IconButton(
          icon: Icon(Icons.chat_bubble_outline,
            color: _showDrawer ? const Color(0xFF1a6aff) : const Color(0xFF8a9ab8)),
          tooltip: 'Conversation',
          onPressed: _toggleDrawer,
        ),
        // Always listen toggle
        IconButton(
          icon: Icon(
            _alwaysListen ? Icons.hearing : Icons.hearing_disabled,
            color: _alwaysListen ? const Color(0xFF00cc66) : const Color(0xFF8a9ab8),
          ),
          tooltip: _alwaysListen ? 'Always listen ON' : 'Always listen OFF',
          onPressed: _toggleAlwaysListen,
        ),
        // Mute
        IconButton(
          icon: Icon(_muted ? Icons.volume_off : Icons.volume_up,
            color: _muted ? const Color(0xFFcc2200) : const Color(0xFF8a9ab8)),
          tooltip: _muted ? 'Unmute' : 'Mute TTS',
          onPressed: _toggleMute,
        ),
        // Settings
        IconButton(
          icon: const Icon(Icons.settings, color: Color(0xFF8a9ab8)),
          onPressed: () async {
            await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()));
            _checkStatus();
          },
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color:   const Color(0xFF1a1a2e),
      child: Row(children: [
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _atlasOnline ? const Color(0xFF00cc66) : const Color(0xFFcc2200),
          ),
        ),
        const SizedBox(width: 8),
        Text(_statusText,
          style: const TextStyle(color: Color(0xFF8a9ab8), fontSize: 12)),
        const Spacer(),
        if (_alwaysListen)
          const Text('● LIVE',
            style: TextStyle(color: Color(0xFF00cc66), fontSize: 11,
              fontWeight: FontWeight.bold, letterSpacing: 1)),
        GestureDetector(
          onTap: _checkStatus,
          child: const Icon(Icons.refresh, color: Color(0xFF4a5a6a), size: 14),
        ),
      ]),
    );
  }

  Widget _buildOrb() {
    return Center(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: OrbPainter(
            particles:     _particles,
            state:         _orbState,
            breathPhase:   _breathPhase,
            currentColor:  _currentColor,
            currentRadius: _currentRadius,
            beams:         _beams,
          ),
          size: const Size(280, 280),
        ),
      ),
    );
  }

  Widget _buildHeardText() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Text('"$_heardText"',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF4499ff),
          fontSize: 13, fontStyle: FontStyle.italic)),
    );
  }

  Widget _buildResponseText() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
    child: Text(
      _responseText,
      textAlign: TextAlign.center,
      maxLines:  4,
      overflow:  TextOverflow.ellipsis,
      style: const TextStyle(
        color:    Color(0xFFc8d8e8),
        fontSize: 14,
        height:   1.4,
        ),
      ),
    );
  }

  Widget _buildStateLabel() {
    final labels = {
      'listening': '● Listening ●',
      'thinking':  '● Thinking ●',
      'speaking':  '● Speaking ●',
      'error':     '● Error ●',
      'sleeping':  '● Sleeping ●',
    };
    final colors = {
      'listening': const Color(0xFF3a6aee),
      'thinking':  const Color(0xFF3aee6a),
      'speaking':  const Color(0xFF66ccff),
      'error':     const Color(0xFFee3a3a),
      'sleeping':  const Color(0xFFeec83a),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(labels[_orbState] ?? '',
        style: TextStyle(
          color: colors[_orbState] ?? const Color(0xFF4a5a6a),
          fontSize: 11, letterSpacing: 1)),
    );
  }

  Widget _buildButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        // Cancel
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _cancel,
            icon: const Icon(Icons.stop, size: 16),
            label: const Text('Cancel'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFff6b6b),
              side: const BorderSide(color: Color(0xFF8e2a2a)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Keyboard / text input
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _toggleTextField,
            icon: Icon(_showTextField ? Icons.keyboard_hide : Icons.keyboard, size: 16),
            label: const Text('Type'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8a9ab8),
              side: const BorderSide(color: Color(0xFF2a2a4e)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildPushToTalk() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTapDown: (_) {
        _holdingButton   = true;
        _accumulatedText = '';
        _startListening();
      },
      onTapUp:     (_) => _releaseButton(),
      onTapCancel: ()  => _releaseButton(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _isListening
              ? const Color(0xFF1a3a6e)
              : const Color(0xFF1a1a2e),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isListening
                ? const Color(0xFF1a6aff)
                : const Color(0xFF2a2a4e),
              width: _isListening ? 2 : 1,
            ),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(_isListening ? Icons.mic : Icons.mic_none,
              color: _isListening
                ? const Color(0xFF1a6aff)
                : const Color(0xFF8a9ab8),
              size: 20),
            const SizedBox(width: 8),
            Text(_isListening ? 'Release to send' : 'Hold to speak',
              style: TextStyle(
                color: _isListening
                  ? const Color(0xFF4499ff)
                  : const Color(0xFF4a5a6a),
                fontSize: 14)),
          ]),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _drawerSlide, curve: Curves.easeOut)),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.5,
          decoration: const BoxDecoration(
            color: Color(0xFF0f0f1a),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(top: BorderSide(color: Color(0xFF2a2a4e))),
          ),
          child: Column(children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF2a2a4e),
                borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Conversation',
              style: TextStyle(color: Color(0xFF4a5a6a), fontSize: 12,
                letterSpacing: 1)),
            Expanded(
              child: ConversationDrawer(
                entries: _conversation,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildTextField() {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _textFieldSlide, curve: Curves.easeOut)),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: EdgeInsets.only(
            left: 12, right: 12, top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF0f0f1a),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            border: Border(top: BorderSide(color: Color(0xFF2a2a4e))),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller:    _textController,
                autofocus:     true,
                style:         const TextStyle(color: Color(0xFFc8d8e8)),
                decoration: const InputDecoration(
                  hintText:  'Type a command...',
                  hintStyle: TextStyle(color: Color(0xFF4a5a6a)),
                  filled:    true,
                  fillColor: Color(0xFF1a1a2e),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide:   BorderSide(color: Color(0xFF2a2a4e)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide:   BorderSide(color: Color(0xFF2a2a4e)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide:   BorderSide(color: Color(0xFF1a6aff)),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) => _submitText(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _submitText,
              icon: const Icon(Icons.send, color: Color(0xFF1a6aff)),
            ),
          ]),
        ),
      ),
    );
  }
}
