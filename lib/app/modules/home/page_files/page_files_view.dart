import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'page_files_controller.dart';

class PageFilesView extends GetView<PageFilesController> {
  const PageFilesView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        'Files Page'.text.make(),
      ],
    ).scrollVertical();
  }
}
