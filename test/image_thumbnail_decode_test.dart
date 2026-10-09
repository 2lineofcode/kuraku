import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a 36 MB image keeps full main resolution while thumbnail decode stays bounded', (tester) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('thumbnail_decode_');
      ImageInfo? main;
      ImageInfo? thumbnail;
      try {
        const width = 4000;
        const height = 3000;
        const pixelBytes = width * height * 3;
        final bytes = Uint8List(54 + pixelBytes);
        final header = ByteData.sublistView(bytes);
        header.setUint16(0, 0x4d42, Endian.little);
        header.setUint32(2, bytes.length, Endian.little);
        header.setUint32(10, 54, Endian.little);
        header.setUint32(14, 40, Endian.little);
        header.setInt32(18, width, Endian.little);
        header.setInt32(22, height, Endian.little);
        header.setUint16(26, 1, Endian.little);
        header.setUint16(28, 24, Endian.little);
        header.setUint32(34, pixelBytes, Endian.little);
        final file = await File('${directory.path}/large.bmp').writeAsBytes(bytes);
        expect(await file.length(), greaterThan(30 * 1024 * 1024));

        Future<ImageInfo> decode(ImageProvider provider) async {
          final completer = Completer<ImageInfo>();
          final stream = provider.resolve(const ImageConfiguration());
          final listener = ImageStreamListener((info, _) => completer.complete(info),
            onError: (error, stack) => completer.completeError(error, stack));
          stream.addListener(listener);
          try {
            return await completer.future.timeout(const Duration(seconds: 20));
          } finally {
            stream.removeListener(listener);
          }
        }

        main = await decode(FileImage(file));
        thumbnail = await decode(ResizeImage(FileImage(file), width: 116, height: 68, policy: ResizeImagePolicy.fit));
        expect(main.image.width, width);
        expect(main.image.height, height);
        expect(thumbnail.image.width, lessThanOrEqualTo(116));
        expect(thumbnail.image.height, 68);
        expect(thumbnail.image.width / thumbnail.image.height, closeTo(width / height, 1 / 68));
      } finally {
        main?.dispose();
        thumbnail?.dispose();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await directory.delete(recursive: true);
      }
    });
  });
}
