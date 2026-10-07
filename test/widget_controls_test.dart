import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/core/app_color.dart';
import 'package:javit/app/modules/widgets/widget_controls.dart';
import 'package:javit/app/modules/widgets/widget_style.dart';
import 'package:javit/app/modules/widgets/widget_surfaces.dart';

import '../tool/ui_catalog_flutter.dart';

void main() {
  tearDown(() => Get.reset());

  testWidgets('success foreground stays readable on light and dark surfaces', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(GetMaterialApp(key: ValueKey(brightness), theme: AppStyle.theme(brightness),
        home: const Scaffold(body: SizedBox.shrink())));
      await tester.pumpAndSettle();
      final foreground = AppColor.success.computeLuminance();
      for (final background in [AppColor.body, AppColor.panel, AppColor.selected,
        Color.alphaBlend(const Color(0x3322C55E), AppColor.container),
        Color.alphaBlend(const Color(0x3310B981), AppColor.hover)]) {
        final luminance = background.computeLuminance();
        final contrast = foreground > luminance
            ? (foreground + .05) / (luminance + .05) : (luminance + .05) / (foreground + .05);
        expect(contrast, greaterThanOrEqualTo(4.5), reason: '$brightness on $background');
      }
    }
  });

  testWidgets('shared controls keep constraints, disabled actions and input behavior', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var presses = 0;
    String? submitted;
    await tester.pumpWidget(GetMaterialApp(theme: AppStyle.theme(Brightness.light), home: Scaffold(body: Column(children: [
      AppButton(label: 'Save', onPressed: () => presses++),
      const AppButton(label: 'Disabled', variant: AppButtonVariant.filled, onPressed: null),
      AppButton(label: 'Custom', onPressed: () {}, style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.black, minimumSize: const Size(0, 36))),
      AppIconButton(tooltip: 'Compact action', icon: const Icon(Icons.add), onPressed: () {},
        style: IconButton.styleFrom(minimumSize: const Size(28, 28), maximumSize: const Size(28, 28))),
      AppIconButton(tooltip: 'Small action', constraints: const BoxConstraints.tightFor(width: 24, height: 24),
        icon: const Icon(Icons.add), onPressed: () => presses++),
      AppTextField(controller: controller, obscureText: true, autocorrect: false,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly], onSubmitted: (value) => submitted = value),
    ]))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AppTextField)).height, 32);
    expect(tester.widget<CupertinoTextField>(find.byType(CupertinoTextField)).style!.fontSize, 12);
    expect(tester.getSize(find.byType(AppButton).first).height, greaterThanOrEqualTo(AppStyle.controlHeight));
    expect(tester.getSize(find.byType(AppIconButton).last), const Size(24, 24));
    expect(tester.getSize(find.byTooltip('Compact action')), const Size(28, 28));
    final custom = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Custom'));
    expect(custom.style!.foregroundColor!.resolve({}), Colors.white);
    expect(custom.style!.backgroundColor!.resolve({}), Colors.black);
    expect(tester.getSize(find.widgetWithText(AppButton, 'Custom')).height, 36);
    final disabled = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(disabled.style!.backgroundColor!.resolve({WidgetState.disabled}),
      isNot(disabled.style!.backgroundColor!.resolve({})));
    await tester.tap(find.text('Disabled'));
    expect(presses, 0);
    await tester.tap(find.text('Save'));
    await tester.tap(find.byTooltip('Small action'));
    expect(presses, 2);
    await tester.enterText(find.byType(AppTextField), '12ab34');
    expect(controller.text, '1234');
    expect(tester.widget<CupertinoTextField>(find.byType(CupertinoTextField)).obscureText, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, '1234');
  });

  testWidgets('dropdown defaults align with text fields and keep selection accessible', (tester) async {
    tester.view.physicalSize = const Size(700, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final scale in [1.0, 1.5]) {
        var choice = 'Balanced';
        const items = [DropdownMenuItem(value: 'Balanced', child: Text('Balanced')),
          DropdownMenuItem(value: 'Broad', child: Text('Broad'))];
        await tester.pumpWidget(GetMaterialApp(theme: AppStyle.theme(brightness), home: MediaQuery(
          data: MediaQueryData(size: const Size(700, 600), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: StatefulBuilder(builder: (context, setState) => Column(children: [
            Row(children: [
              const Expanded(child: AppTextField(placeholder: 'Search')),
              Expanded(child: AppDropdown<String>(value: choice, isExpanded: true, items: items,
                onChanged: (value) => setState(() => choice = value!))),
              Expanded(child: AppDropdownFormField<String>(initialValue: 'Balanced', items: items, onChanged: (_) {})),
            ]),
            const AppDropdown<String>(value: 'Balanced', items: items, onChanged: null),
          ]))),
        )));
        await tester.pumpAndSettle();
        final fieldHeight = tester.getSize(find.byType(AppTextField)).height;
        for (final dropdown in [find.byType(AppDropdown<String>).first, find.byType(AppDropdownFormField<String>)]) {
          expect(tester.getSize(dropdown).height, scale == 1 ? fieldHeight : greaterThanOrEqualTo(32));
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(AppDropdown<String>).first);
        await tester.pump();
        expect(find.byType(MenuItemButton), findsNWidgets(2));
        final menuSize = tester.getSize(find.byType(MenuItemButton).last);
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.getSize(find.byType(MenuItemButton).last), menuSize);
        await tester.tap(find.text('Broad').last);
        await tester.pump();
        expect(choice, 'Broad');
        expect(find.byType(MenuItemButton), findsNothing);
        await tester.tap(find.byType(AppDropdown<String>).first);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.byType(MenuItemButton), findsNothing);
        expect(tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>).last).onChanged, isNull);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('real gallery renders across themes, narrow widths and text scaling', (tester) async {
    Get.testMode = true;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const font = String.fromEnvironment('VISUAL_QA_FONT');
    const output = String.fromEnvironment('UI_QA_PATH');
    if (font.isNotEmpty) {
      await tester.runAsync(() async {
        await (FontLoader('VisualQA')..addFont(File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
        await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
    }
    final boundary = GlobalKey();
    for (final dark in [false, true]) {
      for (final width in [900.0, 360.0]) {
        tester.view.physicalSize = Size(width, 980);
        final theme = AppStyle.theme(dark ? Brightness.dark : Brightness.light);
        await tester.pumpWidget(GetMaterialApp(theme: theme.copyWith(
          textTheme: font.isEmpty ? theme.textTheme : theme.textTheme.apply(fontFamily: 'VisualQA'),
          chipTheme: font.isEmpty ? theme.chipTheme : theme.chipTheme.copyWith(labelStyle: theme.chipTheme.labelStyle?.copyWith(fontFamily: 'VisualQA')),
        ), home: MediaQuery(data: MediaQueryData(size: Size(width, 980), textScaler: TextScaler.linear(width == 360 ? 1.5 : 1)),
          child: RepaintBoundary(key: boundary, child: UiCatalog(key: ValueKey('$dark-$width'))),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (output.isNotEmpty && width == 900) {
          await tester.runAsync(() async {
            final rendered = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
            final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
            await File('$output-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
            rendered.dispose();
          });
        }
        await tester.ensureVisible(find.text('Validate form'));
        await tester.tap(find.text('Validate form'));
        await tester.pumpAndSettle();
        expect(find.text('Name is required'), findsOneWidget);
        await tester.enterText(find.byType(AppTextFormField), 'Adit');
        await tester.tap(find.text('Validate form'));
        await tester.pumpAndSettle();
        expect(find.text('Name is required'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('dialog scrolls long content and wraps actions on a narrow window', (tester) async {
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GetMaterialApp(theme: AppStyle.theme(Brightness.dark), home: Scaffold(body: Builder(builder: (context) => AppButton(
      label: 'Open', onPressed: () => showDialog<void>(context: context, builder: (context) => AppDialog(
        title: const Text('Review changes'), content: Text(List.filled(100, 'Long content').join('\n')),
        actions: [AppButton(label: 'Cancel and return', onPressed: () => Navigator.pop(context)),
          AppButton(label: 'Save all changes', variant: AppButtonVariant.filled, onPressed: () => Navigator.pop(context))],
      )),
    )))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel and return'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
