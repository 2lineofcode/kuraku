import 'dart:io';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';

typedef FileIdentity = ({int size, int modifiedAt, String fingerprint});

mixin VideoFileIdentity {
  static Future<FileIdentity?> read(String path, {FileIdentity? cached}) async {
    RandomAccessFile? handle;
    try {
      final file = File(path);
      final before = await file.stat();
      if (before.type != FileSystemEntityType.file || before.size <= 0) return null;
      final modified = before.modified.microsecondsSinceEpoch;
      if (cached != null && cached.size == before.size && cached.modifiedAt == modified) return cached;
      handle = await file.open();
      final bytes = <int>[];
      const sampleSize = 64 * 1024;
      // ponytail: sample five regions to avoid hashing multi-GB files; use full hashes for adversarial content.
      for (var i = 0; i < 5; i++) {
        final offset = math.max(0, before.size - sampleSize) * i ~/ 4;
        await handle.setPosition(offset);
        final length = math.min(sampleSize, before.size - offset);
        final sample = await handle.read(length);
        if (sample.length != length) return null;
        bytes.addAll(sample);
      }
      final after = await file.stat();
      if (after.size != before.size || after.modified != before.modified) return null;
      final hash = await Sha256().hash(bytes);
      return (size: before.size, modifiedAt: modified,
        fingerprint: hash.bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join());
    } on FileSystemException {
      return null;
    } finally {
      await handle?.close();
    }
  }
}
