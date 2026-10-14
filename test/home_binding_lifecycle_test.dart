import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/modules/home/home_binding.dart';
import 'package:kuraku/app/modules/home/page_download/page_download_controller.dart';
import 'package:kuraku/app/modules/home/page_explore/page_explore_controller.dart';
import 'package:kuraku/app/modules/home/page_home/page_home_controller.dart';
import 'package:kuraku/app/modules/home/page_search/page_search_controller.dart';
import 'package:kuraku/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_controller.dart';
import 'package:kuraku/app/modules/player/player_controller.dart';

class _Controller extends GetxController {
  final draft = 'Saved draft'.obs;
}

void main() {
  testWidgets('Home page controllers keep their state when first resolved in a dismissed dialog', (tester) async {
    addTearDown(Get.reset);
    Get.lazyPut<PlayerController>(() => throw StateError('Player should stay uninitialized'));
    HomeBinding().dependencies();
    final settingsPolicy = GetInstance().getInstanceInfo<PageSettingsController>();
    GetInstance().lazyPut<_Controller>(() => _Controller(), permanent: settingsPolicy.isPermanent ?? false);
    Get.lazyPut<_Controller>(() => _Controller(), tag: 'transient');
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold(body: Text('Home'))));
    await tester.pumpAndSettle();

    late _Controller retained;
    final dialog = Get.dialog(Builder(builder: (context) {
      retained = Get.find<_Controller>();
      Get.find<_Controller>(tag: 'transient');
      return const Dialog(child: Text('Temporary dialog'));
    }));
    await tester.pumpAndSettle();
    retained.draft.value = 'Edited in dialog';
    Get.back();
    await tester.pumpAndSettle();
    await dialog;

    expect(Get.isRegistered<_Controller>(tag: 'transient'), isFalse);
    expect(Get.isRegistered<_Controller>(), isTrue);
    expect(Get.find<_Controller>(), same(retained));
    expect(retained.isClosed, isFalse);
    expect(retained.draft.value, 'Edited in dialog');
    final reassemble = tester.binding.reassembleApplication();
    await tester.pumpAndSettle();
    await reassemble;
    expect(Get.find<_Controller>(), same(retained));

    expect(GetInstance().getInstanceInfo<PageSettingsController>().isPermanent, isTrue);
    expect(GetInstance().getInstanceInfo<PageToolsController>().isPermanent, isTrue);
    expect(GetInstance().getInstanceInfo<PageDownloadController>().isPermanent, isTrue);
    expect(GetInstance().getInstanceInfo<PageExploreController>().isPermanent, isTrue);
    expect(GetInstance().getInstanceInfo<PageSearchController>().isPermanent, isTrue);
    expect(GetInstance().getInstanceInfo<PageHomeController>().isPermanent, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
