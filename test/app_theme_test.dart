import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/core/app_color.dart';
import 'package:javit/app/modules/widgets/widget_base_layout.dart';
import 'package:javit/app/modules/widgets/widget_media_stack.dart';
import 'package:javit/app/modules/widgets/widget_style.dart';
import 'package:javit/app/modules/widgets/widget_surfaces.dart';

void main() {
  testWidgets('Cupertino filled buttons keep white labels across themes', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(MaterialApp(theme: AppStyle.theme(brightness), home: Scaffold(
        body: CupertinoButton.filled(onPressed: () {}, child: const Text('Capture')),
      )));
      await tester.pumpAndSettle();
      final context = tester.element(find.text('Capture'));
      expect(DefaultTextStyle.of(context).style.color, CupertinoColors.white);
      expect(CupertinoTheme.of(context).primaryColor, CupertinoColors.activeBlue.resolveFrom(context));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Cupertino dialog actions use native colors instead of app accent', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(MaterialApp(theme: AppStyle.theme(brightness), home: AppConfirmDialog(
        title: const Text('New'), actions: [
          AppDialogAction(child: const Text('Submit'), onPressed: () {}),
          AppDialogAction(isDestructiveAction: true, child: const Text('Delete'), onPressed: () {}),
        ],
      )));
      await tester.pumpAndSettle();
      final context = tester.element(find.text('Submit'));
      final color = DefaultTextStyle.of(context).style.color;
      expect(color, CupertinoColors.activeBlue.resolveFrom(context));
      expect(color, isNot(Theme.of(context).colorScheme.primary));
      final destructiveContext = tester.element(find.text('Delete'));
      expect(DefaultTextStyle.of(destructiveContext).style.color, CupertinoColors.systemRed.resolveFrom(destructiveContext));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Theme changes update content and selection while media stays readable', (tester) async {
    addTearDown(Get.reset);
    await tester.pumpWidget(GetMaterialApp(
      theme: AppStyle.theme(Brightness.light), darkTheme: AppStyle.theme(Brightness.dark), themeMode: ThemeMode.dark,
      home: Builder(builder: (context) {
        AppColor.dependOn(context);
        return MyLayout(
        appBarTitle: const Text('Explore'),
        sideMenuContent: const Text('Navigation'),
        footerContent: const Text('Status'),
        bodyContent: Column(children: [
          Container(key: const Key('selection'), color: AppColor.selected, child: const Text('Selected')),
          const MediaStack([Text('Media title'), Positioned(right: 0, child: Icon(CupertinoIcons.play_fill))]),
        ]),
      );
      }),
    ));
    for (final mode in [ThemeMode.dark, ThemeMode.light, ThemeMode.dark]) {
      Get.changeThemeMode(mode);
      await tester.pumpAndSettle();
      expect(AppColor.body.computeLuminance() > .5, mode == ThemeMode.light);
      expect(find.byWidgetPredicate((widget) => widget is ColoredBox && widget.color == AppColor.body), findsWidgets);
      for (final background in [AppColor.body, AppColor.panel, AppColor.container, AppColor.selected]) {
        for (final foreground in [AppColor.text, AppColor.muted]) {
          final a = foreground.computeLuminance(), b = background.computeLuminance();
          final contrast = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
          expect(contrast, greaterThanOrEqualTo(4.5));
        }
      }
      expect(tester.widget<Container>(find.byKey(const Key('selection'))).color, AppColor.selected);
      expect(DefaultTextStyle.of(tester.element(find.text('Media title'))).style.color, Colors.white);
      expect(IconTheme.of(tester.element(find.byIcon(CupertinoIcons.play_fill))).color, Colors.white);
      expect(tester.takeException(), isNull);
    }
  });
}
