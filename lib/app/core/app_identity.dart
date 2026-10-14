import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

class AppIdentity {
  static const displayName = 'KuraKu';
  static const legacyName = 'JavIt';
  static const legacyDatabase = 'javit.db';

  static Future<void> migrateMacOSDirectory(Directory current) async {
    final legacy = Directory(p.join(p.dirname(current.path), 'com.example.javit'));
    if (legacy.path == current.path || !await legacy.exists()) return;
    if (await current.exists()) {
      if (!await current.list().isEmpty) throw StateError('Both legacy and current macOS data folders exist: ${current.path}.');
      await current.delete();
    }
    await legacy.rename(current.path);
    for (final suffix in ['', '-wal', '-shm']) {
      final thumbnail = File(p.join(current.path, 'javitThumbnail.db$suffix'));
      if (await thumbnail.exists()) {
        final next = p.join(current.path, 'kurakuThumbnail.db$suffix');
        if (await File(next).exists()) throw StateError('Conflicting legacy and current thumbnail caches.');
        await thumbnail.rename(next);
      }
    }
  }

  static Future<String> migrate(Directory documents, String name) async {
    final target = Directory(p.join(documents.path, name));
    final legacy = Directory(p.join(documents.path, legacyName));
    if (name != legacyName && await legacy.exists()) {
      if (await target.exists()) {
        if (!await target.list().isEmpty) throw StateError('Both legacy and current app folders exist. Move one aside before restarting.');
        await target.delete();
      }
      await legacy.rename(target.path);
    }
    await target.create(recursive: true);
    if (name == legacyName) return target.path;

    final oldStorage = File(p.join(target.path, 'javit.gs'));
    final oldBackup = File(p.join(target.path, 'javit.bak'));
    final storage = File(p.join(target.path, '${name.toLowerCase()}.gs'));
    if ((await oldStorage.exists() || await oldBackup.exists()) && !await storage.exists()) {
      Map<String, dynamic> values;
      try {
        values = await _readStorage(oldStorage, legacyName);
      } catch (_) {
        if (!await oldBackup.exists() || await oldBackup.length() == 0) rethrow;
        values = await _readStorage(oldBackup, legacyName);
      }
      migrateSqlSettings(values);
      final encrypted = await _encryptStorage(values, name);
      await _writeStorage(File(p.join(target.path, '${name.toLowerCase()}.bak')), encrypted);
      await _writeStorage(storage, encrypted);
    }
    if (await oldStorage.exists() || await oldBackup.exists()) {
      await _readStorage(storage, name);
      if (await oldStorage.exists()) await oldStorage.delete();
      if (await oldBackup.exists()) await oldBackup.delete();
    }

    final moves = {'javit.db-wal': 'kuraku.db-wal', 'javit.db-shm': 'kuraku.db-shm',
      legacyDatabase: 'kuraku.db', 'javit.dio': 'kuraku.dio'};
    for (final entry in moves.entries) {
      if (await File(p.join(target.path, entry.key)).exists() && await File(p.join(target.path, entry.value)).exists()) {
        throw StateError('Conflicting database/cache files: ${entry.key} and ${entry.value}.');
      }
    }
    for (final entry in moves.entries) {
      final file = File(p.join(target.path, entry.key));
      if (await file.exists()) await file.rename(p.join(target.path, entry.value));
    }

    // Python venv entry points embed the original absolute app-data path.
    final bin = Directory(p.join(target.path, 'semantic_runtime', 'venv', Platform.isWindows ? 'Scripts' : 'bin'));
    if (await bin.exists()) {
      final entries = await bin.list(followLinks: false).toList();
      final config = File(p.join(target.path, 'semantic_runtime', 'venv', 'pyvenv.cfg'));
      if (await config.exists()) entries.add(config);
      for (final entry in entries) {
        if (entry is! File) continue;
        String text;
        try { text = await entry.readAsString(); } on FormatException { continue; }
        if (text.contains(legacy.path)) await entry.writeAsString(text.replaceAll(legacy.path, target.path), flush: true);
      }
    }
    return target.path;
  }

  static void migrateSqlSettings(Map<String, dynamic> settings) {
    void renameSource(Map values) {
      if (values.containsKey(legacyDatabase)) {
        if (values.containsKey('kuraku.db')) throw const FormatException('Conflicting legacy and current SQL drafts/snippets.');
        values.putIfAbsent('kuraku.db', () => values[legacyDatabase]);
        values.remove(legacyDatabase);
      }
    }
    final snippets = settings['sql_snippets'];
    if (snippets is Map) renameSource(snippets);
    final tabs = settings['sql_tabs'];
    if (tabs is Map && tabs['tabs'] is List) {
      for (final tab in (tabs['tabs'] as List).whereType<Map>()) {
        if (tab['source'] == legacyDatabase) tab['source'] = 'kuraku.db';
        for (final field in ['drafts', 'parameters', 'loaded']) {
          if (tab[field] is Map) renameSource(tab[field]);
        }
      }
    }
  }

  static Future<SecretKey> _key(String password) => Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 1000, bits: 128)
      .deriveKeyFromPassword(password: password, nonce: password.runes.toList().reversed.toList());

  static Future<Map<String, dynamic>> _readStorage(File file, String password) async {
    final payload = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (!payload.containsKey('cipherText')) return payload;
    List<int> bytes(String value) => [for (var i = 0; i < value.length; i += 2) int.parse(value.substring(i, i + 2), radix: 16)];
    final clear = await AesCtr.with128bits(macAlgorithm: Hmac.sha256()).decryptString(
      SecretBox(bytes(payload['cipherText'] as String), nonce: bytes(payload['nonce'] as String), mac: Mac(bytes(payload['mac'] as String))),
      secretKey: await _key(password),
    );
    return jsonDecode(clear) as Map<String, dynamic>;
  }

  static Future<String> _encryptStorage(Map<String, dynamic> values, String password) async {
    final box = await AesCtr.with128bits(macAlgorithm: Hmac.sha256()).encryptString(jsonEncode(values), secretKey: await _key(password));
    String hex(List<int> bytes) => bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return jsonEncode({'cipherText': hex(box.cipherText), 'nonce': hex(box.nonce), 'mac': hex(box.mac.bytes)});
  }

  static Future<void> _writeStorage(File file, String value) async {
    final pending = File('${file.path}.migrating');
    await pending.writeAsString(value, flush: true);
    await pending.rename(file.path);
  }

  static String migrateChatLinks(String content) => content.replaceAllMapped(
    RegExp(r'\bjavit-(video|cover|translate|similar):'), (match) => 'kuraku-${match[1]}:',
  );
}
