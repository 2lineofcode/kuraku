import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';

Finder findHugeIcon(List<List<dynamic>> icon) => find.byWidgetPredicate((widget) => widget is HugeIcon && widget.icon == icon);

Finder findHugeIconButton(List<List<dynamic>> icon) => find.ancestor(of: findHugeIcon(icon), matching: find.byType(IconButton));
