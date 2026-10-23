import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/app_color.dart';
import '../../core/app_shortcut.dart';
import 'widget_controls.dart';
import 'widget_style.dart';
import 'widget_surfaces.dart';

class KeyboardShortcutsPanel extends StatefulWidget {
  const KeyboardShortcutsPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<KeyboardShortcutsPanel> createState() => _KeyboardShortcutsPanelState();
}

class _KeyboardShortcutsPanelState extends State<KeyboardShortcutsPanel> {
  String _tab = 'App';

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    const tabs = {
      'App': {
        'Navigation': [
          ('⌘ + 1', 'Go to Home'),
          ('⌘ + 2', 'Go to Library'),
          ('⌘ + 3', 'Go to Explore'),
          ('⌘ + 4', 'Go to Downloads'),
          ('⌘ + 5', 'Go to Tools'),
          ('⌘ + ,', 'Open Settings'),
          ('/', 'Focus search (outside text inputs)'),
          ('⌘ + F', 'Focus search (outside text inputs)'),
        ],
        'Panels': [
          ('⌘ + /', 'Open Keyboard Shortcuts'),
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
          ('⌘ + ⇧ + T', 'Toggle light/dark theme'),
          ('Esc', 'Close dialog/panel'),
        ],
      },
      'Player': {
        'Playback': [
          ('Space', 'Play/pause'),
          ('← / →', 'Seek backward/forward (short step)'),
          ('⌥ + ← / →', 'Seek backward/forward (medium step)'),
          ('⌘ + ← / →', 'Seek backward/forward (long step)'),
          ('↑ / ↓', 'Volume up/down'),
          ('] / [', 'Playback speed up/down'),
          ('M', 'Mute/unmute'),
        ],
        'Video controls': [
          ('⌘ + ⌥ + C', 'Enable/disable bottom controls'),
          ('A', 'Toggle video fit'),
          (',', 'Open/close video adjustments'),
          ('⌘ + ⌥ + ←', 'Rotate video left'),
          ('⌘ + ⌥ + →', 'Rotate video right'),
          ('P', 'Enter/exit mini player'),
        ],
        'Trailer playback': [
          ('Space', 'Play/pause'),
          ('← / →', 'Seek backward/forward 5 seconds'),
          ('⌥ + ← / →', 'Seek backward/forward 30 seconds'),
          ('⌘ + ← / →', 'Seek backward/forward 60 seconds'),
          ('↑ / ↓', 'Volume up/down'),
          ('] / [', 'Playback speed up/down'),
          ('M', 'Mute/unmute'),
        ],
        'Player navigation': [
          ('⇧ + >', 'Next video'),
          ('⇧ + <', 'Previous video'),
          ('L', 'Open player playlist'),
          ('I', 'Open video info'),
          ('⌘ + I', 'Properties'),
          ('⌥ + ↑', 'Open screenshots'),
          ('C', 'Add video to cart'),
          ('Q', 'Close player'),
        ],
      },
      'Pages': {
        'Search, Explore, Downloads & SQL': [
          ('⌘ + N', 'New tab'),
          ('⌘ + W', 'Close current tab'),
        ],
        'Search & Downloads suggestions': [
          ('↑ / ↓', 'Select suggestion'),
          ('Esc', 'Hide suggestions'),
        ],
        'Screenshots': [
          ('← / →', 'Previous/next image'),
          ('⌥ + ← / →', 'Previous/next video screenshots'),
          ('↓ / Esc', 'Close screenshot viewer'),
        ],
        'Video info panel': [
          ('↑', 'Open screenshots'),
          ('↓ / I', 'Close video info'),
          ('.', 'Open video file'),
        ],
        'SQL editor': [
          ('⌘ + Enter', 'Run query'),
          ('Ctrl + Space', 'Open autocomplete'),
          ('↑ / ↓', 'Select autocomplete suggestion'),
          ('Tab / Enter', 'Accept autocomplete suggestion'),
          ('Esc', 'Close autocomplete'),
        ],
      },
      'Chat': {
        'Conversations': [
          ('⌘ + N', 'New conversation'),
          ('⌘ + W', 'Delete current conversation'),
          ('⌘ + F', 'Search chat history'),
          ('⌘ + L', 'Focus chat input'),
          ('⌘ + ⇧ + S', 'Show/hide chat history'),
        ],
        'Messages': [
          ('Enter', 'Send message'),
          ('⇧ + Enter', 'New line'),
          ('⌘ + ⇧ + R', 'Retry response'),
          ('⌘ + .', 'Stop response'),
          ('Esc', 'Cancel message edit / close commands'),
        ],
        'Chat image viewer': [
          ('← / →', 'Previous/next image'),
          ('↓', 'Close image viewer'),
        ],
        'Chat commands': [
          ('↑ / ↓', 'Select command'),
          ('Tab', 'Complete command'),
        ],
      },
    };
    final groups = tabs[_tab]!;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): widget.onClose},
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
              AppIconButton(tooltip: 'Close'.tr, icon: const Icon(Icons.close, size: AppStyle.iconSize), onPressed: widget.onClose),
            ]),
            const SizedBox(height: 16),
            CupertinoSlidingSegmentedControl<String>(
              groupValue: _tab,
              children: {for (final tab in tabs.keys) tab: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(tab.tr, style: const TextStyle(fontSize: 12)),
              )},
              onValueChanged: (value) { if (value != null) setState(() => _tab = value); },
            ),
            const SizedBox(height: 12),
            if (_tab == 'Player') ...[
              Text('Full player shortcuts. Mini player supports seek, next/previous and P. Multi-player supports playback, volume, speed, mute and Q. Seek steps follow Settings.'.tr,
                style: TextStyle(fontSize: 11, color: AppColor.muted)),
              const SizedBox(height: 12),
            ],
            Flexible(child: SingleChildScrollView(key: ValueKey(_tab), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                            for (final key in AppShortcut.label(shortcut.$1).split(' + '))
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
