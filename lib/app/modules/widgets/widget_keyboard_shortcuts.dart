import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/app_color.dart';
import 'widget_controls.dart';
import 'widget_style.dart';
import 'widget_surfaces.dart';

class KeyboardShortcutsPanel extends StatelessWidget {
  const KeyboardShortcutsPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    const groups = {
      'Navigation': [
        ('⌘ + 1', 'Go to Home'),
        ('⌘ + 2', 'Go to Library'),
        ('⌘ + 3', 'Go to Explore'),
        ('⌘ + 4', 'Go to Downloads'),
        ('⌘ + 5', 'Go to Tools'),
        ('⌘ + ,', 'Open Settings'),
      ],
      'Panels': [
        ('⌘ + B', 'Show/hide side menu (mini mode)'),
        ('⌘ + E', 'Open video cart panel'),
        ('⌘ + L', 'Open app log panel'),
        ('⌘ + P', 'Open playlist panel'),
        ('⌘ + .', 'Open relapse panel'),
      ],
      'Actions': [
        ('⌘ + D', 'Open new download dialog'),
        ('⌘ + T', 'Add new todo'),
        ('⌘ + R', 'Reload all pages'),
        ('Esc', 'Close dialog/panel'),
      ],
    };
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
      child: FocusScope(autofocus: true, child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColor.selected, borderRadius: BorderRadius.circular(AppStyle.radius)),
                child: HugeIcon(icon: HugeIcons.strokeRoundedKeyboard, size: 20, color: AppColor.text),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Keyboard Shortcuts'.tr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              AppIconButton(tooltip: 'Close'.tr, icon: const Icon(Icons.close, size: AppStyle.iconSize), onPressed: onClose),
            ]),
            const SizedBox(height: 20),
            Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final group in groups.entries) ...[
                AppSectionHeading(title: group.key.tr),
                const SizedBox(height: 6),
                AppPanel(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), bordered: true,
                  child: Column(children: [
                    for (final shortcut in group.value)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Expanded(child: Text(shortcut.$2.tr, style: const TextStyle(fontSize: 13))),
                          const SizedBox(width: 16),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            for (final key in shortcut.$1.split(' + '))
                              Container(
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                margin: const EdgeInsets.only(left: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColor.panel,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: AppColor.border),
                                  boxShadow: [BoxShadow(color: AppColor.border, offset: const Offset(0, 2))],
                                ),
                                child: Text(key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                          ]),
                        ]),
                      ),
                  ]),
                ),
                if (group.key != groups.keys.last) const SizedBox(height: 16),
              ],
            ]))),
          ]),
        ),
      )),
    );
  }
}
