import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SecureHiveService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _hiveKeyName = 'studygrades_hive_key_v1';
  static const String _pendingHiveKeyName = 'studygrades_hive_key_v1_pending';
  static List<int>? _cachedKey;

  static Future<Box> openBox(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box(name);

    final storedKey = await _readStoredKey(_hiveKeyName);
    if (storedKey != null) {
      return _openEncryptedBox(name, storedKey);
    }

    final pendingKey = await _readStoredKey(_pendingHiveKeyName);
    if (pendingKey != null) {
      final box = await _openOrMigrateWithNewKey(name, pendingKey);
      await _promotePendingKey(pendingKey);
      return box;
    }

    final key = _createKey();
    await _writeKey(_pendingHiveKeyName, key);
    final box = await _openOrMigrateWithNewKey(name, key);
    await _promotePendingKey(key);
    return box;
  }

  static Future<Box> _openEncryptedBox(String name, List<int> key) async {
    final cipher = HiveAesCipher(key);
    try {
      // crashRecovery MUST be false here: Hive's default crash-recovery
      // treats a cipher mismatch exactly like file corruption and silently
      // TRUNCATES the box to the point of mismatch instead of throwing.
      // Since every box on disk before this feature shipped is unencrypted,
      // opening it with a cipher (crashRecovery: true, the default) would
      // wipe 100% of existing local data (pending offline grades, local
      // accounts, settings) on the very first launch after the update,
      // with no exception ever thrown and no migration path triggered.
      // crashRecovery: false forces a real HiveError on mismatch so the
      // legacy migration below actually runs instead of silently deleting
      // the user's data.
      return await Hive.openBox(
        name,
        encryptionCipher: cipher,
        crashRecovery: false,
      );
    } on HiveError catch (error) {
      throw HiveError(
        'Encrypted Hive box "$name" could not be opened with the stored key: $error',
      );
    }
  }

  static Future<Box> _openOrMigrateWithNewKey(
    String name,
    List<int> key,
  ) async {
    final cipher = HiveAesCipher(key);
    try {
      return await Hive.openBox(
        name,
        encryptionCipher: cipher,
        crashRecovery: false,
      );
    } on HiveError {
      return _migrateLegacyBox(name, cipher);
    }
  }

  static Future<List<int>?> _readStoredKey(String keyName) async {
    if (keyName == _hiveKeyName && _cachedKey != null) return _cachedKey!;

    final stored = await _secureStorage.read(key: keyName);
    if (stored != null && stored.isNotEmpty) {
      try {
        final decoded = base64Decode(stored);
        if (decoded.length == 32) {
          if (keyName == _hiveKeyName) {
            _cachedKey = decoded;
          }
          return decoded;
        }
      } catch (_) {
        throw HiveError('Stored Hive encryption key is not valid base64.');
      }
      throw HiveError('Stored Hive encryption key has an invalid length.');
    }

    return null;
  }

  static List<int> _createKey() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }

  static Future<void> _writeKey(String keyName, List<int> key) async {
    await _secureStorage.write(key: keyName, value: base64Encode(key));
  }

  static Future<void> _promotePendingKey(List<int> key) async {
    await _writeKey(_hiveKeyName, key);
    await _secureStorage.delete(key: _pendingHiveKeyName);
    _cachedKey = key;
  }

  static Future<Box> _migrateLegacyBox(
    String name,
    HiveAesCipher cipher,
  ) async {
    late final Box legacy;
    try {
      legacy = await Hive.openBox(name, crashRecovery: false);
    } on HiveError catch (error) {
      throw HiveError(
        'Hive box "$name" is not readable as legacy plaintext. Refusing destructive migration: $error',
      );
    }
    final snapshot = <dynamic, dynamic>{};
    for (final key in legacy.keys) {
      snapshot[key] = legacy.get(key);
    }
    await legacy.close();
    await Hive.deleteBoxFromDisk(name);

    final encrypted = await Hive.openBox(
      name,
      encryptionCipher: cipher,
      crashRecovery: false,
    );
    if (snapshot.isNotEmpty) {
      await encrypted.putAll(snapshot);
    }
    return encrypted;
  }
}
