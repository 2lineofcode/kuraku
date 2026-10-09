import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/app_color.dart';
import '../../../core/app_pin.dart';
import '../../../core/app_pref.dart';
import '../../../core/app_translations.dart';
import '../../../utils/helper.dart';
import '../../../utils/r18_updater.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_style.dart';
import '../../widgets/widget_surfaces.dart';
import '../home_controller.dart';
import 'page_settings_controller.dart';

class PageSettingsView extends GetView<PageSettingsController> {
  const PageSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Obx(
      () => controller.appLogMode.value == false
        ? uiMainContent(context).scrollVertical()
        : uiAppLog(context),
    );
  }

  Widget uiMainContent(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(builder: (context, constraints) {
            final preferences = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _section('Appearance'.tr, [
                buildThemeSetting(),
                buildAccentSetting(),
                buildLanguageSetting(),
                _settingRow('Mini Mode'.tr, Obx(() => Align(
                  alignment: Alignment.centerRight,
                  child: Switch.adaptive(
                    value: controller.appMiniMode.value,
                    onChanged: (value) {
                      controller.appMiniMode.value = value;
                      Get.find<HomeController>().sideMenuWidth.value = value ? 65 : 180;
                      AppPref.setAppHideSideMenu(value);
                    },
                  ),
                ))),
              ]),
              const SizedBox(height: 24),
              buildPinSetting(),
              const SizedBox(height: 24),
              _section('Playback & Search'.tr, [
                _settingRow('Default Player'.tr, Obx(() => _dropdown<String>(
                  value: controller.tecDefaultPlayer.value.isEmpty ? 'In App' : controller.tecDefaultPlayer.value,
                  items: ['In App', 'Default System'].map((value) => DropdownMenuItem(value: value, child: Text(value.tr))).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    controller.tecDefaultPlayer.value = value;
                    AppPref.setDefaultPlayer(value);
                  },
                ))),
                _settingRow('Search Engine'.tr, Obx(() => _dropdown<String>(
                  value: controller.tecDefaultSearchEngine.value.isEmpty ? 'NJAV' : controller.tecDefaultSearchEngine.value,
                  items: AppPref.searchEngines.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    controller.tecDefaultSearchEngine.value = value;
                    AppPref.setDefaultSearchEngine(value);
                  },
                ))),
                _settingRow('Daily relapse limit'.tr, _numberField(controller.tecAppMaxColi,
                  onSubmitted: (_) => controller.saveRelapseLimit(),
                  suffix: AppIconButton(
                    tooltip: 'Save daily limit (0 blocks playback)'.tr,
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedTick02, size: AppStyle.iconSize),
                    onPressed: controller.saveRelapseLimit,
                  ),
                )),
                Text('0 blocks playback. Press Enter or ✓ to save.'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted)),
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 12),
                  child: Text('In-app seek intervals'.tr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                LayoutBuilder(builder: (context, constraints) {
                  final fields = [
                    _seekField('Small Seek'.tr, controller.tecPlayerSeekShort, AppPref.setPlayerSeekShort),
                    _seekField('Medium Seek'.tr, controller.tecPlayerSeekMid, AppPref.setPlayerSeekMid),
                    _seekField('Long Seek'.tr, controller.tecPlayerSeekLong, AppPref.setPlayerSeekLong),
                  ];
                  return Wrap(spacing: 12, runSpacing: 12, children: fields.map((field) => SizedBox(
                    width: constraints.maxWidth < 340 ? constraints.maxWidth : (constraints.maxWidth - 24) / 3,
                    child: field,
                  )).toList());
                }),
              ]),
              const SizedBox(height: 24),
              buildVisualSearchSettings(),
            ]);
            final info = _section('Application Info'.tr, [
              Obx(() => Column(children: [
                _infoRow('Version'.tr, controller.appVersion.value),
                Divider(height: 24, color: AppColor.border),
                _infoRow('Total Library'.tr, '${controller.totalLibrary.value}'),
                _infoRow('Total Video'.tr, controller.totalVideos.value.numberFormat()),
                _infoRow('Total Albums'.tr, controller.totalAlbums.value.numberFormat()),
                _infoRow('Total Images'.tr, controller.totalImages.value.numberFormat()),
                _infoRow('Library size'.tr, controller.totalFilesize.value.toFileSizeFormat()),
                _infoRow('Last Relapse'.tr, controller.lastRelapse.value),
                Divider(height: 24, color: AppColor.border),
                _infoRow('R18 Total Video'.tr, controller.r18TotalVideo.value.numberFormat()),
                _infoRow('R18 Version'.tr, '${controller.dbR18Version.value}'),
              ])),
            ]);
            final utilities = _section('Utilities'.tr, [
              Obx(() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _action(HugeIcons.strokeRoundedArchive01, 'Export Backup'.tr, controller.backupBusy.value ? null : controller.exportBackup),
                _action(HugeIcons.strokeRoundedArchive01, 'Restore Backup'.tr, controller.backupBusy.value || controller.restorePending.value ? null : controller.restoreBackup),
                if (controller.backupBusy.value) const CupertinoActivityIndicator(),
                if (controller.restorePending.value) Text('Restore prepared. Close and reopen the app to apply it.'.tr, style: const TextStyle(fontSize: 11)),
              ])),
              _action(HugeIcons.strokeRoundedNote, 'Open App Log'.tr, controller.onOpenAppLog),
              _action(HugeIcons.strokeRoundedKeyboard, 'Keyboard Shortcuts'.tr, () => HelperOpener.openKeyboardShortcuts()),
              _action(HugeIcons.strokeRoundedFolderCog, 'Go App Folder'.tr, () => HelperOpener.openFolder(controller.appSetting.appPath)),
              _action(HugeIcons.strokeRoundedFolderKanban, 'Go Cache Folder'.tr, () async {
                try {
                  final directory = await IOFileSystem.createDirectory('net_thumbnail');
                  await HelperOpener.openFolder(directory.path);
                } catch (e) {
                  await HelperToast.error('$e');
                }
              }),
              Divider(height: 20, color: AppColor.border),
              Obx(() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _action(HugeIcons.strokeRoundedLoading03, 'Update R18 DB'.tr, R18Updater.busy.value ? null : controller.updateR18DB),
                if (R18Updater.busy.value) LinearProgressIndicator(
                  value: R18Updater.progress.value < 0 ? null : R18Updater.progress.value,
                  semanticsLabel: 'Update R18 DB'.tr,
                ),
                if (R18Updater.status.value.isNotEmpty) Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(R18Updater.status.value, style: TextStyle(fontSize: 11, color: AppColor.muted)),
                ),
              ])),
            ]);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (constraints.maxWidth >= 640)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 320, child: info),
                  const SizedBox(width: 32),
                  Expanded(child: utilities),
                ])
              else ...[info, const SizedBox(height: 20), utilities],
              const SizedBox(height: 24),
              preferences,
              const SizedBox(height: 24),
              _buildStorage(),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _sectionBackground(Widget child) => AppPanel(child: child);

  Widget buildPinSetting() => _section('Security'.tr, [
    _settingRow('PIN lock'.tr, Obx(() => Align(
      alignment: Alignment.centerRight,
      child: Switch.adaptive(
        key: const ValueKey('app-pin-switch'),
        value: controller.appPinEnabled.value,
        onChanged: (value) => _editPin(disable: !value),
      ),
    ))),
    Obx(() => controller.appPinEnabled.value ? _settingRow('PIN'.tr, Align(
      alignment: Alignment.centerRight,
      child: AppButton(onPressed: _editPin, child: Text('Change PIN'.tr)),
    )) : const SizedBox.shrink()),
  ]);

  Future<void> _editPin({bool disable = false}) async {
    final saved = await showCupertinoDialog<bool>(
      context: Get.context!,
      barrierDismissible: false,
      builder: (context) => AppPinForm(
        disable: disable,
        onSuccess: () => Navigator.of(context).pop(true),
      ),
    );
    if (saved == true) controller.appPinEnabled.value = AppPref.getAppPinEnabled();
  }

  Widget _section(String title, List<Widget> children, {Widget? action}) => AppPanel(child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppSectionHeading(title: title, action: action),
      const SizedBox(height: 8),
      ...children,
    ],
  ));

  Widget _settingRow(String label, Widget control, {String? description}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: LayoutBuilder(builder: (context, constraints) {
      final title = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        if (description != null) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(description, style: TextStyle(fontSize: 11, color: AppColor.muted)),
        ),
      ]);
      final input = Semantics(label: label, child: control);
      if (constraints.maxWidth < 420) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 8), input]);
      return Row(children: [Expanded(child: title), const SizedBox(width: 16), SizedBox(width: 320, child: input)]);
    }),
  );

  Widget _dropdown<T>({required T value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) => AppDropdown<T>(
    value: value, items: items, onChanged: onChanged, isExpanded: true,
  );

  Widget _numberField(TextEditingController textController, {Widget? suffix, ValueChanged<String>? onChanged, ValueChanged<String>? onSubmitted}) => AppTextField(
    controller: textController,
    style: TextStyle(color: AppColor.text),
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    suffix: suffix, onChanged: onChanged, onSubmitted: onSubmitted,
  );

  Widget _seekField(String label, TextEditingController textController, ValueChanged<int> save) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 11, color: AppColor.muted)),
      const SizedBox(height: 8),
      Semantics(label: label, child: _numberField(textController,
        suffix: Padding(padding: const EdgeInsets.only(right: 10), child: Text('Seconds'.tr, style: TextStyle(fontSize: 10, color: AppColor.muted))),
        onChanged: (value) => save(int.tryParse(value) ?? 0),
      )),
    ],
  );

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(label, style: TextStyle(fontSize: 11, color: AppColor.muted))),
      const SizedBox(width: 12),
      Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _action(List<List<dynamic>> icon, String label, VoidCallback? onTap) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      minLeadingWidth: 20, horizontalTitleGap: 10,
      dense: true, visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: HugeIcon(icon: icon, size: AppStyle.iconSize, color: AppColor.muted),
      title: Text(label, style: const TextStyle(fontSize: 12)),
      trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: AppStyle.iconSize, color: AppColor.muted),
      onTap: onTap,
    ),
  );

  Widget _buildStorage() => _section('Storage Usage'.tr, [
    Obx(() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (controller.isLoadingStorage.value)
        const Center(child: Padding(padding: EdgeInsets.all(12), child: CupertinoActivityIndicator()))
      else if (controller.storageList.isEmpty)
        Text('No storage detected'.tr, style: TextStyle(fontSize: 12, color: AppColor.muted))
      else for (final item in controller.storageList) _storageRow(item),
    ])),
  ], action: Obx(() => AppButton(
    style: TextButton.styleFrom(
      foregroundColor: AppColor.muted,
      textStyle: Get.textTheme.labelSmall?.copyWith(fontSize: 11),
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: controller.isLoadingStorage.value ? null : controller.onRefreshStorage,
    icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh01, size: AppStyle.iconSize), child: Text('Refresh'.tr),
  )));

  Widget _storageRow(StorageUsage item) {
    final usedPct = item.usedPct.clamp(0, 100);
    final color = usedPct >= 90 ? Colors.redAccent : usedPct >= 80 ? Colors.orange : AppColor.accentForeground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          HugeIcon(icon: item.isExternal ? HugeIcons.strokeRoundedArchive01 : HugeIcons.strokeRoundedComputer, size: AppStyle.iconSize, color: AppColor.muted),
          const SizedBox(width: 8),
          Expanded(child: Text('${item.label}${item.isExternal ? ' (External)'.tr : ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          Text('${usedPct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, color: color)),
        ]),
        const SizedBox(height: 5),
        Text(item.path, style: TextStyle(fontSize: 10, color: AppColor.muted)),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: usedPct / 100, minHeight: 5, borderRadius: BorderRadius.circular(4), color: color, backgroundColor: AppColor.border),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          Text('Available: @{toFileSizeFormat}'.trNamed({'toFileSizeFormat': item.freeBytes.toFileSizeFormat()}), style: TextStyle(fontSize: 11, color: color)),
          Text('Used: @{toFileSizeFormat}'.trNamed({'toFileSizeFormat': (item.totalBytes - item.freeBytes).toFileSizeFormat()}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
          Text('Total: @{toFileSizeFormat}'.trNamed({'toFileSizeFormat': item.totalBytes.toFileSizeFormat()}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
        ]),
      ]),
    );
  }

  Widget uiAppLog(BuildContext context) {
    AppColor.dependOn(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final heading = Row(children: [
          AppIconButton(
            tooltip: 'Back'.tr,
            onPressed: () => controller.appLogMode.value = false,
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft02, size: AppStyle.iconSize),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('APP LOG'.tr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Obx(() => Text('@{visible} of @{total} logs'.trNamed({
              'visible': '${controller.filteredAppLogs.length}', 'total': '${controller.appLogData.length}',
            }), style: TextStyle(fontSize: 11, color: AppColor.muted))),
          ])),
        ]);
        final filters = Row(children: [
          Expanded(child: AppTextField(
            controller: controller.tecAppLogFilter,
            placeholder: 'Filter logs...'.tr,
            prefix: Padding(padding: const EdgeInsets.only(left: 10),
              child: Icon(Icons.search, size: AppStyle.iconSize, color: AppColor.muted)),
            clearButtonMode: OverlayVisibilityMode.editing,
            onChanged: (value) => controller.appLogKeyword.value = value,
          )),
          const SizedBox(width: 8),
          SizedBox(width: 100, child: Obx(() => AppDropdown<String>(
            value: controller.appLogLevelSelected.value,
            items: [for (final level in ['ALL', 'DEBUG', 'INFO', 'WARN', 'ERROR'])
              DropdownMenuItem(value: level, child: Text(level.tr)),
            ],
            onChanged: (value) {
              if (value != null) controller.appLogLevelSelected.value = value;
            },
          ))),
          const SizedBox(width: 8),
          Obx(() => AppButton(
            label: 'Clear'.tr,
            variant: AppButtonVariant.outlined,
            onPressed: controller.appLogData.isEmpty ? null : controller.clearAppLog,
          )),
        ]);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (constraints.maxWidth < 680) ...[heading, const SizedBox(height: 12), filters]
          else Row(children: [Expanded(child: heading), const SizedBox(width: 24), SizedBox(width: 380, child: filters)]),
          const SizedBox(height: 16),
          Expanded(child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColor.panel,
              borderRadius: BorderRadius.circular(AppStyle.radius + 2),
              border: Border.all(color: AppColor.border),
            ),
            child: Column(children: [
              if (!compact) Container(
                color: AppColor.container,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: DefaultTextStyle.merge(style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColor.muted),
                  child: Row(children: [
                    SizedBox(width: 100, child: Text('TIME'.tr)),
                    SizedBox(width: 76, child: Text('LEVEL'.tr)),
                    Expanded(child: Text('MESSAGE'.tr)),
                  ])),
              ),
              Expanded(child: Obx(() {
                final logs = controller.filteredAppLogs;
                if (logs.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.article_outlined, size: 32, color: AppColor.muted),
                  const SizedBox(height: 12),
                  Text((controller.appLogData.isEmpty ? 'No app logs' : 'No matching items').tr,
                    style: TextStyle(fontSize: 12, color: AppColor.muted)),
                ]));
                return ListView.separated(
                  itemCount: logs.length,
                  separatorBuilder: (context, index) => Divider(height: 1, thickness: .5, color: AppColor.border),
                  itemBuilder: (context, index) {
                    final item = logs[index];
                    final level = controller.normalizeLogLevel(item.type);
                    final dark = Theme.of(context).brightness == Brightness.dark;
                    final color = switch (level) {
                      'DEBUG' => dark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
                      'WARN' => dark ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
                      'ERROR' => Theme.of(context).colorScheme.error,
                      'INFO' || 'OK' => AppColor.success,
                      _ => AppColor.muted,
                    };
                    final date = DateTime.tryParse(item.createdAt ?? '');
                    final time = date == null ? item.createdAt ?? '-' :
                      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
                    final timestamp = Tooltip(message: item.createdAt ?? '-', child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(time, style: TextStyle(fontSize: 11, color: AppColor.muted, fontFeatures: const [FontFeature.tabularFigures()])),
                        if (date != null) Text(date.toString().split(' ').first, style: TextStyle(fontSize: 9, color: AppColor.muted)),
                      ],
                    ));
                    final badge = Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(4)),
                      child: Text(level, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
                    );
                    final message = Tooltip(message: 'Copy message'.tr, child: InkWell(
                      onTap: () => HelperMisc.copyToClipboard(item.content ?? '-', showToast: true, toastDuration: 500.milliseconds),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(item.content ?? '-', style: const TextStyle(fontSize: 12, height: 1.5))),
                    ));
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: compact ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [Expanded(child: timestamp), badge]),
                        const SizedBox(height: 6),
                        message,
                      ]) : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 100, child: timestamp),
                        SizedBox(width: 76, child: Align(alignment: Alignment.centerLeft, child: badge)),
                        Expanded(child: message),
                      ]),
                    );
                  },
                );
              })),
            ]),
          )),
        ]);
      }),
    );
  }
  Widget buildLanguageSetting() => _settingRow('Language'.tr, Obx(() => _dropdown<String>(
    value: controller.appLanguage.value,
    items: AppTranslations.languages.entries.map((language) => DropdownMenuItem(value: language.key, child: Text(language.value))).toList(),
    onChanged: (code) { if (code != null) controller.setLanguage(code); },
  )));

  Widget buildThemeSetting() => Obx(() => _settingRow('Theme'.tr, _dropdown<AppTheme>(
    value: controller.appTheme.value,
    items: AppTheme.values.map((theme) => DropdownMenuItem(value: theme, child: Text(theme.label))).toList(),
    onChanged: (theme) { if (theme != null) controller.setTheme(theme); },
  ), description: controller.appTheme.value == AppTheme.schedule ? 'Light 06:00–17:00 · Dark 17:00–06:00'.tr : null));

  Future<void> pickAccent() async {
    var hsv = HSVColor.fromColor(colorFromHex(controller.tecAppAccent.text.trim()) ?? AppColor.accent);
    final picked = await showDialog<Color>(context: Get.context!, builder: (context) => StatefulBuilder(
      builder: (context, setState) => AppDialog(
        maxWidth: 360,
        title: Text('Accent color'.tr),
        content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(borderRadius: BorderRadius.circular(AppStyle.radius), child: AspectRatio(
            aspectRatio: 1.6,
            child: ColorPickerArea(hsv, (value) => setState(() => hsv = value), PaletteType.hsvWithHue),
          )),
          const SizedBox(height: 16),
          for (final track in [TrackType.hue, TrackType.alpha]) ...[
            Row(children: [
              Expanded(child: Text((track == TrackType.hue ? 'Hue' : 'Opacity').tr, style: const TextStyle(fontSize: 11))),
              Text(track == TrackType.hue ? '${hsv.hue.round()}°' : '${(hsv.alpha * 100).round()}%',
                style: TextStyle(fontSize: 11, color: AppColor.muted)),
            ]),
            Semantics(label: (track == TrackType.hue ? 'Hue' : 'Opacity').tr, child: SizedBox(
              height: 32,
              child: ColorPickerSlider(track, hsv, (value) => setState(() => hsv = value), displayThumbColor: true),
            )),
            const SizedBox(height: 8),
          ],
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(
            color: AppColor.body, borderRadius: BorderRadius.circular(AppStyle.radius), border: Border.all(color: AppColor.border),
          ), child: Row(children: [
            ColorIndicator(hsv, width: 32, height: 32),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Preview'.tr, style: TextStyle(fontSize: 10, color: AppColor.muted)),
              SelectableText(colorToHex(hsv.toColor(), includeHashSign: true), style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            ])),
          ])),
        ]),
        actions: [
          AppButton(label: 'Cancel'.tr, onPressed: () => Navigator.pop(context)),
          AppButton(label: 'Save'.tr, variant: AppButtonVariant.outlined, onPressed: () => Navigator.pop(context, hsv.toColor())),
        ],
      ),
    ));
    if (picked == null || controller.isClosed) return;
    controller.tecAppAccent.text = colorToHex(picked, enableAlpha: picked.a < 1);
    await controller.setAccent();
  }

  Widget buildAccentSetting() => Obx(() => _settingRow('Accent color'.tr, Row(children: [
    AppIconButton(tooltip: 'Pick accent color'.tr, onPressed: pickAccent,
      icon: ColorIndicator(HSVColor.fromColor(AppColor.accent), width: 20, height: 20)),
    const SizedBox(width: 8),
    Expanded(child: AppTextField(controller: controller.tecAppAccent,
      placeholder: colorToHex(AppColor.accent, includeHashSign: true, enableAlpha: AppColor.accent.a < 1),
      decoration: InputDecoration(errorText: controller.appAccentError.value.isEmpty ? null : controller.appAccentError.value),
      onSubmitted: (_) => controller.setAccent(),
    )),
    AppIconButton(tooltip: 'Save'.tr, icon: const Icon(Icons.check, size: AppStyle.iconSize), onPressed: () => controller.setAccent()),
    AppIconButton(tooltip: 'Reset accent color'.tr, icon: const Icon(Icons.restart_alt, size: AppStyle.iconSize), onPressed: () => controller.setAccent(reset: true)),
  ])));

  Widget buildVisualSearchSettings() => _sectionBackground(Obx(() {
    final ready = controller.semanticReady.value;
    final busy = controller.semanticBusy.value;
    final missing = controller.semanticMissingCount.value;
    final status = controller.semanticStatus.value;
    final showStatus = status.isNotEmpty && (busy || !controller.semanticStatusIsRoutine.value);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Tooltip(
          message: 'Local visual search · English queries · One frame per video.\nSetup: ~155 MB + runtime, Python 3.12–3.14, macOS 14+, FFmpeg.\nCLIP ViT-B/32 INT8 · MIT license.'.tr,
          child: Text('Visual Search'.tr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        if (ready) Text('@{semanticEmbeddingCount} indexed • @{missing} pending'.trNamed({'semanticEmbeddingCount': '${controller.semanticEmbeddingCount.value}', 'missing': '$missing'}), style: const TextStyle(fontSize: 11)),
        ])),
        const SizedBox(width: 8),
        Tooltip(
          message: busy ? 'Keep completed work'.tr : ready ? (missing == 0 ? 'All videos are indexed'.tr : 'Index pending videos only'.tr) : 'Download and set up local search'.tr,
          child: AppButton(variant: AppButtonVariant.outlined,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: busy ? controller.stopSemanticIndex : ready ? (missing > 0 ? controller.generateMissingEmbeddings : null) : controller.setupSemanticSearch,
            child: Text(busy ? 'Stop'.tr : ready ? 'Index'.tr : 'Set up'.tr, style: const TextStyle(fontSize: 11)),
          ),
        ),
        PopupMenuButton<String>(
          popUpAnimationStyle: AnimationStyle.noAnimation,
          tooltip: 'Visual Search options'.tr,
          enabled: !busy,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical, size: AppStyle.iconSize),
          style: IconButton.styleFrom(minimumSize: const Size(28, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          onSelected: (value) async {
            switch (value) {
              case 'refresh': await controller.refreshSemanticStatus(); break;
              case 'repair': await controller.setupSemanticSearch(); break;
              case 'rebuild': await controller.reindexAllEmbeddings(); break;
            }
          },
          itemBuilder: (_) => [
            if (ready) PopupMenuItem(value: 'refresh', child: Text('Refresh status'.tr)),
            PopupMenuItem(value: 'repair', child: Text('Repair setup'.tr)),
            if (ready) PopupMenuItem(value: 'rebuild', child: Text('Rebuild frames & index'.tr)),
          ],
        ),
      ]),
      if (busy) Padding(
        padding: const EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(
          minHeight: 2,
          value: controller.semanticProgress.value < 0 ? null : controller.semanticProgress.value.clamp(0, 1),
          semanticsLabel: 'Visual Search progress'.tr,
        ),
      ),
      if (showStatus) Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Tooltip(message: status, child: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
      ),
    ]);
  }));

}
