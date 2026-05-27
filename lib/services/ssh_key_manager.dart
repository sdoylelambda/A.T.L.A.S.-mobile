// lib/services/ssh_key_manager.dart
//
// Manages the Atlas SSH keypair stored in flutter_secure_storage.
// Keys never touch disk — private key lives only in hardware-backed
// secure storage on Android (Keystore).
//
// Flow:
//   First launch  → generate ed25519 keypair → store in secure storage
//   Every launch  → load private key → SSH auth (no password)
//   Fallback      → password auth if key auth fails
//   Setup screen  → show public key as QR → user scans with computer

import 'dart:convert';
import 'dart:typed_data';
import 'dart:developer' as dev;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SshKeyManager {
  static const _storage        = FlutterSecureStorage();
  static const _keyPrivatePem  = 'atlas_ssh_private_pem';
  static const _keyPublicPem   = 'atlas_ssh_public_pem';
  static const _keyPublicB64   = 'atlas_ssh_public_b64';

  // ---------------------------------------------------------------------------
  // Key generation
  // ---------------------------------------------------------------------------

  /// Generate a new ed25519 keypair and store in secure storage.
  /// Called once on first launch or after key reset.
  static Future<void> generateAndStore() async {
    dev.log('[SSH Key] Generating new ed25519 keypair...');

    final algorithm = Ed25519();
    final keyPair   = await algorithm.newKeyPair();

    final privateKey = await keyPair.extractPrivateKeyBytes();
    final publicKey  = await keyPair.extractPublicKey();
    final pubBytes   = publicKey.bytes;

    // format as OpenSSH authorized_keys line
    // ssh-ed25519 <base64> atlas-mobile
    final pubB64 = _encodeOpenSshPublicKey(pubBytes);
    final pubLine = 'ssh-ed25519 $pubB64 atlas-mobile';

    // PEM format for dartssh2
    final pemPrivate = _encodeOpenSshPrivateKey(
      Uint8List.fromList(privateKey),
      Uint8List.fromList(pubBytes),
    );

    await _storage.write(key: _keyPrivatePem, value: pemPrivate);
    await _storage.write(key: _keyPublicPem,  value: pubLine);
    await _storage.write(key: _keyPublicB64,  value: pubB64);

    dev.log('[SSH Key] Keypair generated and stored');
  }

  // ---------------------------------------------------------------------------
  // Key retrieval
  // ---------------------------------------------------------------------------

  static Future<bool> hasKey() async {
    final pem = await _storage.read(key: _keyPrivatePem);
    return pem != null && pem.isNotEmpty;
  }

  /// Returns the private key PEM string for use with dartssh2.
  static Future<String?> getPrivatePem() async {
    return await _storage.read(key: _keyPrivatePem);
  }

  /// Returns the full authorized_keys line to add to the computer.
  /// e.g. "ssh-ed25519 AAAA... atlas-mobile"
  static Future<String?> getPublicKeyLine() async {
    return await _storage.read(key: _keyPublicPem);
  }

  /// Delete all stored keys.
  static Future<void> deleteKeys() async {
    await _storage.delete(key: _keyPrivatePem);
    await _storage.delete(key: _keyPublicPem);
    await _storage.delete(key: _keyPublicB64);
  }

  // ---------------------------------------------------------------------------
  // OpenSSH encoding
  // ---------------------------------------------------------------------------

  /// Encode ed25519 public key in OpenSSH base64 format.
  static String _encodeOpenSshPublicKey(List<int> pubBytes) {
    // OpenSSH public key wire format:
    // string "ssh-ed25519"
    // string <32 bytes public key>
    final buf = BytesBuilder();
    final keyType = utf8.encode('ssh-ed25519');
    _writeU32(buf, keyType.length);
    buf.add(keyType);
    _writeU32(buf, pubBytes.length);
    buf.add(pubBytes);
    return base64.encode(buf.toBytes());
  }

  /// Encode as OpenSSH private key PEM for dartssh2 SSHKeyPair.fromPem().
  static String _encodeOpenSshPrivateKey(
      Uint8List privateBytes, Uint8List publicBytes) {
    // OpenSSH private key format (RFC-compliant)
    final buf = BytesBuilder();

    // magic
    buf.add(utf8.encode('openssh-key-v1\x00'));

    // cipher: none, kdf: none, kdf options: empty, num keys: 1
    _writeString(buf, 'none');  // cipher
    _writeString(buf, 'none');  // kdf
    _writeU32(buf, 0);          // kdf options length (empty)
    _writeU32(buf, 1);          // number of keys

    // public key block
    final pubBlock = BytesBuilder();
    _writeStringBytes(pubBlock, utf8.encode('ssh-ed25519'));
    _writeStringBytes(pubBlock, publicBytes);
    _writeU32(buf, pubBlock.toBytes().length);
    buf.add(pubBlock.toBytes());

    // private key block (unencrypted)
    final privBlock = BytesBuilder();
    // check ints (two identical random ints for integrity check)
    final check = 0x12345678;
    _writeU32(privBlock, check);
    _writeU32(privBlock, check);
    // key type
    _writeStringBytes(privBlock, utf8.encode('ssh-ed25519'));
    // public key
    _writeStringBytes(privBlock, publicBytes);
    // private key (64 bytes: 32 private seed + 32 public)
    final fullPrivate = Uint8List(64);
    fullPrivate.setRange(0, 32, privateBytes);
    fullPrivate.setRange(32, 64, publicBytes);
    _writeStringBytes(privBlock, fullPrivate);
    // comment
    _writeString(privBlock, 'atlas-mobile');
    // padding (1,2,3... until block aligned to 8)
    var i = 1;
    while (privBlock.length % 8 != 0) { privBlock.addByte(i++); }

    final privBytes = privBlock.toBytes();
    _writeU32(buf, privBytes.length);
    buf.add(privBytes);

    final b64 = base64.encode(buf.toBytes());
    // wrap at 70 chars
    final wrapped = StringBuffer();
    for (var i = 0; i < b64.length; i += 70) {
      wrapped.writeln(b64.substring(i,
          i + 70 > b64.length ? b64.length : i + 70));
    }
    return '-----BEGIN OPENSSH PRIVATE KEY-----\n'
        '$wrapped'
        '-----END OPENSSH PRIVATE KEY-----';
  }

  static void _writeU32(BytesBuilder buf, int value) {
    buf.addByte((value >> 24) & 0xff);
    buf.addByte((value >> 16) & 0xff);
    buf.addByte((value >>  8) & 0xff);
    buf.addByte( value        & 0xff);
  }

  static void _writeString(BytesBuilder buf, String s) {
    final bytes = utf8.encode(s);
    _writeU32(buf, bytes.length);
    buf.add(bytes);
  }

  static void _writeStringBytes(BytesBuilder buf, List<int> bytes) {
    _writeU32(buf, bytes.length);
    buf.add(bytes);
  }
}
