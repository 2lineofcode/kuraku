import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class AppShortcut extends SingleActivator {
  const AppShortcut(super.trigger, {super.alt, super.shift, super.includeRepeats}) : super(meta: true);

  static bool get isMacOS => defaultTargetPlatform == TargetPlatform.macOS;
  static LogicalKeyboardKey get modifier => isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control;
  static bool get isPressed => isMacOS ? HardwareKeyboard.instance.isMetaPressed : HardwareKeyboard.instance.isControlPressed;
  static String label(String value) => isMacOS ? value : value.replaceAll('⌘', 'Ctrl').replaceAll('⌥', 'Alt').replaceAll('⇧', 'Shift');

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) => super.accepts(event, state) || !isMacOS &&
      SingleActivator(trigger, control: true, alt: alt, shift: shift, includeRepeats: includeRepeats).accepts(event, state);
}
