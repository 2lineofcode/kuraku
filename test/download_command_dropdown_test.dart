import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/modules/home/page_download/page_download_command_dropdown.dart';
import 'package:javit/app/modules/home/page_download/page_download_helper.dart';

void main() {
  tearDown(Get.reset);

  testWidgets('commands stay compact and keep keyboard selection visible in a short window', (tester) async {
    tester.view.physicalSize = const Size(320, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? picked;
    Future<void> show(int selected, {List<PageDownloadCommand>? commands}) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 280, child: DownloadCommandDropdown(
          commands: commands ?? PageDownloadCommandEngine.commands,
          selectedIndex: selected,
          onPick: (command) => picked = command,
        )),
      ))));
      await tester.pumpAndSettle();
    }

    await show(0);
    expect(tester.getSize(find.byType(DownloadCommandDropdown)).height, lessThanOrEqualTo(184));
    expect(find.text('JavMost'), findsOneWidget);
    expect(find.text('↑ ↓ Navigate · ↵ Select · Esc Close'), findsOneWidget);
    await show(6);
    expect(find.text('JavHey'), findsOneWidget);
    expect(find.text('/javhey').hitTestable(), findsOneWidget);
    await show(5);
    expect(find.text('/search').hitTestable(), findsOneWidget);
    await tester.tap(find.text('/search'));
    expect(picked, '/search');
    await show(0);
    expect(find.text('/new-release').hitTestable(), findsOneWidget);
    await show(0, commands: PageDownloadCommandEngine.byPrefix('/ja'));
    expect(find.text('JavHey'), findsOneWidget);
    expect(find.text('JavMost'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
