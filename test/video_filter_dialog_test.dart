import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/utils/helper_opener.dart';

const adapter = VideoFilterAdapter<String>(
  videoCode: code,
  actresses: names,
  categories: names,
  releaseDate: date,
);
String code(String value) => value;
Iterable<String> names(String value) => [value];
String? date(String value) => null;

void main() {
  tearDown(Get.reset);

  test('empty filters preserve undated videos; reset retains loaded options', () {
    final state = VideoFilterState();
    state.categories.add('Category');
    state.actresses.add('Actress');
    expect(state.apply(['ABC'], adapter), ['ABC']);
    expect(state.isFiltered.value, isFalse);
    state.tecVideoCode.text = ' abc ';
    expect(state.apply(['ABC', 'DEF'], adapter), ['ABC']);
    state.currentRange.value = const RangeValues(2020, 2021);
    expect(state.apply(['ABC'], adapter), isEmpty);
    state.reset();
    expect(state.categories, ['Category']);
    expect(state.actresses, ['Actress']);
    expect(state.hasFilters, isFalse);
  });

  testWidgets('filter drafts cancel, reset, apply and reject stale tabs', (tester) async {
    final state = VideoFilterState();
    state.actresses.add('Actress');
    state.categories.addAll(List.generate(20, (index) => 'Category $index'));
    state.tecVideoCode.text = 'ABC';
    state.isFiltered.value = true;
    final videos = ['ABC'].obs;
    var available = true;
    Future<void>? dialog;
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: TextButton(
      onPressed: () {
        dialog = HelperOpener.openFilterDialog(
          state: state,
          allVideos: ['ABC', 'DEF'],
          videos: videos,
          adapter: adapter,
          isAvailable: () => available,
        );
      },
      child: const Text('Open'),
    ))));
    Future<void> open() async {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }
    final field = find.byWidgetPredicate((widget) => widget is CupertinoTextField && widget.placeholder == 'Contains video code...');
    await open();
    await tester.enterText(field, 'DEF');
    expect(state.tecVideoCode.text, 'ABC');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await dialog;
    expect(state.tecVideoCode.text, 'ABC');
    expect(videos, ['ABC']);

    await open();
    await tester.tap(find.text('Reset'));
    expect(state.tecVideoCode.text, 'ABC');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await dialog;
    expect(state.hasFilters, isFalse);
    expect(state.isFiltered.value, isFalse);
    expect(videos, ['ABC', 'DEF']);

    await open();
    await tester.enterText(field, ' DEF ');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await dialog;
    expect(state.tecVideoCode.text, 'DEF');
    expect(videos, ['DEF']);

    await open();
    await tester.enterText(field, 'ABC');
    available = false;
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await dialog;
    expect(state.tecVideoCode.text, 'DEF');
    expect(videos, ['DEF']);

    available = true;
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    state.categoriesSelected.assignAll(state.categories);
    await open();

    expect(tester.takeException(), isNull);
    expect(find.text('Apply').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await dialog;
  });
}
