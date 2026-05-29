// lib/services/atlas_service.dart
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dartssh2/dartssh2.dart';
import 'ssh_key_manager.dart';

class AtlasService {
  static const _storage = FlutterSecureStorage();

  static const _keyApiKey         = 'atlas_api_key';
  static const _keyServerUrl      = 'atlas_server_url';
  static const _keySshHost        = 'atlas_ssh_host';
  static const _keySshUser        = 'atlas_ssh_user';
  static const _keySshFingerprint = 'atlas_ssh_fingerprint';

  // ---------------------------------------------------------------------------
  // Config
  // ---------------------------------------------------------------------------

  Future<String?> getServerUrl()      async => _storage.read(key: _keyServerUrl);
  Future<String?> getApiKey()         async => _storage.read(key: _keyApiKey);
  Future<String?> getSshHost()        async => _storage.read(key: _keySshHost);
  Future<String?> getSshUser()        async => _storage.read(key: _keySshUser);
  Future<String?> getSshFingerprint() async => _storage.read(key: _keySshFingerprint);

  Future<void> saveSettings({
    required String serverUrl,
    required String apiKey,
    required String sshHost,
    required String sshUser,
  }) async {
    // proper URL validation
    final uri = Uri.tryParse(serverUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError('Invalid server URL');
    }
    await _storage.write(key: _keyServerUrl, value: serverUrl.trim());
    await _storage.write(key: _keyApiKey,    value: apiKey.trim());
    await _storage.write(key: _keySshHost,   value: sshHost.trim());
    await _storage.write(key: _keySshUser,   value: sshUser.trim());
  }

  Future<bool> isConfigured() async {
    final url  = await getServerUrl();
    final key  = await getApiKey();
    final host = await getSshHost();
    final user = await getSshUser();
    return url  != null && url.isNotEmpty  &&
           key  != null && key.isNotEmpty  &&
           host != null && host.isNotEmpty &&
           user != null && user.isNotEmpty;
  }

  // delete only known keys — never deleteAll
  Future<void> clearSettings() async {
    for (final k in [
      _keyApiKey, _keyServerUrl,
      _keySshHost, _keySshUser, _keySshFingerprint,
    ]) { await _storage.delete(key: k); }
    await SshKeyManager.deleteKeys();
  }

  Future<void> resetSshFingerprint() async =>
      _storage.delete(key: _keySshFingerprint);

  // ---------------------------------------------------------------------------
  // SSH — key auth primary, password fallback
  // ---------------------------------------------------------------------------

  /// Try SSH key auth first (silent). Falls back to password if key fails.
  /// [password] is only used if key auth fails. May be null if caller
  /// wants key-only (will return error string if key auth fails).
  Future<String?> wakeViaSSH({String? password}) async {
    final host = await getSshHost();
    final user = await getSshUser();

    if (host == null || user == null || host.isEmpty || user.isEmpty) {
      return 'SSH host and username not configured. Check Settings.';
    }

    // ensure we have a key — generate if missing
    if (!await SshKeyManager.hasKey()) {
      dev.log('[SSH] No key found, generating...');
      await SshKeyManager.generateAndStore();
    }

    // try key auth first
    final keyError = await _sshConnect(
      host: host, user: user, useKey: true, password: null);

    if (keyError == null) return null; // key auth succeeded

    dev.log('[SSH] Key auth failed: $keyError — trying password');

    // key auth failed — try password if provided
    if (password != null && password.isNotEmpty) {
      return await _sshConnect(
        host: host, user: user, useKey: false, password: password);
    }

    // no password provided and key failed
    return 'key_auth_failed'; // caller should ask for password
  }

  Future<String?> _sshConnect({
    required String  host,
    required String  user,
    required bool    useKey,
    required String? password,
  }) async {
    SSHSocket? socket;
    SSHClient? client;

    try {
      socket = await SSHSocket.connect(
        host, 22, timeout: const Duration(seconds: 15));

      final storedFp = await getSshFingerprint();

      // build identities list if using key auth
      List<SSHKeyPair> identities = [];
      if (useKey) {
        final pem = await SshKeyManager.getPrivatePem();
        if (pem != null) {
          identities = SSHKeyPair.fromPem(pem);
        }
      }

      client = SSHClient(
        socket,
        username:   user,
        identities: identities,
        // only provide password callback for password auth
        onPasswordRequest: (!useKey && password != null)
            ? () => password
            : null,

        // host key verification — TOFU
        onVerifyHostKey: (hostKey, fingerprint) async {
          final fp = base64.encode(fingerprint);
          if (storedFp == null || storedFp.isEmpty) {
            await _storage.write(key: _keySshFingerprint, value: fp);
            dev.log('[SSH] Host fingerprint stored');
            return true;
          }
          if (fp == storedFp) return true;
          dev.log('[SSH] WARNING: Host fingerprint mismatch!');
          return false; // reject — possible MITM
        },
      );

      await client.authenticated;

      // Change path to var in config
      final session = await client.execute(
        'cd /home/zero/dev/A.T.L.A.S. && '
        'if ! pgrep -f "uvicorn api.fastapi_server:app" > /dev/null; then '
        '  mkdir -p /home/zero/.atlas/logs && '
        '  TSHIP=\$(tailscale ip -4 | head -n1) && '
        '  echo "IP: \$TSHIP" >> /home/zero/.atlas/logs/fastapi.log && '
        '  /home/zero/dev/A.T.L.A.S./.venv/bin/uvicorn api.fastapi_server:app '
        '    --host \$TSHIP '
        '    --port 8000 '
        '  >> /home/zero/.atlas/logs/fastapi.log 2>&1 & '
        'fi',
      );

      // drain silently — no logging of output (#9)
      await session.stdout.drain();
      await session.done;

      return null; // success

    } on SSHAuthFailError {
      return useKey ? 'key_auth_failed' : 'Incorrect password.';
    } catch (e) {
      dev.log('[SSH] Error: $e'); // dev log only
      return 'Could not connect to Atlas.'; // generic to user
    } finally {
      client?.close();
      socket?.destroy();
    }
  }

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  Future<AtlasStatus> getStatus() async {
    final url = await getServerUrl();
    if (url == null || url.isEmpty) {
      return AtlasStatus(isRunning: false, state: 'not configured');
    }
    try {
      final response = await http
          .get(Uri.parse('$url/status'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AtlasStatus(
          isRunning: data['atlas_running'] ?? false,
          state:     data['state'] ?? 'unknown',
        );
      }
      return AtlasStatus(isRunning: false, state: 'error');
    } catch (_) {
      return AtlasStatus(isRunning: false, state: 'unreachable');
    }
  }

  // ---------------------------------------------------------------------------
  // Command
  // ---------------------------------------------------------------------------

  Future<AtlasResponse> sendCommand(String text) async {
    final url    = await getServerUrl();
    final apiKey = await getApiKey();
    if (url == null || url.isEmpty) {
      return AtlasResponse.error('No server URL. Go to Settings.');
    }
    if (apiKey == null || apiKey.isEmpty) {
      return AtlasResponse.error('No API key. Go to Settings.');
    }
    try {
      final response = await http.post(
        Uri.parse('$url/command'),
        headers: {'Content-Type': 'application/json', 'X-API-Key': apiKey},
        body: jsonEncode({'text': text}),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AtlasResponse(
          text:    data['response'] ?? 'No response.',
          state:   data['state']    ?? 'listening',
          success: true,
        );
      } else if (response.statusCode == 401) {
        return AtlasResponse.error('Invalid API key. Check Settings.');
      } else if (response.statusCode == 429) {
        return AtlasResponse.error('Too many requests. Please wait.');
      }
      return AtlasResponse.error('Could not reach Atlas.');
    } catch (_) {
      return AtlasResponse.error('Could not reach Atlas.');
    }
  }

  // ---------------------------------------------------------------------------
  // Cancel
  // ---------------------------------------------------------------------------

  Future<void> cancelCommand() async {
    final url    = await getServerUrl();
    final apiKey = await getApiKey();
    if (url == null || apiKey == null) return;
    try {
      await http.post(Uri.parse('$url/cancel'),
        headers: {'X-API-Key': apiKey},
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class AtlasStatus {
  final bool isRunning; final String state;
  const AtlasStatus({required this.isRunning, required this.state});
}

class AtlasResponse {
  final String text; final String state; final bool success;
  const AtlasResponse({required this.text, required this.state, required this.success});
  factory AtlasResponse.error(String m) =>
      AtlasResponse(text: m, state: 'error', success: false);
}


// // lib/services/atlas_service.dart
// //
// // HTTP client for the Atlas FastAPI server.
// // Handles /command and /status endpoints.
// // Both API key and server URL stored in flutter_secure_storage.
// // Nothing sensitive is hardcoded or committed to git.

// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// class AtlasService {
//   static const _storage      = FlutterSecureStorage();
//   static const _keyApiKey    = 'atlas_api_key';
//   static const _keyServerUrl = 'atlas_server_url';

//   // ---------------------------------------------------------------------------
//   // Config — read from secure storage only, nothing hardcoded
//   // ---------------------------------------------------------------------------

//   Future<String?> getServerUrl() async {
//     return await _storage.read(key: _keyServerUrl);
//   }

//   Future<String?> getApiKey() async {
//     return await _storage.read(key: _keyApiKey);
//   }

//   Future<void> saveSettings({
//     required String serverUrl,
//     required String apiKey,
//   }) async {
//     await _storage.write(key: _keyServerUrl, value: serverUrl.trim());
//     await _storage.write(key: _keyApiKey,    value: apiKey.trim());
//   }

//   Future<bool> isConfigured() async {
//     final url = await getServerUrl();
//     final key = await getApiKey();
//     return url != null && url.isNotEmpty &&
//            key != null && key.isNotEmpty;
//   }

//   /// Wipe all stored credentials from device secure storage.
//   /// Call this if the API key is compromised or on logout.
//   Future<void> clearSettings() async {
//     await _storage.deleteAll();
//   }

//   // ---------------------------------------------------------------------------
//   // Endpoints
//   // ---------------------------------------------------------------------------

//   /// GET /status
//   /// Returns atlas running state. No auth required.
//   Future<AtlasStatus> getStatus() async {
//     final url = await getServerUrl();

//     if (url == null || url.isEmpty) {
//       return AtlasStatus(isRunning: false, state: 'not configured');
//     }

//     try {
//       final response = await http
//           .get(Uri.parse('$url/status'))
//           .timeout(const Duration(seconds: 10));

//       if (response.statusCode == 200) {
//         final data = jsonDecode(response.body);
//         return AtlasStatus(
//           isRunning: data['atlas_running'] ?? false,
//           state:     data['state'] ?? 'unknown',
//         );
//       }
//       return AtlasStatus(isRunning: false, state: 'error');
//     } catch (_) {
//       return AtlasStatus(isRunning: false, state: 'unreachable');
//     }
//   }

//   /// POST /command
//   /// Sends text command to Atlas, returns spoken response.
//   /// Timeout 60s — Mistral can be slow on complex tasks.
//   Future<AtlasResponse> sendCommand(String text) async {
//     final url    = await getServerUrl();
//     final apiKey = await getApiKey();

//     if (url == null || url.isEmpty) {
//       return AtlasResponse.error(
//         'No server URL set. Go to Settings and enter your Atlas server address.',
//       );
//     }

//     if (apiKey == null || apiKey.isEmpty) {
//       return AtlasResponse.error(
//         'No API key set. Go to Settings and add your Atlas API key.',
//       );
//     }

//     try {
//       final response = await http
//           .post(
//             Uri.parse('$url/command'),
//             headers: {
//               'Content-Type': 'application/json',
//               'X-API-Key':    apiKey,
//             },
//             body: jsonEncode({'text': text}),
//           )
//           .timeout(const Duration(seconds: 80));

//       if (response.statusCode == 200) {
//         final data = jsonDecode(response.body);
//         return AtlasResponse(
//           text:    data['response'] ?? 'No response.',
//           state:   data['state']    ?? 'listening',
//           success: true,
//         );
//       } else if (response.statusCode == 401) {
//         return AtlasResponse.error('Invalid API key. Check Settings.');
//       } else {
//         return AtlasResponse.error('Atlas error: ${response.statusCode}');
//       }
//     } on Exception catch (e) {
//       return AtlasResponse.error('Could not reach Atlas: $e');
//     }
//   }

// Future<void> cancelCommand() async {
//     final url    = await getServerUrl();
//     final apiKey = await getApiKey();
//     if (url == null || apiKey == null) return;
//     try {
//       await http.post(
//         Uri.parse('$url/cancel'),
//         headers: {'X-API-Key': apiKey},
//       ).timeout(const Duration(seconds: 5));
//     } catch (_) {}
//   }
// }
// // ---------------------------------------------------------------------------
// // Models
// // ---------------------------------------------------------------------------

// class AtlasStatus {
//   final bool   isRunning;
//   final String state;
//   const AtlasStatus({required this.isRunning, required this.state});
// }

// class AtlasResponse {
//   final String text;
//   final String state;
//   final bool   success;

//   const AtlasResponse({
//     required this.text,
//     required this.state,
//     required this.success,
//   });

//   factory AtlasResponse.error(String message) => AtlasResponse(
//     text:    message,
//     state:   'error',
//     success: false,
//   );
// }
