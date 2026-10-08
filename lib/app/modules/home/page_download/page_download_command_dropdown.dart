import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/app_color.dart';
import 'page_download_helper.dart';

class DownloadCommandDropdown extends StatefulWidget {
  const DownloadCommandDropdown({super.key, required this.commands, required this.selectedIndex, required this.onPick});

  final List<PageDownloadCommand> commands;
  final int selectedIndex;
  final ValueChanged<String> onPick;

  @override
  State<DownloadCommandDropdown> createState() => _DownloadCommandDropdownState();
}

class _DownloadCommandDropdownState extends State<DownloadCommandDropdown> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant DownloadCommandDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex && oldWidget.commands.length == widget.commands.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || widget.selectedIndex < 0) return;
      var top = widget.selectedIndex * 32.0;
      for (var i = 0; i <= widget.selectedIndex && i < widget.commands.length; i++) {
        if (i == 0 || widget.commands[i].group != widget.commands[i - 1].group) top += 24;
      }
      final bottom = top + 32;
      final position = _scroll.position;
      if (top < position.pixels) {
        _scroll.jumpTo(top.clamp(0.0, position.maxScrollExtent));
      } else if (bottom > position.pixels + position.viewportDimension) {
        _scroll.jumpTo((bottom - position.viewportDimension).clamp(0.0, position.maxScrollExtent));
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: BoxConstraints(maxHeight: (MediaQuery.sizeOf(context).height * .6).clamp(80.0, 336.0)),
      decoration: BoxDecoration(
        color: AppColor.container,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColor.border, width: .5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(color: Colors.transparent, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: ListView(
          controller: _scroll,
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: List.generate(widget.commands.length, (index) {
            final command = widget.commands[index];
            final selected = index == widget.selectedIndex;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              if (index == 0 || command.group != widget.commands[index - 1].group) Container(
                height: 24,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(command.group, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColor.muted)),
              ),
              SizedBox(height: 32, child: Semantics(selected: selected, button: true, child: InkWell(
              canRequestFocus: false,
              onTap: () => widget.onPick(command.value),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColor.selected : Colors.transparent,
                  border: Border(left: BorderSide(color: selected ? AppColor.accentForeground : Colors.transparent, width: 2)),
                ),
                child: Row(children: [
                  SizedBox(width: 124, child: Text(command.value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColor.text))),
                  Expanded(child: Tooltip(message: command.description.tr, child: Text(command.description.tr,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColor.muted)))),
                  const SizedBox(width: 8),
                  SizedBox(width: 16, child: Text(selected ? '↵' : '', style: TextStyle(fontSize: 12, color: AppColor.muted))),
                ]),
              ),
            ))),
            ]);
          }),
        )),
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColor.border, width: .5))),
          child: Text('↑ ↓ Navigate · ↵ Select · Esc Close'.tr, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: AppColor.muted)),
        ),
      ])),
    );
  }
}
