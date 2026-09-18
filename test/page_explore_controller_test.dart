import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/modules/home/page_explore/page_explore_controller.dart';

class _DelayedExploreController extends PageExploreController {
  final first = Completer<List<LeftListModel>>();
  final second = Completer<List<LeftListModel>>();
  int calls = 0;

  @override
  Future<List<LeftListModel>> getActressList() => calls++ == 0 ? first.future : second.future;
}

void main() {
  test('latest Explore menu request wins', () async {
    final controller = _DelayedExploreController();
    addTearDown(controller.onClose);

    final older = controller.onMenuChange(kActress);
    final latest = controller.onMenuChange(kActress);

    controller.second.complete([LeftListModel(id: 2, name: 'Latest', count: 1)]);
    await latest;
    controller.first.complete([LeftListModel(id: 1, name: 'Older', count: 1)]);
    await older;

    expect(controller.leftList.map((item) => item.name), ['Latest']);
  });
}
