import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_color.dart';

class SearchTabBar extends StatelessWidget {
  const SearchTabBar({super.key, required this.tabs, required this.activeIndex,
    required this.scrollController, required this.onSelect, required this.onClose, required this.onAdd, this.addTooltip = 'New search tab'});

  final List<({String title, bool isLoading})> tabs;
  final int activeIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onAdd;
  final String addTooltip;

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return SizedBox(
      height: 32,
      child: ListView.builder(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length + 1,
        itemBuilder: (context, index) {
          if (index == tabs.length) {
            return IconButton(
              tooltip: addTooltip.tr,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              icon: const Icon(Icons.add, size: 16),
              onPressed: onAdd,
            );
          }
          final tab = tabs[index];
          return Container(
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
              IconButton(
                tooltip: 'Close tab'.tr,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                icon: const Icon(Icons.close, size: 12),
                onPressed: () => onClose(index),
              ),
            ]),
          );
        },
      ),
    );
  }
}
