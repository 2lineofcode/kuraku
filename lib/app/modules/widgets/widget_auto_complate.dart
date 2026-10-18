import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:get/get.dart';

import 'widget_controls.dart';

class ExAutoComplate extends StatelessWidget {
  const ExAutoComplate({
    super.key,
    required this.items,
    this.controller,
    this.placeHolder,
    this.emptyText,
    this.maxHeight,
    this.maxWidth,
    this.onSelected,
    this.fontSize,
    this.fieldBuilder,
    this.displayStringForOption,
  });

  final List<String> items;
  final String Function(String)? displayStringForOption;
  final TextEditingController? controller;
  final String? placeHolder;
  final String? emptyText;
  final double? maxHeight;
  final double? maxWidth;
  final Function(String)? onSelected;
  final double? fontSize;
  final Widget Function(BuildContext, TextEditingController, FocusNode)? fieldBuilder;

  @override
  Widget build(BuildContext context) {
    return TypeAheadField<String>(
      controller: controller,
      suggestionsCallback: (search) {
        return items.where((kategori) {
          return (displayStringForOption?.call(kategori) ?? kategori).toLowerCase().contains((displayStringForOption?.call(search) ?? search).toLowerCase());
        }).toList();
      },
      builder: fieldBuilder ?? (context, controller, focusNode) {
        return AppTextField(
          controller: controller,
          focusNode: focusNode,
          clearButtonMode: OverlayVisibilityMode.editing,
          placeholder: placeHolder ?? 'Search...'.tr,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: fontSize),
        );
      },
      itemBuilder: (context, s) {
        return (displayStringForOption?.call(s) ?? s).text.minFontSize(11).size(11).make().p8().pOnly(left: 8);
      },
      constraints: BoxConstraints(
        maxHeight: maxHeight ?? 200,
        maxWidth: maxWidth ?? double.infinity,
      ),
      transitionBuilder: (context, animation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.fastOutSlowIn),
          child: child,
        );
      },
      loadingBuilder: (context) => Text('Loading...'.tr),
      errorBuilder: (context, error) => Text('Error!'.tr),
      emptyBuilder: (context) => (emptyText ?? 'No matches.'.tr).text.size(11).minFontSize(11).make(),
      decorationBuilder: (context, child) {
        return Material(
          type: MaterialType.card,
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: child,
        );
      },
      onSelected: onSelected,
    );
  }
}
