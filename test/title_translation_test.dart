// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuraku/app/modules/widgets/widget_title_translation.dart';
import 'package:overlayment/overlayment.dart';

void main() {
  Future<void> pump(WidgetTester tester, String title) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: Text('Home'))));
    unawaited(Overlayment.show(OverPanel(
      alignment: Alignment.centerRight, width: 300, color: Colors.black,
      child: Center(child: TitleTranslation(title: title, child: const Text('Video title'))),
    ), context: Get.context));
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.byType(TitleTranslation)));
    addTearDown(() async {
      if (navigator.mounted && navigator.canPop()) {
        navigator.pop();
        await tester.pumpAndSettle();
      }
      while (Overlayment.count > 0) {
        unawaited(Overlayment.dismissLast());
        await tester.pumpAndSettle();
      }
    });
  }

  tearDown(Get.reset);

  for (final title in ['Waiting for you', 'あなたを待っています', 'Waktu Yang Dinanti']) {
    testWidgets('translates $title only on long press', (tester) async {
      final response = Completer<http.Response>();
      final requests = <http.Request>[];
      await http.runWithClient(() async {
        await pump(tester, title);
        await tester.tap(find.text('Video title'));
        await tester.pump();
        expect(requests, isEmpty);

        await tester.longPress(find.text('Video title'));
        await tester.pumpAndSettle();
        expect(find.text('Translating...'), findsOneWidget);
        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(requests.single.url.queryParameters['q'], title);
        expect(requests.single.url.queryParameters['sl'], 'auto');
        expect(requests.single.url.queryParameters['tl'], 'id');

        response.complete(http.Response(jsonEncode([
          [['Waktu Yang Dinanti', title]], null, 'en',
        ]), 200, headers: {'content-type': 'application/json; charset=utf-8'}));
        await tester.pumpAndSettle();
        expect(find.text('Waktu Yang Dinanti').hitTestable(), findsOneWidget, reason: 'the translation must appear above the OverPanel');
        expect(tester.getSize(find.byType(SingleChildScrollView)).width, 300);
        expect(Overlayment.count, 1);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.text('Waktu Yang Dinanti'), findsNothing);
        expect(Overlayment.count, 1);
      }, () => MockClient((request) {
        requests.add(request);
        return response.future;
      }));
    });
  }

  testWidgets('shows an error when translation fails', (tester) async {
    await http.runWithClient(() async {
      await pump(tester, 'Waiting for you');
      await tester.longPress(find.text('Video title'));
      await tester.pumpAndSettle();
      expect(find.text('Unable to translate title. Try again.'), findsOneWidget);
    }, () => MockClient((_) async => http.Response('Unavailable', 503)));
  });

  testWidgets('opens the popup with the full multiline translation without clipping', (tester) async {
    final response = Completer<http.Response>();
    const translated = 'Waktu yang dinanti akhirnya tiba setelah perjalanan panjang, membawa cerita baru dan kenangan yang indah untuk semua orang.';
    await http.runWithClient(() async {
      await pump(tester, 'Waiting for you');
      await tester.longPress(find.text('Video title'));
      await tester.pumpAndSettle();
      expect(find.text('Translating...'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
      response.complete(http.Response(jsonEncode([
        [[translated, 'Waiting for you']], null, 'en',
      ]), 200));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final text = tester.getRect(find.text(translated));
      expect(text.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(viewport.width, greaterThanOrEqualTo(290));
      expect(viewport.right, lessThanOrEqualTo(tester.view.physicalSize.width));
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) => response.future));
  });

  testWidgets('ignores empty titles', (tester) async {
    await pump(tester, '  ');
    await tester.longPress(find.text('Video title'));
    await tester.pumpAndSettle();
    expect(Overlayment.count, 1);
  });

  testWidgets('times out and safely finishes after the popup is dismissed', (tester) async {
    final response = Completer<http.Response>();
    await http.runWithClient(() async {
      await pump(tester, 'Waiting for you');
      await tester.longPress(find.text('Video title'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('Unable to translate title. Try again.'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      response.complete(http.Response('Unavailable', 503));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(Overlayment.count, 1);
    }, () => MockClient((_) => response.future));
  });

  testWidgets('does not open a popup if the panel closes while translating', (tester) async {
    final response = Completer<http.Response>();
    await http.runWithClient(() async {
      await pump(tester, 'Waiting for you');
      await tester.longPress(find.text('Video title'));
      await tester.pumpAndSettle();
      unawaited(Overlayment.dismissLast());
      await tester.pumpAndSettle();
      response.complete(http.Response('Unavailable', 503));
      await tester.pumpAndSettle();
      expect(find.text('Unable to translate title. Try again.'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(Get.key.currentState!.canPop(), isFalse);
    }, () => MockClient((_) => response.future));
  });
}
