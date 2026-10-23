import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/modules/widgets/widget_video_properties.dart';
import 'package:kuraku/app/utils/helper_media.dart';
import 'package:overlayment/overlayment.dart';

void main() {
  test('codec labels and rational frame rates handle missing and invalid values', () {
    expect(['h264', 'hevc', 'av1', 'vp9', null].map(HelperMedia.codecLabel), ['H.264', 'H.265', 'AV1', 'VP9', '—']);
    expect(HelperMedia.frameRate('30000/1001'), '29.97 fps');
    expect(HelperMedia.frameRate('30/1'), '30 fps');
    for (final value in [null, '0/0', '1/0', 'N/A', '-1', 'NaN', 'Infinity']) {
      expect(HelperMedia.frameRate(value), '—');
    }
  });

  test('codec selection skips attached cover art', () {
    final info = MediaInformation({'streams': [
      {'codec_type': 'video', 'codec_name': 'mjpeg', 'width': 500, 'height': 500, 'disposition': {'attached_pic': 1}},
      {'codec_type': 'video', 'codec_name': 'av1', 'width': 1920, 'height': 1080},
    ]});
    expect(HelperMedia.codecLabel(HelperMedia.videoStream(info)?.getCodec()), 'AV1');
  });

  test('missing files fail without starting FFprobe', () async {
    await expectLater(HelperMedia.readFile(''), throwsA(isA<FileSystemException>()));
  });

  testWidgets('properties show loading, video, multiple audio tracks and subtitle', (tester) async {
    final result = Completer<MediaInformation?>();
    var closed = false;
    await tester.pumpWidget(MaterialApp(home: VideoPropertiesDialog(path: '/videos/example.mkv', information: result.future,
      onClose: () => closed = true)));
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    result.complete(MediaInformation({
      'format': {'format_name': 'matroska', 'size': '123456', 'duration': '90.5'},
      'streams': [null,
        {'index': 0, 'codec_type': 'video', 'codec_name': 'hevc', 'width': 1920, 'height': 1080, 'avg_frame_rate': '24000/1001'},
        {'index': 1, 'codec_type': 'audio', 'codec_name': 'aac', 'channels': 2, 'sample_rate': '48000', 'tags': {'language': 'jpn'}},
        {'index': 2, 'codec_type': 'audio', 'codec_name': 'opus', 'tags': {'language': 'eng'}},
        {'index': 3, 'codec_type': 'subtitle', 'codec_name': 'subrip'},
      ],
    }));
    await tester.pumpAndSettle();
    expect(find.text('H.265'), findsOneWidget);
    expect(find.text('1920 × 1080'), findsOneWidget);
    expect(find.text('23.976 fps'), findsOneWidget);
    expect(find.text('AAC'), findsOneWidget);
    expect(find.text('OPUS'), findsOneWidget);
    expect(find.text('SUBRIP'), findsOneWidget);
    expect(find.text('jpn'), findsOneWidget);
    expect(find.text('eng'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Properties opens and closes through Overlayment', (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => VideoPropertiesDialog.open('/example.mp4', information: Future.value(MediaInformation({
        'format': {'format_name': 'mp4'}, 'streams': [],
      }))), child: const Text('Open properties'),
    )))));
    await tester.tap(find.text('Open properties'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(tester.getSize(find.byType(VideoPropertiesDialog)).width, 520);
    expect(tester.getSize(find.byType(VideoPropertiesDialog)).height, closeTo(600 * .8, .1));
    expect(find.text('example.mp4'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(VideoPropertiesDialog), findsNothing);
    expect(Overlayment.count, 0);
    expect(tester.takeException(), isNull);
    Get.reset();
  });

  testWidgets('failed probes show an error and remain dismissible', (tester) async {
    final result = Completer<MediaInformation?>();
    await tester.pumpWidget(MaterialApp(home: VideoPropertiesDialog(path: '/missing.mp4',
      information: result.future, onClose: () {})));
    result.completeError(const FormatException());
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not read video properties.'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
