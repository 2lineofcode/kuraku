import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/app_color.dart';
import 'widget_style.dart';

enum AppButtonVariant { text, filled, outlined, tonal }

class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.onPressed, this.child, this.label, this.icon,
    this.variant = AppButtonVariant.text, this.style, this.height = AppStyle.controlHeight,
    this.width, this.labelSize = AppStyle.fontSize, this.labelColor, this.borderColor,
    this.backgroundColor, this.isLabelBold = false, this.padding, this.minimumSize, this.focusNode});

  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final Widget? child;
  final String? label;
  final Widget? icon;
  final AppButtonVariant variant;
  final ButtonStyle? style;
  final double height;
  final double? width;
  final double labelSize;
  final Color? labelColor, borderColor, backgroundColor;
  final bool isLabelBold;
  final EdgeInsetsGeometry? padding;
  final Size? minimumSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = variant == AppButtonVariant.filled;
    final content = DefaultTextStyle.merge(
      style: TextStyle(fontSize: labelSize, fontWeight: isLabelBold ? FontWeight.w600 : FontWeight.w400),
      child: icon == null ? child ?? Text(label ?? '') : Row(mainAxisSize: MainAxisSize.min, children: [
        IconTheme.merge(data: const IconThemeData(size: AppStyle.iconSize), child: icon!),
        const SizedBox(width: 6),
        Flexible(child: child ?? Text(label ?? '', overflow: TextOverflow.ellipsis)),
      ]),
    );
    final defaults = TextButton.styleFrom(
      foregroundColor: labelColor ?? (primary ? scheme.onPrimary : scheme.onSurface),
      backgroundColor: backgroundColor ?? (primary ? scheme.primary : variant == AppButtonVariant.tonal ? scheme.primary.withValues(alpha: .12) : null),
      disabledBackgroundColor: primary || variant == AppButtonVariant.tonal || backgroundColor != null ? scheme.onSurface.withValues(alpha: .08) : null,
      minimumSize: minimumSize ?? Size(width ?? 0, height),
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: labelSize, fontWeight: FontWeight.w500),
      side: variant == AppButtonVariant.outlined ? BorderSide(color: borderColor ?? AppColor.border) : null,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppStyle.radius))),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
    final base = (style?.merge(defaults) ?? defaults).copyWith(
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppStyle.radius)))),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final Widget button;
    switch (variant) {
      case AppButtonVariant.filled:
      case AppButtonVariant.tonal:
        button = FilledButton(style: base, focusNode: focusNode, onPressed: onPressed, child: content);
      case AppButtonVariant.outlined:
        button = OutlinedButton(style: base, focusNode: focusNode, onPressed: onPressed, child: content);
      case AppButtonVariant.text:
        button = TextButton(style: base, focusNode: focusNode, onPressed: onPressed, child: content);
    }
    return width == null ? button : SizedBox(width: width, child: button);
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({super.key, required this.icon, required this.onPressed, this.tooltip,
    this.style, this.constraints, this.padding = EdgeInsets.zero, this.visualDensity,
    this.iconSize = AppStyle.iconSize, this.color, this.splashRadius, this.filled = false});

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final ButtonStyle? style;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry padding;
  final VisualDensity? visualDensity;
  final double iconSize;
  final double? splashRadius;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = (icon is Icon ? (icon as Icon).size ?? iconSize : icon is HugeIcon ? (icon as HugeIcon).size ?? iconSize : iconSize).clamp(AppStyle.iconTarget, double.infinity);
    final defaults = IconButton.styleFrom(
      foregroundColor: color ?? (filled ? scheme.onPrimary : IconTheme.of(context).color ?? scheme.onSurface),
      backgroundColor: filled ? scheme.primary : null,
      disabledForegroundColor: scheme.onSurface.withValues(alpha: .38),
      minimumSize: constraints == null ? Size(target, target) : Size(constraints!.minWidth, constraints!.minHeight),
      padding: padding,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppStyle.radius))),
    );
    final base = (style?.merge(defaults) ?? defaults).copyWith(
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppStyle.radius)))),
    );
    return IconButton(
      tooltip: tooltip, onPressed: onPressed, icon: icon, iconSize: iconSize,
      style: base, color: color, constraints: constraints, padding: padding,
      visualDensity: visualDensity ?? VisualDensity.standard, splashRadius: splashRadius,
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({super.key, this.controller, this.focusNode, this.placeholder,
    this.style, this.placeholderStyle, this.decoration, this.prefix, this.suffix,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.clearButtonMode = OverlayVisibilityMode.never, this.onChanged, this.onSubmitted,
    this.onTap, this.enabled = true, this.readOnly = false, this.autofocus = false,
    this.obscureText = false, this.autocorrect = true, this.enableSuggestions = true,
    this.keyboardType, this.textInputAction, this.inputFormatters, this.minLines,
    this.maxLines = 1, this.expands = false, this.scrollController, this.smartDashesType,
    this.smartQuotesType, this.textAlignVertical, this.selectAllOnFocus});

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final TextStyle? style, placeholderStyle;
  final InputDecoration? decoration;
  final Widget? prefix, suffix;
  final EdgeInsetsGeometry padding;
  final OverlayVisibilityMode clearButtonMode;
  final ValueChanged<String>? onChanged, onSubmitted;
  final VoidCallback? onTap;
  final bool enabled, readOnly, autofocus, obscureText, autocorrect, enableSuggestions, expands;
  final bool? selectAllOnFocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final int? minLines, maxLines;
  final ScrollController? scrollController;
  final SmartDashesType? smartDashesType;
  final SmartQuotesType? smartQuotesType;
  final TextAlignVertical? textAlignVertical;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final input = decoration;
    final field = CupertinoTextField(
      controller: controller, focusNode: focusNode, enabled: enabled, readOnly: readOnly,
      autofocus: autofocus, obscureText: obscureText, autocorrect: autocorrect,
      enableSuggestions: enableSuggestions, keyboardType: keyboardType,
      textInputAction: textInputAction, inputFormatters: inputFormatters,
      minLines: minLines, maxLines: maxLines, expands: expands, scrollController: scrollController,
      smartDashesType: smartDashesType, smartQuotesType: smartQuotesType,
      textAlignVertical: textAlignVertical, selectAllOnFocus: selectAllOnFocus,
      onChanged: onChanged, onSubmitted: onSubmitted, onTap: onTap,
      placeholder: placeholder ?? input?.hintText ?? input?.labelText,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: AppStyle.fontSize, color: scheme.onSurface).merge(style),
      placeholderStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: AppStyle.fontSize, color: scheme.onSurfaceVariant).merge(placeholderStyle),
      padding: padding, prefix: prefix ?? input?.prefixIcon, suffix: suffix ?? input?.suffixIcon,
      clearButtonMode: clearButtonMode, cursorColor: scheme.primary,
      decoration: input?.border == InputBorder.none ? null : AppStyle.inputDecoration(context),
    );
    final control = maxLines == 1 && !expands
        ? ConstrainedBox(constraints: const BoxConstraints(minHeight: AppStyle.inputHeight), child: field) : field;
    if (input == null || (input.labelText == null && input.helperText == null && input.errorText == null)) return control;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (input.labelText != null) Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(input.labelText!, style: TextStyle(fontSize: AppStyle.fontSize, color: scheme.onSurface)),
      ),
      control,
      if (input.errorText != null || input.helperText != null) Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(input.errorText ?? input.helperText!, style: TextStyle(fontSize: 11, color: input.errorText == null ? scheme.onSurfaceVariant : scheme.error)),
      ),
    ]);
  }
}

class AppTextFormField extends StatelessWidget {
  const AppTextFormField({super.key, this.initialValue, this.controller, this.style,
    this.enabled = true, this.autofocus = false, this.placeholder, this.decoration,
    this.padding = EdgeInsets.zero, this.maxLength, this.onChanged, this.onFieldSubmitted,
    this.validator, this.autovalidateMode = AutovalidateMode.disabled});

  final String? initialValue, placeholder;
  final TextEditingController? controller;
  final TextStyle? style;
  final bool enabled, autofocus;
  final InputDecoration? decoration;
  final EdgeInsetsGeometry padding;
  final int? maxLength;
  final ValueChanged<String>? onChanged, onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode autovalidateMode;

  @override
  Widget build(BuildContext context) => CupertinoTextFormFieldRow(
    initialValue: initialValue, controller: controller, enabled: enabled, autofocus: autofocus,
    placeholder: placeholder ?? decoration?.hintText ?? decoration?.labelText,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: AppStyle.fontSize, color: Theme.of(context).colorScheme.onSurface).merge(style),
    placeholderStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: AppStyle.fontSize, color: Theme.of(context).colorScheme.onSurfaceVariant),
    decoration: AppStyle.inputDecoration(context), padding: padding, maxLength: maxLength,
    onChanged: onChanged, onFieldSubmitted: onFieldSubmitted, validator: validator,
    autovalidateMode: autovalidateMode,
  );
}

class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({super.key, required this.value, required this.items, required this.onChanged,
    this.isExpanded = false, this.isDense = true, this.style, this.dropdownColor, this.icon,
    this.prefix, this.menuMaxHeight});
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded, isDense;
  final TextStyle? style;
  final Color? dropdownColor;
  final Widget? icon, prefix;
  final double? menuMaxHeight;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  final _focusNode = FocusNode();

  @override
  void dispose() { _focusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: AppStyle.fontSize, color: scheme.onSurface).merge(widget.style);
    Widget selected = const SizedBox.shrink();
    for (final item in widget.items) {
      if (item.value == widget.value) { selected = item.child; break; }
    }
    return MenuAnchor(
      animated: false, consumeOutsideTap: true, childFocusNode: _focusNode,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(widget.dropdownColor ?? scheme.surface),
        maximumSize: widget.menuMaxHeight == null ? null : WidgetStatePropertyAll(Size(double.infinity, widget.menuMaxHeight!)),
      ),
      menuChildren: [for (final item in widget.items) MenuItemButton(
        onPressed: widget.onChanged == null || !item.enabled ? null : () => widget.onChanged!(item.value),
        leadingIcon: HugeIcon(icon: item.value == widget.value ? HugeIcons.strokeRoundedCheckmarkCircle02 : HugeIcons.strokeRoundedCircle, size: AppStyle.iconSize),
        style: MenuItemButton.styleFrom(textStyle: textStyle),
        child: item.child,
      )],
      builder: (context, menu, child) => AppButton(
        variant: AppButtonVariant.outlined, focusNode: _focusNode,
        backgroundColor: AppStyle.inputDecoration(context).color,
        minimumSize: Size(0, widget.isDense ? AppStyle.inputHeight : 48),
        style: TextButton.styleFrom(textStyle: textStyle),
        onPressed: widget.onChanged == null ? null : () => menu.isOpen ? menu.close() : menu.open(),
        child: Row(mainAxisSize: widget.isExpanded ? MainAxisSize.max : MainAxisSize.min, children: [
          if (widget.prefix != null) ...[widget.prefix!, const SizedBox(width: 6)],
          if (widget.isExpanded) Expanded(child: selected) else Flexible(child: selected),
          const SizedBox(width: 8),
          widget.icon ?? const HugeIcon(icon: HugeIcons.strokeRoundedArrowDown01, size: AppStyle.iconSize),
        ]),
      ),
    );
  }
}

class AppDropdownFormField<T> extends StatelessWidget {
  const AppDropdownFormField({super.key, required this.initialValue, required this.items, required this.onChanged,
    this.isExpanded = true, this.iconSize = AppStyle.iconSize, this.style, this.decoration, this.menuMaxHeight});
  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;
  final double iconSize;
  final TextStyle? style;
  final InputDecoration? decoration;
  final double? menuMaxHeight;

  @override
  Widget build(BuildContext context) => FormField<T>(
    key: ValueKey(initialValue), initialValue: initialValue, enabled: onChanged != null,
    builder: (field) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (decoration?.labelText != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(decoration!.labelText!)),
      AppDropdown<T>(
        value: field.value, items: items, isExpanded: isExpanded, style: style,
        prefix: decoration?.prefixIcon, icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowDown01, size: iconSize),
        menuMaxHeight: menuMaxHeight,
        onChanged: onChanged == null ? null : (value) { field.didChange(value); onChanged!(value); },
      ),
      if (decoration?.errorText != null || decoration?.helperText != null) Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(decoration!.errorText ?? decoration!.helperText!, style: TextStyle(fontSize: 11,
          color: decoration!.errorText == null ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.error)),
      ),
    ]),
  );
}
