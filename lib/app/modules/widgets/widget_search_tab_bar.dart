import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;

import '../../core/app_color.dart';
import 'widget_controls.dart';
import 'widget_style.dart';

class SearchTabBar extends StatelessWidget {
  const SearchTabBar({super.key, required this.tabs, required this.activeIndex,
    required this.scrollController, required this.onSelect, required this.onClose, required this.onAdd,
    required this.onReorder, required this.onPin, this.addTooltip = 'New search tab'});

  final List<({int id, String title, bool isLoading, bool isPinned})> tabs;
  final int activeIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onAdd;
  final ReorderCallback onReorder;
  final ValueChanged<int> onPin;
  final String addTooltip;

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return SizedBox(
      height: 32,
      child: ReorderableListView.builder(
        scrollController: scrollController,
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        onReorderItem: onReorder,
        footer: AppIconButton(
          tooltip: addTooltip.tr,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: AppStyle.iconSize),
          onPressed: onAdd,
        ),
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final tab = tabs[index];
          return ReorderableDragStartListener(
            key: ValueKey(tab.id),
            index: index,
            child: scm.ContextMenuWidget(
              menuProvider: (_) => scm.Menu(children: [
                scm.MenuAction(title: tab.isPinned ? 'Unpin'.tr : 'Pin'.tr, callback: () => onPin(index)),
                scm.MenuAction(title: 'Close tab'.tr, attributes: scm.MenuActionAttributes(disabled: tab.isPinned), callback: () => onClose(index)),
              ]),
              child: Container(
                width: 136,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: activeIndex == index ? AppColor.selected : AppColor.container,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: InkWell(
                    onTap: () => onSelect(index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(children: [
                        if (tab.isLoading) ...[
                          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                          const SizedBox(width: 6),
                        ],
                        Expanded(child: Tooltip(
                          message: tab.title == 'New search' || tab.title == 'Filtered search' ? tab.title.tr : tab.title,
                          child: Text(tab.title == 'New search' || tab.title == 'Filtered search' ? tab.title.tr : tab.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                        )),
                      ]),
                    ),
                  )),
                  if (tab.isPinned) AppIconButton(
                    tooltip: 'Unpin tab'.tr,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 24, height: 32),
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedPin02, size: AppStyle.iconSize),
                    color: Colors.amber,
                    onPressed: () => onPin(index),
                  ),
                  if (!tab.isPinned) AppIconButton(
                    tooltip: 'Close tab'.tr,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize),
                    onPressed: () => onClose(index),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
