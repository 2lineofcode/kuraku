import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/widgets/widgets.dart';

void main() {
  test('the widgets barrel exposes every shared widget', () {
    expect(const MediaStack([SizedBox()]), isA<Widget>());
    expect(
      const MyLayout(appBarTitle: Text('t'), sideMenuContent: SizedBox(), bodyContent: SizedBox(), footerContent: SizedBox()),
      isA<Widget>(),
    );
    expect(const ExThumbnail(imageUrl: '', width: 10, height: 10), isA<Widget>());
    expect(ExChewieCustom(video: Videos()), isA<Widget>());
    expect(const ExAutoComplate(items: ['a']), isA<Widget>());
    expect(DoubleTap(child: const SizedBox(), onDoubleTap: () {}), isA<Widget>());
  });

  test('the widgets barrel also re-exports the helper mixins', () {
    // Both barrels must keep working: `widgets.dart` re-exports `helper.dart`.
    expect(HelperMisc.formatVideoQuality('1920x1080'), startsWith('FHD'));
    expect(HelperDecensor.decensor('R**e'), 'Rape');
    expect(HelperDecensor.censored('Rape'), 'R**e');
    expect(HelperBadge.getBadgeTotVidText(0), 'Noobless');
    expect(HelperBadge.getCollectionProgress(0).nextTitle, 'Jav Lover');
  });

  test('the helper entry points stay callable through the barrel', () {
    expect(HelperToast.error, isNotNull);
    expect(HelperToast.success, isNotNull);
    expect(HelperLoading.show, isNotNull);
    expect(HelperLoading.dismiss, isNotNull);
    expect(HelperFilePicker.pickFolderSubFolder, isNotNull);
    expect(HelperOpener.openVideoFile, isNotNull);
    expect('ABP-001'.isValidVideoCode(), isTrue);
    expect('/movies/abp-001.mp4'.getVideoCode(), 'ABP-001');
  });
}
