import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

import '../../../utils/helper_opener.dart';
import 'page_settings_controller.dart';

class PageSettingsView extends GetView<PageSettingsController> {
  const PageSettingsView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        ExButtonElevated(
          label: 'Go Folder',
          onPressed: () {
            HelperOpener.openFolder(controller.appSetting.appDir.path);
          },
        ),
      ],
    ).scrollVertical();
  }
}
