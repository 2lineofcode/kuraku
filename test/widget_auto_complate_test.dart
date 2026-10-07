import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/modules/widgets/widget_auto_complate.dart';

void main() {
  late TextEditingController controller;

  setUp(() => controller = TextEditingController());
  tearDown(() => controller.dispose());

  Future<void> pump(
    WidgetTester tester, {
    List<String> items = const ['Drama', 'Cosplay', 'Big Tits', 'drama school'],
    String? placeHolder,
    String? emptyText,
    double? maxHeight,
    void Function(String)? onSelected,
    Widget Function(BuildContext, TextEditingController, FocusNode)? fieldBuilder,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 320,
            child: ExAutoComplate(
              items: items,
              controller: controller,
              placeHolder: placeHolder,
              emptyText: emptyText,
              maxHeight: maxHeight,
              onSelected: onSelected,
              fieldBuilder: fieldBuilder,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders a cupertino field with the default placeholder', (tester) async {
    await pump(tester);

    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(tester.widget<CupertinoTextField>(find.byType(CupertinoTextField)).placeholder, 'Search...');
    expect(find.text('Drama'), findsNothing, reason: 'suggestions stay closed until the user types');
  });

  testWidgets('uses the given placeholder and compact default font size', (tester) async {
    await pump(tester, placeHolder: 'Pick a category');

    final field = tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
    expect(field.placeholder, 'Pick a category');
    expect(field.style!.fontSize, 12);
    expect(tester.getSize(find.byType(CupertinoTextField)).height, 32);
  });

  testWidgets('suggests every case insensitive match while typing', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(CupertinoTextField), 'dra');
    await tester.pumpAndSettle();

    expect(find.text('Drama'), findsOneWidget);
    expect(find.text('drama school'), findsOneWidget);
    expect(find.text('Cosplay'), findsNothing);

    await tester.enterText(find.byType(CupertinoTextField), 'COS');
    await tester.pumpAndSettle();
    expect(find.text('Cosplay'), findsOneWidget);
    expect(find.text('Drama'), findsNothing);
  });

  testWidgets('shows the empty message when nothing matches', (tester) async {
    await pump(tester, emptyText: 'No category found');

    await tester.enterText(find.byType(CupertinoTextField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text('No category found'), findsOneWidget);
  });

  testWidgets('reports the picked suggestion', (tester) async {
    final picked = <String>[];
    await pump(tester, onSelected: picked.add);

    await tester.enterText(find.byType(CupertinoTextField), 'big');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Big Tits'));
    await tester.pumpAndSettle();

    expect(picked, ['Big Tits']);
  });

  testWidgets('a custom field builder replaces the default input', (tester) async {
    await pump(tester, fieldBuilder: (context, textController, focusNode) {
      return TextField(controller: textController, focusNode: focusNode, decoration: const InputDecoration(hintText: 'Custom field'));
    });

    expect(find.byType(CupertinoTextField), findsNothing);
    expect(find.text('Custom field'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'cos');
    await tester.pumpAndSettle();
    expect(find.text('Cosplay'), findsOneWidget);
  });

  testWidgets('an empty catalogue never suggests anything', (tester) async {
    await pump(tester, items: const [], emptyText: 'Nothing here');

    await tester.enterText(find.byType(CupertinoTextField), 'a');
    await tester.pumpAndSettle();

    expect(find.text('Nothing here'), findsOneWidget);
  });
}
