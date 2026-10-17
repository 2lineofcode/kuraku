import 'dart:io';
import 'dart:ui' as ui;

import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_color.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/modules/widgets/widget_library_empty_state.dart';

void main() {
  tearDown(() { Get.reset(); Get.clearTranslations(); });

  testWidgets('folder drop empty state fits small windows and keeps Add folder accessible', (tester) async {
    const output = String.fromEnvironment('EMPTY_STATE_QA_PATH');
    const font = String.fromEnvironment('VISUAL_QA_FONT');
    if (font.isNotEmpty) {
      await tester.runAsync(() async {
        await (FontLoader('VisualQA')..addFont(File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
      });
    }
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    var additions = 0;
    for (final language in ['en', 'id']) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        for (final size in [const Size(900, 650), const Size(280, 180)]) {
          tester.view.physicalSize = size;
          Get.locale = Locale(language);
          await tester.pumpWidget(GetMaterialApp(
            translations: AppTranslations(), locale: Locale(language),
            theme: ThemeData(brightness: brightness, fontFamily: font.isEmpty ? null : 'VisualQA'),
            home: Builder(builder: (_) => Scaffold(backgroundColor: AppColor.body,
              body: RepaintBoundary(key: boundary, child: ColoredBox(color: AppColor.body, child: LibraryEmptyState(onAdd: () => additions++))))),
          ));
          await tester.pumpAndSettle();
          expect(find.byType(DottedBorder), findsOneWidget);
          expect(find.text('Drop a folder here'.tr), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$language $brightness $size');
          if (output.isNotEmpty && size.width == 900 && language == 'en') {
            await tester.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
              final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
              await File('$output-${brightness.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.ensureVisible(find.text('Add folder'.tr));
          final before = additions;
          await tester.tap(find.text('Add folder'.tr));
          await tester.pumpAndSettle();
          expect(additions, before + 1);
          expect(tester.takeException(), isNull);
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
