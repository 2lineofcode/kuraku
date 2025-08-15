import 'dart:async';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager_plus/window_manager_plus.dart';

import 'app/core/app_logging.dart';
import 'app/core/app_pref.dart';
import 'app/core/app_setting.dart';
import 'app/data/database/db_init.dart';
import 'app/routes/app_pages.dart';
import 'env.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Stopwatch sw = Stopwatch()..start();

  await hotKeyManager.unregisterAll();

  /// makesure `AppSettingService` already initialized
  await Get.putAsync(() async {
    final service = AppSettingService();
    await service.onReady();
    return service;
  }, permanent: true);

  // makesure `DBService` already initialized
  await Get.putAsync(() async {
    final service = DBService();
    await service.onReady();
    return service;
  }, permanent: true);

  AppLog.logD('All Depedencies loaded in ${sw.elapsedMilliseconds}ms');
  runApp(JavIt());
}

class JavIt extends StatefulWidget {
  const JavIt({super.key});

  @override
  State<JavIt> createState() => _JavItState();
}

class _JavItState extends State<JavIt> with WindowListener {
  @override
  void initState() {
    super.initState();
    WindowManagerPlus.current.addListener(this);
  }

  @override
  void dispose() {
    WindowManagerPlus.current.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: GetMaterialApp(
        enableLog: Env.logLvl == 'debug' ? true : false,
        title: Env.appName,
        initialRoute: AppPages.INITIAL,
        theme: ThemeData.dark(),
        getPages: AppPages.routes,
        defaultTransition: Transition.fadeIn,
        debugShowCheckedModeBanner: false,
      ),
    );
  }

  @override
  void onWindowClose([int? windowId]) {
    AppPref.setAppLastOpen(DateTime.now().toStringEx());
    AppLog.logD('onWindowClose');
  }

  @override
  void onWindowEnterFullScreen([int? windowId]) {
    Get.forceAppUpdate();
    AppLog.logD('onWindowEnterFullScreen');
  }

  @override
  void onWindowLeaveFullScreen([int? windowId]) {
    Get.forceAppUpdate();
    AppLog.logD('onWindowLeaveFullScreen');
  }
}
