import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/modules/widgets/widget_download_method.dart';

void main() {
  testWidgets('download choices stay ordered and return their selection', (tester) async {
    String? selected;
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(
      body: Center(child: DownloadMethodDialog(onSelected: (method) => selected = method)),
    )));
    for (final option in const {'Native': 'native', 'Downie': 'downie', 'Just Open URL': 'url'}.entries) {
      await tester.tap(find.text(option.key));
      expect(selected, option.value);
    }
    expect(tester.getTopLeft(find.text('Native')).dy, lessThan(tester.getTopLeft(find.text('Downie')).dy));
    expect(tester.getTopLeft(find.text('Downie')).dy, lessThan(tester.getTopLeft(find.text('Just Open URL')).dy));
    await tester.tap(find.text('Cancel'));
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
    Get.reset();
  });
}
