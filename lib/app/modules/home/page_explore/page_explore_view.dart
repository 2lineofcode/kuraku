import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'page_explore_controller.dart';

class PageExploreView extends GetView<PageExploreController> {
  const PageExploreView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        'Explore Page'.text.make(),
      ],
    ).scrollVertical();
  }
}
