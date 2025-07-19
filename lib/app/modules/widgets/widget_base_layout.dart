import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';

import '../../core/app_color.dart';

class MyLayout extends StatelessWidget {
  const MyLayout({
    super.key,
    required this.appBarTitle,
    this.appBarLeading,
    this.appBarAction,
    required this.sideMenuContent,
    this.sideMenuWidth,
    this.sideMenuColor,
    required this.bodyContent,
    required this.footerContent,
    this.footerColor,
    this.floatingActionButton,
    this.isShowAppBarLeading = true,
  });

  // appBar
  final Widget? appBarTitle;
  final Widget? appBarLeading;
  final bool isShowAppBarLeading;

  final Widget? appBarAction;

  // sideMenu
  final Widget? sideMenuContent;
  final double? sideMenuWidth;
  final Color? sideMenuColor;

  // body
  final Widget bodyContent;

  // footer
  final Widget footerContent;
  final Color? footerColor;

  // fab
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: floatingActionButton?.pOnly(bottom: 16),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// row 1 -> Desktop
          sideMenu().wh(sideMenuWidth ?? 200, double.infinity),

          /// row 2
          VStack(
            [
              /// appbar -> Desktop
              myAppBarDesktop(),

              /// body
              body().expand(),

              /// footer
              footer(),
            ],
          ).expand(),
        ],
      ),
    );
  }

  Widget sideMenu() {
    return GlassContainer(
      borderRadius: BorderRadius.all(Radius.circular(0)),
      border: Border.all(color: Colors.transparent),
      blur: 50,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Get.theme.scaffoldBackgroundColor,
          Get.theme.scaffoldBackgroundColor,
        ],
      ),
      width: 100,
      height: double.infinity,
      child: VStack([
        kIsWeb ? 8.heightBox : 32.heightBox,
        sideMenuContent ?? Container(),
      ]),
    );
  }

  Widget myAppBarDesktop() {
    return AppBar(
      backgroundColor: AppColor.appBar,
      title: appBarTitle,
      centerTitle: false,
      leading: isShowAppBarLeading == true
          ? appBarLeading?.pOnly(right: 8) ??
              IconButton(
                icon: Icon(CupertinoIcons.arrow_left, size: 22),
                onPressed: Get.back,
              ).pOnly(right: 8)
          : null,
      actions: [
        appBarAction ?? Container(),
      ],
    );
  }

  Widget body() => bodyContent.w(double.infinity).pOnly(top: 8).color(Color.fromARGB(255, 14, 12, 17));

  Widget footer() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: footerColor ?? AppColor.footer),
      child: Padding(
        padding: !kIsWeb && Platform.isIOS ? EdgeInsets.only(bottom: 20, right: 8, left: 8) : EdgeInsets.all(0),
        child: footerContent,
      ),
    );
  }
}
