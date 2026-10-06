import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_color.dart';
import 'widget_search_suggestions_overlay.dart';

class SearchHistoryDropdown extends StatelessWidget {
  const SearchHistoryDropdown({super.key, required this.suggestions, required this.selectedIndex,
    required this.onPick, required this.onDelete, required this.onClear});

  final List<String> suggestions;
  final int selectedIndex;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onDelete;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return SearchSuggestionsOverlay(child: suggestions.isEmpty ? const SizedBox.shrink() : _buildDropdown(context));
  }

  Widget _buildDropdown(BuildContext context) {
    return TextFieldTapRegion(child: Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 140),
      decoration: BoxDecoration(
        color: AppColor.container,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColor.border, width: .5),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemExtent: 28,
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final query = suggestions[index];
              return InkWell(
                onTap: () => onPick(query),
                child: Container(
                  color: selectedIndex == index ? AppColor.selected.withAlpha(90) : Colors.transparent,
                  padding: const EdgeInsets.only(left: 8, right: 2),
                  child: Row(children: [
                    const Icon(Icons.history, size: 12),
                    const SizedBox(width: 6),
                    Expanded(child: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
                    IconButton(
                      tooltip: 'Remove from history'.tr,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                      icon: const Icon(Icons.close, size: 12),
                      onPressed: () => onDelete(query),
                    ),
                  ]),
                ),
              );
            },
          )),
          Container(
            height: 28,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColor.border, width: .5))),
            alignment: Alignment.centerRight,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () async {
                final confirmed = await showCupertinoDialog<bool>(
                  context: context,
                  builder: (context) => CupertinoAlertDialog(
                    title: Text('Are you sure you want to clear all history?'.tr, style: TextStyle(fontSize: 13)),
                    actions: [
                      CupertinoDialogAction(onPressed: () => Navigator.pop(context, false), child: Text('No'.tr)),
                      CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: Text('Yes'.tr)),
                    ],
                  ),
                );
                if (confirmed == true) await onClear();
              },
              child: Text('Clear all'.tr, style: TextStyle(fontSize: 11)),
            ),
          ),
        ]),
      ),
    ));
  }
}
