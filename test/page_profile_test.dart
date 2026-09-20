import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/db_gamification.dart';
import 'package:javit/app/data/database/db_profile.dart';
import 'package:javit/app/data/models/profile_entity.dart';
import 'package:javit/app/modules/home/home_controller.dart';
import 'package:javit/app/modules/home/home_view.dart';
import 'package:javit/app/modules/home/page_profile/page_profile_controller.dart';
import 'package:javit/app/modules/home/page_profile/page_profile_view.dart';
import 'package:sqflite/sqflite.dart';

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
    await tester.tap(find.text('👋🏻 PA'));
    await tester.pumpAndSettle();
    expect(home.currentMenuSelected.value, kMenuProfile);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('10h 28m'), findsOneWidget);
    expect(find.text('49 times'), findsOneWidget);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your name.'), findsOneWidget);
    expect(database.writes, isEmpty);
    await tester.enterText(find.byType(TextField), 'Discarded');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(home.profile.value.name, 'PA');
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  New name  ');
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
    database.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('👋🏻 New name'), findsOneWidget);
    expect(find.text('Profile saved'), findsOneWidget);
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

  test('Name updates reject empty input and a missing profile', () async {
    await expectLater(DBProfile.updateName(' '), throwsArgumentError);
    database.missing = true;
    await expectLater(DBProfile.updateName('Name'), throwsStateError);
    expect(database.writes, isEmpty);
  });
}
