import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:javit/app/core/app_color.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/modules/home/home_controller.dart';
import 'package:javit/app/modules/home/home_view.dart';
import 'package:javit/app/modules/widgets/widget_controls.dart';
import 'package:javit/app/modules/widgets/widget_search_tab_bar.dart';
import 'package:javit/app/modules/widgets/widget_style.dart';

import 'icon_finder.dart';

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  void onReady() {}
  @override
  void onClose() { tecTopNavSearch.dispose(); fnTopNavSearch.dispose(); }
}

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

double _contrast(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  testWidgets('custom accents keep controls, selection and semantic text readable', (tester) async {
    Get.testMode = true;
    final preferences = _Preferences();
    final service = Get.put(AppSettingService()..pref = preferences);
    final home = Get.put<HomeController>(_Home());
    home.sideMenuWidth.value = 65;
    home.currentMenuSelected.value = kMenuSetting;
    final scroll = ScrollController();
    addTearDown(() { service.onClose(); scroll.dispose(); Get.reset(); });
    for (final brightness in Brightness.values) {
      for (final value in [null, 0xff000000, 0xffffffff, 0xffff0000, 0xff00ff00, 0xff0000ff,
        0xffffff00, 0xff00ffff, 0xffff00ff, 0xffdc00ff, 0xff205080, 0x80205080, 0x80ffffff, 0x01000000, 0]) {
        preferences.values['_kAppAccent'] = value;
        await tester.pumpWidget(GetMaterialApp(key: ValueKey('$brightness-$value'),
          theme: AppStyle.theme(brightness), home: Scaffold(body: Row(children: [
            SizedBox(width: 65, child: Column(children: [Builder(builder: (context) {
              AppColor.dependOn(context);
              return const HomeView().sideMenuContent();
            })])),
            Expanded(child: Column(children: [
            SearchTabBar(tabs: const [(id: 0, title: 'Selected', isLoading: false, isPinned: false),
              (id: 1, title: 'Idle', isLoading: false, isPinned: false)],
              activeIndex: 0, scrollController: scroll, onSelect: (_) {}, onClose: (_) {},
              onAdd: () {}, onReorder: (_, _) {}, onPin: (_) {}),
            const AppTextField(placeholder: 'Search'),
            AppButton(label: 'Save', variant: AppButtonVariant.filled, onPressed: () {}),
            AppButton(label: 'Tonal', variant: AppButtonVariant.tonal, onPressed: () {}),
            AppIconButton(icon: const Icon(Icons.add), filled: true, onPressed: () {}),
          ])),
          ])),
        ));
        await tester.pumpAndSettle();
        final scheme = Get.theme.colorScheme;
        final sidebar = find.ancestor(of: findHugeIcon(HugeIcons.strokeRoundedSettings01),
          matching: find.byWidgetPredicate((widget) => widget is Container && widget.decoration is BoxDecoration));
        final decoration = tester.widget<Container>(sidebar.first).decoration! as BoxDecoration;
        expect(decoration.color, AppColor.selected);
        expect(AppColor.accent, value == null ? AppColor.defaultAccent(brightness) : Color(value));
        expect(preferences.values['_kAppAccent'], value);
        expect(AppColor.selected.a, 1);
        if (value == 0xffdc00ff) {
          expect(AppColor.selected, isNot(AppColor.defaultAccent(brightness)));
          expect(AppColor.selected.r, greaterThan(AppColor.selected.g));
          expect(AppColor.selected.b, greaterThan(AppColor.selected.g));
        }
        expect(_contrast(AppColor.selected, AppColor.container), greaterThanOrEqualTo(1.1));
        for (final surface in [AppColor.body, AppColor.panel, AppColor.container, AppColor.hover,
          AppColor.appBar, AppColor.footer, AppColor.selected, scheme.surface, scheme.surfaceContainerHighest]) {
          expect(_contrast(scheme.primary, surface), greaterThanOrEqualTo(4.5), reason: '$brightness $value on $surface');
        }
        for (final foreground in [AppColor.text, AppColor.muted, AppColor.success, scheme.error, AppColor.accentForeground]) {
          expect(_contrast(foreground, AppColor.selected), greaterThanOrEqualTo(4.5), reason: '$brightness $value selected $foreground');
        }
        expect(_contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5));
        expect(_contrast(AppColor.onSelected, AppColor.selected), greaterThanOrEqualTo(4.5));
        final selected = tester.element(find.text('Selected'));
        expect(_contrast(DefaultTextStyle.of(selected).style.color!, AppColor.selected), greaterThanOrEqualTo(4.5));
        expect(_contrast(AppColor.text, Get.theme.textSelectionTheme.selectionColor!), greaterThanOrEqualTo(4.5));
        expect(_contrast(Get.theme.chipTheme.labelStyle!.color!, Get.theme.chipTheme.selectedColor!), greaterThanOrEqualTo(4.5));
        final field = tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
        expect(_contrast(field.cursorColor!, field.decoration!.color!), greaterThanOrEqualTo(4.5));
        for (final label in ['Save', 'Tonal']) {
          final button = tester.widget<ButtonStyleButton>(find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()).first);
          final foreground = button.style!.foregroundColor!.resolve({})!;
          final background = Color.alphaBlend(button.style!.backgroundColor!.resolve({})!, AppColor.body);
          expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5));
        }
        final button = tester.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.add), matching: find.byType(IconButton)).first);
        expect(_contrast(button.style!.foregroundColor!.resolve({})!, button.style!.backgroundColor!.resolve({})!), greaterThanOrEqualTo(4.5));
        expect(tester.takeException(), isNull);
      }
    }
  });
}
