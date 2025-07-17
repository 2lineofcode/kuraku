import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

import '../../../core/app_color.dart';
import 'page_home_controller.dart';

class PageHomeView extends GetView<PageHomeController> {
  const PageHomeView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        ExButtonElevated(
            label: 'test',
            onPressed: ()=> controller.testt(),
        ),
        // Random: Videos maybe you like
        HStack([
          'Videos maybe you like'.text.size(12).make(),
          Spacer(),
          IconButton(
            icon: Icon(CupertinoIcons.refresh, size: 16),
            onPressed: () {},
          ),
        ]).pOnly(bottom: 8),
        ListView.builder(
          itemCount: 5,
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) {
            return Container(
              width: 200,
              color: AppColor.sideMenuPrimary,
            ).cornerRadius(8).pOnly(left: 4, right: 4);
          },
        ).wh(double.infinity, 120),

        // Top 10: Watch again and again
        HStack([
          'Watch again and again'.text.size(12).make(),
          Spacer(),
          IconButton(
            icon: Icon(CupertinoIcons.refresh, size: 16),
            onPressed: () {},
          ),
        ]).pOnly(bottom: 8, top: 8),
        ListView.builder(
          itemCount: 5,
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) {
            return Container(
              width: 120,
              color: AppColor.sideMenuPrimary,
            ).cornerRadius(8).pOnly(left: 4, right: 4);
          },
        ).wh(double.infinity, 200),

        // Favorite videos
        HStack([
          'Favorite videos'.text.size(12).make(),
          Spacer(),
          IconButton(
            icon: Icon(CupertinoIcons.refresh, size: 16),
            onPressed: () {},
          ),
        ]).pOnly(bottom: 8, top: 8),
        ListView.builder(
          itemCount: 5,
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) {
            return Container(
              width: 120,
              color: AppColor.sideMenuPrimary,
            ).cornerRadius(8).pOnly(left: 4, right: 4);
          },
        ).wh(double.infinity, 200),

        // Featured Actress
        HStack([
          'Featured Actress'.text.size(12).make(),
          Spacer(),
          IconButton(
            icon: Icon(CupertinoIcons.refresh, size: 16),
            onPressed: () {},
          ),
        ]).pOnly(bottom: 8, top: 8),
        ListView.builder(
          itemCount: 5,
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) {
            return Container(
              width: 120,
              color: AppColor.sideMenuPrimary,
            ).cornerRadius(8).pOnly(left: 4, right: 4);
          },
        ).wh(double.infinity, 200),
      ],
    ).scrollVertical();
  }
}
