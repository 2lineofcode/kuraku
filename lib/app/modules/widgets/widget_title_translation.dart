import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter_popup/flutter_popup.dart';
import 'package:get/get.dart';
import 'package:translator/translator.dart';

import '../../core/app_color.dart';
import 'widget_style.dart';

class TitleTranslation extends StatefulWidget {
  const TitleTranslation({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<TitleTranslation> createState() => _TitleTranslationState();
}

class _TitleTranslationState extends State<TitleTranslation> {
  final _popupKey = GlobalKey<CustomPopupState>();
  bool _loading = false;
  String _translated = '';

  Future<void> _translate() async {
    if (_loading || widget.title.trim().isEmpty) return;
    Tooltip.dismissAllToolTips();
    setState(() => _loading = true);
    final title = widget.title;
    String translated;
    try {
      translated = (await GoogleTranslator().translate(title, from: 'auto', to: 'id')
          .timeout(const Duration(seconds: 15))).text;
    } catch (_) {
      translated = 'Unable to translate title. Try again.'.tr;
    }
    if (!mounted) return;
    setState(() { _loading = false; _translated = translated; });
    if (widget.title != title) return;
    // CustomPopup measures content once, so open it after the translation is ready.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) _popupKey.currentState?.show();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    var raised = false;
    return CustomPopup(
      key: _popupKey,
      isLongPress: true,
      backgroundColor: AppColor.hover,
      arrowColor: AppColor.hover,
      barrierColor: AppColor.selected.withAlpha(50),
      contentRadius: AppStyle.radius,
      contentPadding: const EdgeInsets.all(12),
      content: Builder(builder: (popupContext) {
        if (!raised) {
          raised = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!popupContext.mounted) return;
            // Navigator popup routes must sit above the panel's Overlayment entries.
            final route = ModalRoute.of(popupContext)!;
            final overlay = Overlay.of(popupContext);
            void raise() {
              if (popupContext.mounted) overlay.rearrange(route.overlayEntries, below: route.overlayEntries.first);
            }
            raise();
            void onAnimationStatus(AnimationStatus status) {
              if (status != AnimationStatus.completed) return;
              route.animation!.removeStatusListener(onAnimationStatus);
              WidgetsBinding.instance.addPostFrameCallback((_) => raise());
            }
            route.animation!.addStatusListener(onAnimationStatus);
          });
        }
        return SizedBox(width: min(300.0, size.width - 44), child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * .4),
          child: SingleChildScrollView(child: Text(_translated,
            style: TextStyle(fontSize: AppStyle.fontSize, color: AppColor.text))),
        ));
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: _translate,
        child: _loading ? Text('Translating...'.tr, textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppStyle.fontSize, color: AppColor.muted)) : widget.child,
      ),
    );
  }
}
