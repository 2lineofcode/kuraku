import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:ffmpeg_kit_flutter_new/media_information_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/modules/home/home_panel/home_panel_library.dart';
import 'package:kuraku/app/utils/helper_media.dart';

class _Session extends MediaInformationSession {
  _Session(this.output);
  final String? output;

  @override
  MediaInformation? getMediaInformation() => MediaInformation({'streams': [null]});

  @override
  Future<String?> getAllLogsAsString([int? waitTimeout]) async => output;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Linux library import reads raw dimensions and keeps files when probing fails', () async {
    final directory = await Directory.systemTemp.createTemp('kuraku-probe-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/holiday.mp4').writeAsBytes([1, 2, 3]);
    var fail = false;
    String? output = '{"streams":[{"width":320,"height":180}]}';
    const channel = MethodChannel('flutter.arthenica.com/ffmpeg_kit');
    const events = MethodChannel('flutter.arthenica.com/ffmpeg_kit_event');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getPlatform': return 'linux';
        case 'getArch': return 'x86_64';
        case 'getPackageName': return 'full-gpl';
        case 'isLTSBuild': return false;
        case 'mediaInformationSession': return {'sessionId': 1};
        case 'mediaInformationSessionExecute':
          if (fail) throw PlatformException(code: 'probe_failed');
          return null;
        case 'getMediaInformation': return {'streams': [null]};
        case 'abstractSessionGetAllLogsAsString': return output;
        default: return null;
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(events, null);
    });
    final video = await HomePanelLibrary.processVideo(file.path, directory.path);
    expect(video?.quality, '320x180');
    output = 'invalid metadata';
    expect((await HomePanelLibrary.processVideo(file.path, directory.path))?.videoPath, file.path);
    fail = true;
    expect((await HomePanelLibrary.processVideo(file.path, directory.path))?.videoPath, file.path);
    expect(await file.readAsBytes(), [1, 2, 3]);
  }, skip: !Platform.isLinux);

  test('Linux recovers dimensions and format from raw FFprobe output when native streams are null', () async {
    final session = _Session('{"streams":[{"codec_type":"audio"},{"codec_type":"video","width":1920,"height":1080}],'
      '"format":{"duration":"120.5","size":"12345"}}');
    final information = await HelperMedia.readInformation(session);
    final stream = HelperMedia.videoStream(information);
    expect([stream?.getWidth(), stream?.getHeight()], [1920, 1080]);
    expect(information?.getDuration(), '120.5');
    expect(information?.getSize(), '12345');
  }, skip: !Platform.isLinux);

  test('Linux handles failed, missing and malformed FFprobe output', () async {
    for (final output in [null, '', 'invalid video', 'null', '[]', '{"streams":[null]}']) {
      expect(HelperMedia.videoStream(await HelperMedia.readInformation(_Session(output))), isNull);
    }
  }, skip: !Platform.isLinux);

  test('video stream selection skips null entries, audio and invalid dimensions', () {
    final information = MediaInformation({'streams': [
      null, 'invalid', {}, {'codec_type': 'audio'},
      {'width': '1920', 'height': 1080}, {'width': 0, 'height': 1080},
      {'width': 1920, 'height': double.infinity}, {'width': -1, 'height': 1080},
      {'width': 1080, 'height': 1920},
    ]});
    final stream = HelperMedia.videoStream(information);
    expect([stream?.getWidth(), stream?.getHeight()], [1080, 1920]);
    for (final information in [null, MediaInformation(null), MediaInformation({'streams': {}})]) {
      expect(HelperMedia.videoStream(information), isNull);
    }
  });
}
