import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_list_view/flutter_list_view.dart';

import '../../data/models/videos_entity.dart';
import '../../utils/helper_opener.dart';

class ScreenshotSource extends StatefulWidget {
  const ScreenshotSource.grid({super.key, required this.items, required this.gridDelegate,
    required this.itemBuilder, this.itemCount, this.controller, this.padding = EdgeInsets.zero})
    : itemExtent = null, separatorBuilder = null, scrollDirection = Axis.vertical, _column = false;

  const ScreenshotSource.list({super.key, required this.items, required this.itemExtent,
    required this.itemBuilder, this.controller, this.padding = EdgeInsets.zero,
    this.scrollDirection = Axis.vertical})
    : gridDelegate = null, itemCount = null, _column = false, separatorBuilder = null;

  const ScreenshotSource.separated({super.key, required this.items, required this.itemBuilder,
    required this.separatorBuilder, FlutterListViewController? this.controller, this.padding = EdgeInsets.zero})
    : gridDelegate = null, itemExtent = null, itemCount = null,
      scrollDirection = Axis.vertical, _column = false;

  const ScreenshotSource.column({super.key, required this.items, required this.itemBuilder})
    : gridDelegate = null, itemExtent = null, separatorBuilder = null, itemCount = null,
      controller = null, padding = EdgeInsets.zero, scrollDirection = Axis.vertical, _column = true;

  final List<dynamic> items;
  final SliverGridDelegate? gridDelegate;
  final double? itemExtent;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final int? itemCount;
  final ScrollController? controller;
  final EdgeInsets padding;
  final Axis scrollDirection;
  final bool _column;

  static final _sources = <_ScreenshotSourceState>{};
  static final _origins = Expando<_ScreenshotSourceState>();

  static List<dynamic> snapshot(List<dynamic> items) {
    // Preserve the originating list when info panels pass snapshots to the viewer.
    final copy = List<dynamic>.of(items);
    final inherited = _origins[items];
    final origin = inherited?.mounted == true ? inherited
        : _sources.where((source) => identical(source.widget.items, items)).lastOrNull;
    if (origin != null) _origins[copy] = origin;
    return copy;
  }

  static Future<void> restore(List<dynamic> items, dynamic item, {bool focus = true}) async {
    final origin = _origins[items];
    if (origin != null && origin.mounted) await origin.reveal(item, focus: focus);
  }

  @override
  State<ScreenshotSource> createState() => _ScreenshotSourceState();
}

class _ScreenshotSourceState extends State<ScreenshotSource> {
  late final _ownController = FlutterListViewController();
  ScrollController get _controller => widget.controller ?? _ownController;
  final _builtItems = <int, _ScreenshotSourceItemState>{};
  dynamic _selected;
  int _selectedIndex = -1;
  double _crossAxisExtent = 0;

  @override
  void initState() {
    super.initState();
    ScreenshotSource._sources.add(this);
  }

  @override
  void didUpdateWidget(covariant ScreenshotSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected != null) _selectedIndex = _indexOf(_selected);
  }

  @override
  void dispose() {
    ScreenshotSource._sources.remove(this);
    _ownController.dispose();
    super.dispose();
  }

  int _indexOf(dynamic item) {
    final index = HelperOpener.screenshotItemIndex(item, widget.items);
    if (index < 0) return -1;
    final candidate = widget.items[index];
    if (item is Videos && candidate is Videos && (item.videoPath ?? '').isNotEmpty &&
        candidate.videoPath != item.videoPath && ((item.id ?? '').isEmpty || candidate.id != item.id)) return -1;
    return index;
  }

  Future<void> reveal(dynamic item, {required bool focus}) async {
    final index = _indexOf(item);
    if (index < 0 || (!widget._column && !_controller.hasClients)) return;
    setState(() { _selected = item; _selectedIndex = index; });
    if (widget._column) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _selectedIndex != index) return;
      final target = _builtItems[index];
      final render = target?.context.findRenderObject();
      if (target == null || render == null) return;
      final position = Scrollable.of(target.context).position;
      final start = RenderAbstractViewport.of(render).getOffsetToReveal(render, 0).offset;
      await Scrollable.ensureVisible(target.context, alignmentPolicy: start < position.pixels
          ? ScrollPositionAlignmentPolicy.keepVisibleAtStart : ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      if (mounted && target.mounted && focus) target._focusNode.requestFocus();
      return;
    }
    if (widget.separatorBuilder != null) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _selectedIndex != index) return;
      (_controller as FlutterListViewController).sliverController.ensureVisible(index * 2);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && _selectedIndex == index && focus) _builtItems[index]?._focusNode.requestFocus();
      return;
    }
    final position = _controller.position;
    double start;
    double extent;
    if (widget.gridDelegate case final delegate?) {
      final layout = delegate.getLayout(SliverConstraints(
        axisDirection: AxisDirection.down, growthDirection: GrowthDirection.forward,
        userScrollDirection: ScrollDirection.idle, scrollOffset: 0, precedingScrollExtent: 0,
        overlap: 0, remainingPaintExtent: position.viewportDimension, crossAxisExtent: _crossAxisExtent,
        crossAxisDirection: AxisDirection.right, viewportMainAxisExtent: position.viewportDimension,
        remainingCacheExtent: 0, cacheOrigin: 0,
      ));
      final geometry = layout.getGeometryForChildIndex(index);
      start = geometry.scrollOffset;
      extent = geometry.mainAxisExtent;
    } else {
      start = index * widget.itemExtent!;
      extent = widget.itemExtent!;
    }
    start += widget.scrollDirection == Axis.vertical ? widget.padding.top : widget.padding.left;
    final end = start + extent;
    final target = start < position.pixels ? start
        : end > position.pixels + position.viewportDimension ? end - position.viewportDimension
        : position.pixels;
    if (target != position.pixels) _controller.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _selectedIndex != index) return;
    if (focus) _builtItems[index]?._focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    _crossAxisExtent = constraints.maxWidth - widget.padding.horizontal;
    Widget buildItem(BuildContext context, int index) {
      final child = widget.itemBuilder(context, index);
      if (index >= widget.items.length) return child;
      return _ScreenshotSourceItem(key: ValueKey(index), source: this, index: index,
        selected: index == _selectedIndex, child: child);
    }
    if (widget._column) return Column(mainAxisSize: MainAxisSize.min,
      children: [for (var i = 0; i < widget.items.length; i++) buildItem(context, i)]);
    if (widget.gridDelegate case final delegate?) {
      return GridView.builder(
        controller: _controller, padding: widget.padding, gridDelegate: delegate,
        itemCount: widget.itemCount ?? widget.items.length, itemBuilder: buildItem,
      );
    }
    if (widget.separatorBuilder case final separator?) {
      return Padding(padding: widget.padding, child: FlutterListView.separated(
        controller: _controller as FlutterListViewController, scrollDirection: widget.scrollDirection,
        itemCount: widget.items.length, itemBuilder: buildItem, separatorBuilder: separator,
      ));
    }
    return ListView.builder(
      controller: _controller, padding: widget.padding, scrollDirection: widget.scrollDirection,
      itemExtent: widget.itemExtent, itemCount: widget.items.length, itemBuilder: buildItem,
    );
  });
}

class _ScreenshotSourceItem extends StatefulWidget {
  const _ScreenshotSourceItem({super.key, required this.source, required this.index, required this.selected, required this.child});
  final _ScreenshotSourceState source;
  final int index;
  final bool selected;
  final Widget child;

  @override
  State<_ScreenshotSourceItem> createState() => _ScreenshotSourceItemState();
}

class _ScreenshotSourceItemState extends State<_ScreenshotSourceItem> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.source._builtItems[widget.index] = this;
  }

  @override
  void dispose() {
    if (identical(widget.source._builtItems[widget.index], this)) widget.source._builtItems.remove(widget.index);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(focusNode: _focusNode,
    child: Semantics(selected: widget.selected, child: Stack(fit: StackFit.passthrough, children: [
      widget.child,
      if (widget.selected) Positioned.fill(child: IgnorePointer(child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.blue.withAlpha(35), border: Border.all(color: Colors.lightBlueAccent, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      ))),
    ])),
  );
}
