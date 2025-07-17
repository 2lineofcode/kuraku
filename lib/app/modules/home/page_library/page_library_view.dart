import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'page_library_controller.dart';

class PageLibraryView extends GetView<PageLibraryController> {
  const PageLibraryView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        'Library Page'.text.make(),
      ],
    ).scrollVertical();
  }
}
