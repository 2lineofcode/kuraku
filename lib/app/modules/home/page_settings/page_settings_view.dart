import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../env.g.dart';
import '../../../core/app_color.dart';
import '../../../core/app_pref.dart';
import '../../../core/app_translations.dart';
import '../../../utils/helper.dart';
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
        : uiAppLog(context).scrollVertical(),
    );
  }

  Widget uiMainContent(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(builder: (context, constraints) {
            final preferences = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _section(Icons.tune_rounded, 'Appearance'.tr, 'Make JavIt feel at home.'.tr, [
                buildThemeSetting(),
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
                )), description: 'Keep the sidebar compact.'.tr),
              ]),
              const SizedBox(height: 16),
              _section(Icons.play_circle_outline_rounded, 'Playback & Search'.tr, 'Your player, shortcuts and browsing preferences.'.tr, [
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
                  items: ['NJAV', 'MISSAV', 'JAVMOST', 'SEXTB', 'JAVGURU'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    controller.tecDefaultSearchEngine.value = value;
                    AppPref.setDefaultSearchEngine(value);
                  },
                ))),
                _settingRow('Daily relapse limit'.tr, _numberField(controller.tecAppMaxColi,
                  onSubmitted: (_) => controller.saveRelapseLimit(),
                  suffix: IconButton(
                    tooltip: 'Save daily limit (0 blocks playback)'.tr,
                    icon: const Icon(Icons.check_rounded, size: 18),
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
              const SizedBox(height: 16),
              buildVisualSearchSettings(),
              const SizedBox(height: 16),
              _buildStorage(),
            ]);
            final details = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _section(Icons.info_outline_rounded, 'Application Info'.tr, 'Your library at a glance.'.tr, [
                Obx(() => Column(children: [
                  _infoRow('Version'.tr, '${Env.appVer}'),
                  Divider(height: 24, color: AppColor.border),
                  _infoRow('Total Library'.tr, '${controller.totalLibrary.value}'),
                  _infoRow('Total Video'.tr, controller.totalVideos.value.numberFormat()),
                  _infoRow('Library size'.tr, controller.totalFilesize.value.toFileSizeFormat()),
                  _infoRow('Last Relapse'.tr, controller.lastRelapse.value),
                  Divider(height: 24, color: AppColor.border),
                  _infoRow('R18 Total Video'.tr, controller.r18TotalVideo.value.numberFormat()),
                  _infoRow('R18 Version'.tr, '${controller.dbR18Version.value}'),
                ])),
              ]),
              const SizedBox(height: 16),
              _section(Icons.dashboard_customize_outlined, 'Utilities'.tr, 'Useful places and maintenance.'.tr, [
                _action(Icons.receipt_long_outlined, 'Open App Log'.tr, controller.onOpenAppLog),
                _action(Icons.keyboard_outlined, 'Keyboard Shortcuts'.tr, () => HelperOpener.openKeyboardShortcuts()),
                _action(Icons.folder_outlined, 'Go App Folder'.tr, () => HelperOpener.openFolder(controller.appSetting.appPath)),
                _action(Icons.folder_copy_outlined, 'Go Cache Folder'.tr, () => HelperOpener.openFolder('/Users/adit/Library/Caches/net_thumbnail')),
                Divider(height: 20, color: AppColor.border),
                _action(Icons.sync_rounded, 'Update R18 DB'.tr, controller.updateR18DB),
              ]),
            ]);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text('Personalize your experience and manage your library.'.tr, style: TextStyle(fontSize: 13, color: AppColor.muted)),
              ),
              if (constraints.maxWidth >= 840)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: preferences),
                  const SizedBox(width: 20),
                  SizedBox(width: 300, child: details),
                ])
              else ...[preferences, const SizedBox(height: 16), details],
            ]);
          }),
        ),
      ),
    );
  }

  Widget _section(IconData icon, String title, String subtitle, List<Widget> children) => Material(
    color: AppColor.panel,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColor.border)),
    child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppColor.accent.withValues(alpha: .09), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 19, color: AppColor.accent),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(fontSize: 11, color: AppColor.muted)),
        ])),
      ]),
      const SizedBox(height: 18),
      ...children,
    ])),
  );

  Widget _settingRow(String label, Widget control, {String? description}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: LayoutBuilder(builder: (context, constraints) {
      final title = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        if (description != null) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(description, style: TextStyle(fontSize: 11, color: AppColor.muted)),
        ),
      ]);
      final input = Semantics(label: label, child: control);
      if (constraints.maxWidth < 300) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 8), input]);
      return Row(children: [Expanded(child: title), const SizedBox(width: 16), SizedBox(width: constraints.maxWidth * .52, child: input)]);
    }),
  );

  Widget _dropdown<T>({required T value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(color: AppColor.body, border: Border.all(color: AppColor.border), borderRadius: BorderRadius.circular(8)),
    child: DropdownButtonHideUnderline(child: DropdownButton<T>(
      value: value, items: items, onChanged: onChanged,
      isExpanded: true, isDense: true, borderRadius: BorderRadius.circular(10),
      dropdownColor: AppColor.panel,
      style: Get.textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColor.text),
      icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColor.muted),
    )),
  );

  Widget _numberField(TextEditingController textController, {Widget? suffix, ValueChanged<String>? onChanged, ValueChanged<String>? onSubmitted}) => CupertinoTextField(
    controller: textController,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    style: Get.textTheme.bodyMedium?.copyWith(fontSize: 13, color: AppColor.text),
    decoration: BoxDecoration(color: AppColor.body, border: Border.all(color: AppColor.border), borderRadius: BorderRadius.circular(8)),
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

  Widget _action(IconData icon, String label, VoidCallback onTap) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    minLeadingWidth: 20, horizontalTitleGap: 10,
    dense: true, visualDensity: VisualDensity.compact,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    leading: Icon(icon, size: 18, color: AppColor.muted),
    title: Text(label, style: const TextStyle(fontSize: 12)),
    trailing: Icon(Icons.chevron_right_rounded, size: 16, color: AppColor.muted),
    onTap: onTap,
  );

  Widget _buildStorage() => _section(Icons.storage_rounded, 'Storage Usage'.tr, 'Space available across your drives.'.tr, [
    Obx(() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(alignment: Alignment.centerRight, child: TextButton.icon(
        onPressed: controller.isLoadingStorage.value ? null : controller.onRefreshStorage,
        icon: const Icon(Icons.refresh_rounded, size: 16), label: Text('Refresh'.tr),
      )),
      if (controller.isLoadingStorage.value)
        const Center(child: Padding(padding: EdgeInsets.all(12), child: CupertinoActivityIndicator()))
      else if (controller.storageList.isEmpty)
        Text('No storage detected'.tr, style: TextStyle(fontSize: 12, color: AppColor.muted))
      else for (final item in controller.storageList) _storageRow(item),
    ])),
  ]);

  Widget _storageRow(StorageUsage item) {
    final usedPct = item.usedPct.clamp(0, 100);
    final color = usedPct >= 90 ? Colors.redAccent : usedPct >= 80 ? Colors.orange : AppColor.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(item.isExternal ? Icons.sd_storage_outlined : Icons.computer_rounded, size: 18, color: AppColor.muted),
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
    return VStack(
      [
        HStack([
          IconButton(
            onPressed: () {
              controller.appLogMode.value = false;
            },
            icon: Icon(Icons.arrow_back_rounded),
          ).pOnly(right: 12),
          'APP LOG'.tr.text.bold.make(),
          Spacer(),

          CupertinoTextField(
            controller: controller.tecAppLogFilter,
            style: TextStyle(fontSize: 13, color: AppColor.text),
            placeholder: 'Filter logs...'.tr,
            placeholderStyle: TextStyle(fontSize: 12, color: Vx.neutral500),
            onChanged: (s) => controller.appLogKeyword.value = s,
          ).w(150).pOnly(right: 12),


          GestureDetector(
            onTapDown: (details) async {
              final value = await showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx, details.globalPosition.dy),
                items: [
                  PopupMenuItem(value: 'ALL', child: Text('ALL'.tr, style: TextStyle(fontSize: 12))),
                  PopupMenuItem(value: 'DEBUG', child: Text('DEBUG', style: TextStyle(fontSize: 12))),
                  PopupMenuItem(value: 'INFO', child: Text('INFO', style: TextStyle(fontSize: 12))),
                  PopupMenuItem(value: 'WARN', child: Text('WARN', style: TextStyle(fontSize: 12))),
                  PopupMenuItem(value: 'ERROR', child: Text('ERROR', style: TextStyle(fontSize: 12))),
                ],
              );

              if (value != null) {
                controller.appLogLevelSelected.value = value;
              }
            },
            child: Container(
              decoration: ExDecorator.box(borderColor: AppColor.border, fillColor: AppColor.container, borderRadius: 6),
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: HStack(
                [
                  Icon(CupertinoIcons.list_dash, size: 16).pOnly(right: 8),
                  Obx(
                    () => Text(
                      controller.appLogLevelSelected.value.isEmpty ? 'Select Level'.tr : controller.appLogLevelSelected.value.tr,
                      style: TextStyle(fontSize: 12, color: AppColor.text),
                    ),
                  ),
                ],
              ),
            ),
          ).w(100),
          
          8.widthBox,
          ExButtonText(
            label: 'Clear'.tr,
            labelSize: 11,
            height: 28,
            width: 60,
            onPressed: () => controller.clearAppLog(),
          ),
        ]).pOnly(bottom: 12),


        Obx(() {
          final logs = controller.filteredAppLogs;
          Color _badgeText(String level) {
            switch (level) {
              case 'DEBUG': return Color(0xFF60A5FA);
              case 'INFO': return Color(0xFF34D399);
              case 'WARN': return Color(0xFFF59E0B);
              case 'ERROR': return Color(0xFFEF4444);
              case 'OK': return Color(0xFF10B981);
              default: return Color(0xFF9CA3AF);
            }
          }

          Color _badgeBg(String level) {
            switch (level) {
              case 'DEBUG': return Color(0x332563EB);
              case 'INFO': return Color(0x3322C55E);
              case 'WARN': return Color(0x33F59E0B);
              case 'ERROR': return Color(0x33EF4444);
              case 'OK': return Color(0x3310B981);
              default: return Color(0x334B5563);
            }
          }

          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColor.border),
            ),
            child: VStack([
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                  border: Border(bottom: BorderSide(color: AppColor.border)),
                ),
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: HStack([
                  'TIME'.tr.text.size(11).semiBold.make().w(160),
                  'LEVEL'.tr.text.size(11).semiBold.make().w(84),
                  'MESSAGE'.tr.text.size(11).semiBold.make().expand(),
                ]),
              ),
              if (logs.isEmpty)
                'No app logs'.tr.text.size(12).make().p12()
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: logs.length,
                  itemBuilder: (c, index) {
                    final item = logs[index];
                    final level = controller.normalizeLogLevel(item.type);
                    final createdAt = (item.createdAt ?? '-').replaceAll('T', ' ').split('.').first;

                    return Container(
                      decoration: BoxDecoration(
                        color: index % 2 == 0 ? AppColor.container : AppColor.hover,
                        border: Border(
                          bottom: BorderSide(
                            color: AppColor.hover,
                            width: index == logs.length - 1 ? 0 : 1,
                          ),
                        ),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: HStack([
                        createdAt.text.size(11).make().w(160),
                        Container(
                          decoration: BoxDecoration(
                            color: _badgeBg(level),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          child: level.text.size(10).semiBold.color(_badgeText(level)).makeCentered(),
                        ).w(80),
                        (item.content ?? '-').text.size(12).make().pOnly(left: 12).onInkTap(() {
                          HelperMisc.copyToClipboard(item.content ?? '-', showToast: true, toastDuration: 500.milliseconds);
                        }).expand(),
                      ]),
                    );
                  },
                ),
            ]),
          );
        }),
      ],
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

  Widget buildVisualSearchSettings() => Container(
    decoration: BoxDecoration(color: AppColor.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColor.border)),
    padding: const EdgeInsets.all(20),
    width: double.infinity,
    child: Obx(() {
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
            child: Text('Visual Search'.tr, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          if (ready) Text('@{semanticEmbeddingCount} indexed • @{missing} pending'.trNamed({'semanticEmbeddingCount': '${controller.semanticEmbeddingCount.value}', 'missing': '$missing'}), style: const TextStyle(fontSize: 11)),
          ])),
          const SizedBox(width: 8),
          Tooltip(
            message: busy ? 'Keep completed work'.tr : ready ? (missing == 0 ? 'All videos are indexed'.tr : 'Index pending videos only'.tr) : 'Download and set up local search'.tr,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: busy ? controller.stopSemanticIndex : ready ? (missing > 0 ? controller.generateMissingEmbeddings : null) : controller.setupSemanticSearch,
              child: Text(busy ? 'Stop'.tr : ready ? 'Index'.tr : 'Set up'.tr, style: const TextStyle(fontSize: 11)),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Visual Search options'.tr,
            enabled: !busy,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.more_vert, size: 18),
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
    }),
  );

}
