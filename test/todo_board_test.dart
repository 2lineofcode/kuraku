import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/core/app_color.dart';
import 'package:javit/app/core/app_translations.dart';
import 'package:javit/app/data/models/activity_entity.dart';
import 'package:javit/app/modules/home/page_tools/page_tools_controller.dart';
import 'package:javit/app/modules/home/page_tools/page_tools_view.dart';

class _Tools extends PageToolsController {
  int additions = 0;
  int refreshes = 0;
  @override
  Future<void> onRefresh() async {}
  @override
  Future<void> addTodo() async { additions++; }
  @override
  Future<void> getTodos() async { refreshes++; }
  @override
  Future<void> deleteTodos(Activity todo) async { todoList.remove(todo); }
}

void main() {
  testWidgets('Todo board groups library matches, adapts and keeps actions connected', (tester) async {
    Get.testMode = true;
    final controller = Get.put<PageToolsController>(_Tools());
    final video = Activity(id: 'pending', content: 'ABP-123');
    controller.todoList.addAll([video, Activity(id: 'note', content: 'A longer note about videos to look for later'), Activity(id: 'done', content: '✔︎ SSIS-001')]);
    addTearDown(() { Get.reset(); Get.clearTranslations(); });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const font = String.fromEnvironment('VISUAL_QA_FONT');
    const output = String.fromEnvironment('TODO_QA_PATH');
    if (font.isNotEmpty) {
      await tester.runAsync(() async {
        final loader = FontLoader('VisualQA')..addFont(File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
        await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
    }
    final boundary = GlobalKey();
    final todo = find.byKey(const ValueKey('TODO'));
    final downloaded = find.byKey(const ValueKey('DOWNLOADED'));
    for (final language in ['en', 'id']) {
      for (final dark in [false, true]) {
        for (final width in [746.0, 1100.0, 360.0]) {
          tester.view.physicalSize = Size(width, 600);
          await tester.pumpWidget(GetMaterialApp(
            translations: AppTranslations(), locale: Locale(language),
            theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light, fontFamily: font.isEmpty ? null : 'VisualQA'),
            home: Builder(builder: (context) {
              AppColor.dependOn(context);
              return Scaffold(backgroundColor: AppColor.body, body: RepaintBoundary(key: boundary,
                child: ColoredBox(color: AppColor.body, child: Padding(padding: const EdgeInsets.all(16), child: const PageToolsView().uiTODO())),
              ));
            }),
          ));
          await tester.pumpAndSettle();
          expect(find.descendant(of: todo, matching: find.text('ABP-123')), findsOneWidget);
          expect(find.descendant(of: todo, matching: find.text('2')), findsOneWidget);
          expect(find.descendant(of: downloaded, matching: find.text('SSIS-001')), findsOneWidget);
          expect(find.descendant(of: downloaded, matching: find.text('1')), findsOneWidget);
          expect(find.text('✔︎ SSIS-001'), findsNothing);
          if (width >= 746) {
            expect(tester.getTopLeft(todo).dy, tester.getTopLeft(downloaded).dy);
            expect(tester.getTopLeft(todo).dx, lessThan(tester.getTopLeft(downloaded).dx));
          } else {
            expect(tester.getTopLeft(todo).dy, lessThan(tester.getTopLeft(downloaded).dy));
          }
          expect(tester.takeException(), isNull);
          if (output.isNotEmpty && width == 746) {
            await tester.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
              final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
              await File('$output-$language-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      }
    }
    await tester.tap(find.text('Add New Todo'.tr));
    expect((controller as _Tools).additions, 1);
    await tester.tap(find.byTooltip('Refresh'.tr));
    expect(controller.refreshes, 1);
    video.content = '✔︎ ABP-123';
    controller.todoList.refresh();
    await tester.pumpAndSettle();
    expect(find.descendant(of: downloaded, matching: find.text('ABP-123')), findsOneWidget);
    expect(find.descendant(of: todo, matching: find.text('ABP-123')), findsNothing);
    await tester.tap(find.descendant(of: todo, matching: find.byTooltip('Delete'.tr)));
    await tester.pumpAndSettle();
    expect(find.text('No pending todos'.tr), findsOneWidget);
    controller.todoList.clear();
    await tester.pumpAndSettle();
    expect(find.text('TODO'), findsOneWidget);
    expect(find.text('DOWNLOADED'), findsOneWidget);
    expect(find.text('No downloaded todos yet'.tr), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
