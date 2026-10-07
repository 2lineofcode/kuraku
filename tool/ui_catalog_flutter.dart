import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:javit/app/core/app_color.dart';
import 'package:javit/app/modules/widgets/widget_controls.dart';
import 'package:javit/app/modules/widgets/widget_style.dart';
import 'package:javit/app/modules/widgets/widget_surfaces.dart';

void main() => runApp(const UiCatalogApp());

class UiCatalogApp extends StatefulWidget {
  const UiCatalogApp({super.key});
  @override
  State<UiCatalogApp> createState() => _UiCatalogAppState();
}

class _UiCatalogAppState extends State<UiCatalogApp> {
  bool dark = false;
  @override
  Widget build(BuildContext context) => GetMaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppStyle.theme(Brightness.light), darkTheme: AppStyle.theme(Brightness.dark),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: UiCatalog(onToggleTheme: () => setState(() => dark = !dark)),
  );
}

class UiCatalog extends StatefulWidget {
  const UiCatalog({super.key, this.onToggleTheme});
  final VoidCallback? onToggleTheme;
  @override
  State<UiCatalog> createState() => _UiCatalogState();
}

class _UiCatalogState extends State<UiCatalog> {
  final form = GlobalKey<FormState>();
  String choice = 'Balanced';
  bool enabled = true;
  int presses = 0;

  void press() => setState(() => presses++);

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    final palette = {'Body': AppColor.body, 'Panel': AppColor.panel, 'Border': AppColor.border,
      'Selected': AppColor.selected, 'Hover': AppColor.hover, 'Muted': AppColor.muted, 'Accent': AppColor.accent};
    return Scaffold(
      backgroundColor: AppColor.body,
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 880), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 8, children: [
              const Text('JavIt / Shared components', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              AppButton(icon: const HugeIcon(icon: HugeIcons.strokeRoundedDarkMode, size: AppStyle.iconSize), label: 'Toggle theme', onPressed: widget.onToggleTheme),
            ]),
            const SizedBox(height: 6),
            Text('Real Flutter widgets · radius 6 · controls 30 · inputs 32 · icons 32', style: TextStyle(color: AppColor.muted)),
            const SizedBox(height: 24),
            const AppSectionHeading(title: 'Colors'),
            const SizedBox(height: 10),
            Wrap(spacing: 12, runSpacing: 12, children: [for (final entry in palette.entries) SizedBox(width: 96, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 38, decoration: BoxDecoration(color: entry.value, borderRadius: BorderRadius.circular(AppStyle.radius), border: Border.all(color: AppColor.border))),
                const SizedBox(height: 6), Text(entry.key),
              ],
            ))]),
            const SizedBox(height: 24),
            AppSectionHeading(title: 'Buttons', detail: '$presses actions'),
            const SizedBox(height: 10),
            AppPanel(bordered: true, child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AppButton(label: 'Edit profile', icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: AppStyle.iconSize), onPressed: press),
              AppButton(label: 'Save changes', variant: AppButtonVariant.filled, onPressed: press),
              AppButton(label: 'Cancel', variant: AppButtonVariant.outlined, onPressed: press),
              AppButton(label: 'Add todo', icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: AppStyle.iconSize), variant: AppButtonVariant.tonal, onPressed: press),
              const AppButton(label: 'Disabled', variant: AppButtonVariant.filled, onPressed: null),
              AppIconButton(icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh01, size: AppStyle.iconSize), tooltip: 'Refresh', onPressed: press),
              const AppIconButton(icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: AppStyle.iconSize), tooltip: 'Unavailable', onPressed: null),
            ])),
            const SizedBox(height: 24),
            const AppSectionHeading(title: 'Inputs & selection'),
            const SizedBox(height: 10),
            AppPanel(bordered: true, child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const AppTextField(placeholder: 'Search your library', prefix: Padding(padding: EdgeInsets.only(left: 10), child: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: AppStyle.iconSize))),
              const SizedBox(height: 10),
              AppTextFormField(placeholder: 'Profile name', validator: (value) => value == null || value.trim().isEmpty ? 'Name is required' : null),
              const SizedBox(height: 10),
              const AppTextField(placeholder: 'PIN', obscureText: true, enableSuggestions: false, autocorrect: false),
              const SizedBox(height: 10),
              AppDropdown<String>(value: choice, isExpanded: true, items: [for (final value in ['Strict', 'Balanced', 'Broad']) DropdownMenuItem(value: value, child: Text(value))],
                onChanged: (value) { if (value != null) setState(() => choice = value); }),
              const SizedBox(height: 10),
              Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Notifications'), Switch(value: enabled, onChanged: (value) => setState(() => enabled = value)),
                ChoiceChip(label: const Text('Selected'), selected: enabled, onSelected: (value) => setState(() => enabled = value)),
                AppButton(label: 'Validate form', onPressed: () => form.currentState!.validate()),
              ]),
            ]))),
            const SizedBox(height: 24),
            const AppSectionHeading(title: 'Dialogs'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              AppButton(label: 'Edit dialog', variant: AppButtonVariant.outlined, onPressed: () => showDialog<void>(context: context, builder: (context) => AppDialog(
                title: const Text('Edit profile'), content: const AppTextField(placeholder: 'Your name'), actions: [
                  AppButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
                  AppButton(label: 'Save', variant: AppButtonVariant.filled, onPressed: () => Navigator.pop(context)),
                ],
              ))),
              AppButton(label: 'Confirmation', onPressed: () => showDialog<void>(context: context, builder: (context) => AppConfirmDialog(
                title: const Text('Delete this item?'), content: const Text('This action removes the selected item.'), actions: [
                  AppDialogAction(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  AppDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context), child: const Text('Delete')),
                ],
              ))),
            ]),
          ],
        )),
      ))),
    );
  }
}
