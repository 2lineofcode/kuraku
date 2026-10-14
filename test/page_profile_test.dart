import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:kuraku/app/core/app_color.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/db_gamification.dart';
import 'package:kuraku/app/data/database/db_profile.dart';
import 'package:kuraku/app/data/models/profile_entity.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
import 'package:kuraku/app/modules/home/home_view.dart';
import 'package:kuraku/app/modules/home/page_profile/page_profile_controller.dart';
import 'package:kuraku/app/modules/home/page_profile/page_profile_view.dart';
import 'package:kuraku/app/modules/widgets/widget_style.dart';
import 'package:sqflite/sqflite.dart';

class _Preferences implements GetSecureStorage {
  int? accent;
  @override
  T? read<T>(String key) => (key == '_kAppAccent' ? accent : null) as T?;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home extends HomeController {
  bool failLoad = false;
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  Future<void> refreshProfile() async {
    if (failLoad) throw StateError('Load failed');
  }
  @override
  void onClose() {
    tecTopNavSearch.dispose();
    fnTopNavSearch.dispose();
  }
}

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  bool failSave = false;
  bool missing = false;
  Completer<void>? pending;
  final writes = <Map<String, Object?>>[];
  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(table, 'profile');
    expect(where, 'id = ?');
    expect(whereArgs, ['1']);
    if (failSave) throw StateError('Write failed');
    if (missing) return 0;
    writes.add(values);
    await pending?.future;
    return 1;
  }
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [{'cnt': 49}];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Home home;
  late _Database database;
  late PageProfileController controller;
  setUp(() {
    database = _Database();
    Get.put<DBService>(_Service()..dbMain = database);
    home = _Home();
    Get.put<HomeController>(home);
    home.profile.value = Profile(id: '1', name: 'PA', createdAt: '2026-07-18 12:00:00', totalWatchDuration: 37680);
    home.totalVideo.value = 465;
    home.streakDays.value = 3;
    home.achievementCount.value = 1;
    home.latestAchievementTitles.assignAll(['First Steps']);
    home.achievementProgress.assignAll([
      AchievementProgress(key: 'first', title: 'First Steps', description: 'Start building your collection.', group: 'Collection', currentValue: 465, targetValue: 1, isUnlocked: true, unlockedAt: '2026-07-18 12:00:00'),
      AchievementProgress(key: 'watch', title: 'Night Owl', description: 'Watch videos for 50 hours.', group: 'Watch', currentValue: 10, targetValue: 50, isUnlocked: false, unlockedAt: ''),
    ]);
    controller = Get.put(PageProfileController());
  });
  tearDown(Get.reset);

  testWidgets('Footer opens the profile page and editing validates, cancels and saves without replacing stats', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: Column(children: [
      Expanded(child: Obx(() => home.currentMenuSelected.value == kMenuProfile ? const HomeView().bodyContent() : const Text('Home'))),
      const HomeView().footerContent(),
    ]))));
    await tester.tap(find.text('PA'));
    await tester.pumpAndSettle();
    expect(home.currentMenuSelected.value, kMenuProfile);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.text('10h 28m'), findsOneWidget);
    expect(find.text('49 times'), findsOneWidget);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await tester.enterText(find.byType(CupertinoTextField), '   ');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your name.'), findsOneWidget);
    expect(database.writes, isEmpty);
    await tester.enterText(find.byType(CupertinoTextField), 'Discarded');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(home.profile.value.name, 'PA');
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(controller.isEditing.value, isFalse);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), '  New name  ');
    database.failSave = true;
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save your name. Please try again.'), findsOneWidget);
    expect(home.profile.value.name, 'PA');
    database.failSave = false;
    database.pending = Completer<void>();
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await controller.saveName();
    expect(database.writes, hasLength(1));
    expect(tester.widget<CupertinoDialogAction>(find.widgetWithText(CupertinoDialogAction, 'Cancel')).onPressed, isNull);
    await Navigator.of(tester.element(find.byType(CupertinoAlertDialog))).maybePop();
    await tester.pump();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    database.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('New name'), findsNWidgets(2));
    expect(find.text('Profile saved'), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(home.profile.value.totalWatchDuration, 37680);
    expect(database.writes.single.keys, unorderedEquals(['name', 'updated_at']));
    expect(database.writes.single['name'], 'New name');
    expect(home.currentMenuSelected.value, kMenuProfile);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Profile handles load errors, narrow windows and achievements', (tester) async {
    home.failLoad = true;
    await home.onOpenProfile();
    await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: PageProfileView())));
    expect(find.text('Retry'), findsOneWidget);
    home.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    for (final width in [1000.0, 360.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('First Steps'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Unlocked Jul 18, 2026'), findsOneWidget);
      expect(find.text('10/50 · In progress'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Compact profile supports both themes, long names and empty achievements', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    home.profile.value = Profile(name: 'A long display name that should wrap in a narrow profile header');
    for (final brightness in [Brightness.dark, Brightness.light]) {
      for (final width in [320.0, 640.0, 1000.0]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpWidget(GetMaterialApp(theme: ThemeData(brightness: brightness), home: const Scaffold(body: PageProfileView())));
        await tester.pumpAndSettle();
        expect(find.text(home.profile.value.name!), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Edit profile'));
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoTextField), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    }
    home.achievementProgress.clear();
    home.latestAchievementTitles.clear();
    home.achievementCount.value = 0;
    home.totalVideo.value = 0;
    await tester.pumpAndSettle();
    expect(find.text('No achievements yet. Your progress will appear here.'), findsOneWidget);
    expect(find.text('0 of 0 unlocked'), findsOneWidget);
    expect(find.text('Noobless'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Gamification shows level rewards, filters milestones and jumps to next goals', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(360, 900));
    home.achievementProgress.add(AchievementProgress(key: 'studio_3', title: 'Studio Sampler',
      description: 'Collect videos from 3 different studios.', group: 'Exploration', currentValue: 2,
      targetValue: 3, isUnlocked: false, unlockedAt: '', xp: 100, unit: 'studios'));
    home.gamification.value = GamificationSummary(streakDays: 3, latestAchievements: [], newAchievementTitles: [],
      stats: {'studios': 2, 'actresses': 5, 'categories': 3, 'favorites': 10, 'playlists': 1},
      progress: [AchievementProgress(key: 'level', title: 'Level', description: '', group: 'Collection',
        currentValue: 1, targetValue: 1, isUnlocked: true, unlockedAt: '', xp: 550)]);
    await tester.pumpWidget(GetMaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: PageProfileView())));
    expect(find.text('Level 2'), findsOneWidget);
    expect(find.text('Rising Curator'), findsOneWidget);
    expect(find.text('50/500 XP · Next level: 3'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('View goals'), 250, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('View goals'));
    await tester.pumpAndSettle();
    expect(controller.achievementGroup.value, 'Exploration');
    expect(controller.achievementFilter.value, 'In progress');
    expect(find.text('2/3 studios · In progress'), findsOneWidget);
    expect(find.text('10/50 · In progress'), findsNothing);
    expect(find.text('Unlocked Jul 18, 2026'), findsNothing);
    await tester.tap(find.text('Unlocked'));
    await tester.pumpAndSettle();
    expect(find.text('No milestones in this filter.'), findsOneWidget);
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();
    expect(find.text('Unlocked Jul 18, 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Gamification foreground stays readable with default and custom accents in both themes', (tester) async {
    final preferences = _Preferences();
    final service = Get.put(AppSettingService()..pref = preferences);
    addTearDown(service.onClose);
    home.achievementProgress.add(AchievementProgress(key: 'studio_3', title: 'Studio Sampler',
      description: 'Collect videos from 3 different studios.', group: 'Exploration', currentValue: 2,
      targetValue: 3, isUnlocked: false, unlockedAt: '', xp: 100, unit: 'studios'));
    for (final brightness in Brightness.values) {
      for (final accent in [AppColor.defaultAccent(brightness), const Color(0xffdce6f5), const Color(0xff202c43),
        Colors.white, Colors.black, Colors.red, const Color(0x30205080)]) {
        preferences.accent = accent.toARGB32();
        final theme = AppStyle.theme(brightness);
        await tester.pumpWidget(GetMaterialApp(theme: theme,
          home: const Scaffold(body: PageProfileView())));
        await tester.pumpAndSettle();
        final rank = tester.widget<Text>(find.text('New Explorer'));
        final icons = tester.widgetList<HugeIcon>(find.byType(HugeIcon)).where((icon) => icon.size == 28);
        final bars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
        expect(AppColor.accent.toARGB32(), accent.toARGB32());
        if ((brightness == Brightness.dark && accent == Colors.white) || (brightness == Brightness.light && accent == Colors.black)) {
          expect(rank.style!.color, accent);
        }
        expect(icons.single.color, rank.style!.color);
        expect(bars.first.color, rank.style!.color);
        final labels = tester.widgetList<Text>(find.text('+100 XP'));
        expect(labels.single.style!.color, rank.style!.color);
        for (final background in [AppColor.body, AppColor.panel, AppColor.hover, theme.colorScheme.surface]) {
          final a = Color.alphaBlend(rank.style!.color!, background).computeLuminance();
          final b = background.computeLuminance();
          expect(a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05), greaterThanOrEqualTo(4.5),
            reason: '$brightness / $accent');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  test('Name updates reject empty input and a missing profile', () async {
    await expectLater(DBProfile.updateName(' '), throwsArgumentError);
    database.missing = true;
    await expectLater(DBProfile.updateName('Name'), throwsStateError);
    expect(database.writes, isEmpty);
  });
}
