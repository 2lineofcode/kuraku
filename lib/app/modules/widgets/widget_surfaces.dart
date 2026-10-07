import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_color.dart';
import 'widget_style.dart';

class AppPanel extends StatelessWidget {
  const AppPanel({super.key, required this.child, this.padding = const EdgeInsets.all(AppStyle.panelPadding),
    this.bordered = false, this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool bordered;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: .025),
        borderRadius: BorderRadius.circular(AppStyle.radius),
        border: bordered ? Border.all(color: AppColor.border, width: .5) : null,
      ),
      child: child,
    );
  }
}

class AppSectionHeading extends StatelessWidget {
  const AppSectionHeading({super.key, required this.title, this.detail, this.action});
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(children: [
        Expanded(child: Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          if (detail != null) Text(detail!, style: TextStyle(fontSize: 11, color: AppColor.muted)),
        ])),
        const SizedBox(width: 12),
        Expanded(child: Divider(height: 1, thickness: .5, color: AppColor.border)),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ]),
    );
  }
}

class AppDialog extends StatelessWidget {
  const AppDialog({super.key, this.child, this.title, this.content, this.actions = const [],
    this.maxWidth = 520,
    this.backgroundColor, this.surfaceTintColor,
    this.insetPadding = const EdgeInsets.all(16), this.clipBehavior = Clip.antiAlias,
    this.titlePadding = const EdgeInsets.fromLTRB(16, 16, 16, 12),
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
    this.actionsPadding = const EdgeInsets.all(12)});

  final Widget? child, title, content;
  final double maxWidth;
  final List<Widget> actions;
  final Color? backgroundColor, surfaceTintColor;
  final EdgeInsets insetPadding, titlePadding, contentPadding, actionsPadding;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Dialog(
      backgroundColor: backgroundColor ?? AppColor.panel,
      surfaceTintColor: surfaceTintColor ?? Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppStyle.radius + 2), side: BorderSide(color: AppColor.border)),
      insetPadding: insetPadding, clipBehavior: clipBehavior,
      child: child ?? ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) Padding(padding: titlePadding, child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), child: title!,
          )),
          if (content != null) Flexible(child: SingleChildScrollView(padding: contentPadding, child: content!)),
          if (actions.isNotEmpty) Padding(
            padding: actionsPadding,
            child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
          ),
        ]),
      ),
    );
  }
}

class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({super.key, this.title, this.content, this.actions = const []});
  final Widget? title, content;
  final List<Widget> actions;

  static void show({Widget? title, Widget? content, List<Widget> actions = const [], bool isDismissible = true}) {
    unawaited(showAdaptiveDialog<void>(
      context: Get.context!, barrierDismissible: isDismissible,
      builder: (_) => AppConfirmDialog(title: title, content: content, actions: actions),
    ));
  }

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
    title: title == null ? null : DefaultTextStyle.merge(style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), child: title!),
    content: content == null ? null : DefaultTextStyle.merge(style: const TextStyle(fontSize: 12), child: content!),
    actions: actions,
  );
}

class AppDialogAction extends StatelessWidget {
  const AppDialogAction({super.key, required this.child, required this.onPressed,
    this.isDefaultAction = false, this.isDestructiveAction = false});
  final Widget child;
  final VoidCallback? onPressed;
  final bool isDefaultAction, isDestructiveAction;

  @override
  Widget build(BuildContext context) => CupertinoDialogAction(
    isDefaultAction: isDefaultAction, isDestructiveAction: isDestructiveAction,
    onPressed: onPressed,
    child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 13), child: child),
  );
}
