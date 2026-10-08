import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../../core/app_color.dart';
import '../../../core/app_translations.dart';
import '../../../data/database/db_gamification.dart';
import '../../../utils/helper_badge.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_style.dart';
import '../../widgets/widget_surfaces.dart';
import 'page_profile_controller.dart';

class PageProfileView extends GetView<PageProfileController> {
  const PageProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Obx(() {
      if (controller.isLoading.value) return const Center(child: CupertinoActivityIndicator());
      if (controller.error.value.isNotEmpty) {
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(controller.error.value),
          const SizedBox(height: 12),
          AppButton(onPressed: controller.onRefresh, child: Text('Retry'.tr, style: const TextStyle(fontSize: 12))),
        ]));
      }
      final home = controller.home;
      final profile = home.profile.value;
      final watch = Duration(seconds: profile.totalWatchDuration ?? 0);
      final achievements = home.achievementProgress.toList();
      final summary = home.gamification.value;
      final filtered = achievements.where((item) =>
        (controller.achievementGroup.value == 'All' || item.group == controller.achievementGroup.value) &&
        (controller.achievementFilter.value == 'All' || item.isUnlocked == (controller.achievementFilter.value == 'Unlocked'))).toList();
      final goals = achievements.where((item) => !item.isUnlocked && ['Collection', 'Curation', 'Exploration'].contains(item.group)).take(3).toList();
      return SingleChildScrollView(
        key: const PageStorageKey('profile'),
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: LayoutBuilder(builder: (context, constraints) => Obx(() {
              final wide = constraints.maxWidth >= 700;
              final columns = constraints.maxWidth >= 700 ? 4 : constraints.maxWidth >= 320 ? 2 : 1;
              final statWidth = (constraints.maxWidth - 24 - (columns - 1) * 12) / columns;
              final panelWidth = wide ? (constraints.maxWidth - 48) / 2 : constraints.maxWidth - 24;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: AppColor.container, border: Border.all(color: AppColor.border), borderRadius: BorderRadius.circular(6)),
                      child: HugeIcon(icon: HugeIcons.strokeRoundedUser, size: AppStyle.iconSize, color: AppColor.muted),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(profile.name?.trim().isNotEmpty == true ? profile.name! : 'Your profile'.tr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('Member since @{createdAt}'.trNamed({'createdAt': '${_date(profile.createdAt)}'}), style: TextStyle(fontSize: 12, color: AppColor.muted)),
                    ])),
                    if (wide)
                      _editButton(context),
                  ]),
                  if (!wide)
                    Padding(padding: const EdgeInsets.only(top: 12), child: _editButton(context)),
                  if (controller.notice.value.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(controller.notice.value, style: TextStyle(fontSize: 12, color: AppColor.success)),
                  ],
                ])),
                const SizedBox(height: 24),
                _surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    HugeIcon(icon: HugeIcons.strokeRoundedAward01, size: 28, color: AppColor.accentForeground),
                    Text('Level @{level}'.trNamed({'level': '${summary?.level ?? 1}'}), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    Text((summary?.rank ?? 'New Explorer').tr, style: TextStyle(fontSize: 13, color: AppColor.accentForeground)),
                    Text('@{xp} XP earned'.trNamed({'xp': '${summary?.xp ?? 0}'}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
                  ]),
                  const SizedBox(height: 16),
                  _progress(((summary?.levelXp ?? 0) / 500 * 100).toInt(), AppColor.accentForeground),
                  const SizedBox(height: 8),
                  Text('@{xp}/500 XP · Next level: @{level}'.trNamed({'xp': '${summary?.levelXp ?? 0}', 'level': '${(summary?.level ?? 1) + 1}'}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
                  const SizedBox(height: 6),
                  Text('Earn XP once per milestone. Your unlocked achievements and level stay with you.'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted)),
                ])),
                const SizedBox(height: 24),
                _heading('Activity overview'.tr),
                _surface(Wrap(spacing: 12, runSpacing: 12, children: [
                  _stat('Videos'.tr, '${home.totalVideo.value}', HugeIcons.strokeRoundedFilm01, statWidth),
                  _stat('Watch time'.tr, '@{hours}h @{minutes}m'.trNamed({'hours': '${watch.inHours}', 'minutes': '${watch.inMinutes.remainder(60)}'}), HugeIcons.strokeRoundedClock01, statWidth),
                  _stat('Current streak'.tr, '@{streakDays} days'.trNamed({'streakDays': '${home.streakDays.value}'}), HugeIcons.strokeRoundedFire, statWidth),
                  _stat('Total relapse'.tr, '@{totalRelapse} times'.trNamed({'totalRelapse': '${controller.totalRelapse.value}'}), HugeIcons.strokeRoundedClock01, statWidth),
                ])),
                const SizedBox(height: 24),
                _heading('Your collection DNA'.tr),
                _surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 20, runSpacing: 12, children: [
                    for (final entry in {'favorites': 'Favorites', 'playlists': 'Playlists', 'studios': 'Studios', 'actresses': 'Actresses', 'categories': 'Categories'}.entries)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('${summary?.stats[entry.key] ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Text(entry.value.tr, style: TextStyle(fontSize: 11, color: AppColor.muted)),
                      ]),
                  ]),
                  const SizedBox(height: 12),
                  Text('Based on your active library metadata and non-empty playlists.'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted)),
                ])),
                if (goals.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _heading('Next milestones'.tr, detail: 'A little closer with every discovery'.tr),
                  _surface(Column(children: [for (final item in goals) _goal(item)])),
                ],
                const SizedBox(height: 24),
                _heading('Badges & progress'.tr),
                _surface(Wrap(spacing: 24, runSpacing: 20, children: [
                  SizedBox(width: panelWidth, child: _badge('Collection'.tr, HelperBadge.getCollectionProgress(home.totalVideo.value), 'videos'.tr, HugeIcons.strokeRoundedLayers01)),
                  SizedBox(width: panelWidth, child: _badge('Watch time'.tr, HelperBadge.getWatchDurationProgress(profile.totalWatchDuration ?? 0), 'hours'.tr, HugeIcons.strokeRoundedPlaySquare, watchTime: true)),
                ])),
                const SizedBox(height: 24),
                _heading('Achievements'.tr, detail: '@{achievementCount} of @{length} unlocked'.trNamed({'achievementCount': '${home.achievementCount.value}', 'length': '${achievements.length}'})),
                if (home.latestAchievementTitles.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(bottom: 16), child: Text('Latest: @{join}'.trNamed({'join': '${home.latestAchievementTitles.map((title) => title.tr).join(' · ')}'}), style: TextStyle(fontSize: 12, color: AppColor.muted))),
                Wrap(key: controller.achievementSectionKey, spacing: 6, runSpacing: 6, children: [
                  for (final filter in ['All', 'In progress', 'Unlocked'])
                    _filter(filter, controller.achievementFilter),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final group in ['All', ...achievements.map((item) => item.group).toSet()])
                    _filter(group, controller.achievementGroup),
                ]),
                const SizedBox(height: 12),
                if (achievements.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('No achievements yet. Your progress will appear here.'.tr, style: TextStyle(fontSize: 13, color: AppColor.muted)))
                else if (filtered.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('No milestones in this filter.'.tr, style: TextStyle(fontSize: 12, color: AppColor.muted)))
                else
                  Column(children: filtered.map(_achievement).toList()),
              ]);
            })),
          ),
        ),
      );
    });
  }

  Widget _editButton(BuildContext context) => AppButton(
    label: 'Edit profile'.tr,
    icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: AppStyle.iconSize),
    onPressed: () => _editName(context),
  );

  Future<void> _editName(BuildContext context) async {
    controller.editName();
    Future<void> save(BuildContext dialogContext) async {
      await controller.saveName();
      if (dialogContext.mounted && !controller.isEditing.value) Navigator.of(dialogContext).pop();
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Obx(() => PopScope(
        canPop: !controller.isSaving.value,
        child: AppConfirmDialog(
          title: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('Edit profile'.tr, textAlign: TextAlign.left, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(label: 'Display name'.tr, child: AppTextField(
              controller: controller.tecName,
              autofocus: true,
              enabled: !controller.isSaving.value,
              style: TextStyle(color: AppColor.text),
              placeholder: 'Display name'.tr,
              placeholderStyle: TextStyle(fontSize: 12, color: AppColor.muted),
              prefix: Padding(padding: const EdgeInsets.only(left: 8), child: HugeIcon(icon: HugeIcons.strokeRoundedUser, size: AppStyle.iconSize, color: AppColor.muted)),
              onSubmitted: (_) => save(dialogContext),
            )),
            if (controller.nameError.value.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(controller.nameError.value, style: const TextStyle(fontSize: 11, color: CupertinoColors.systemRed)),
            ),
          ]),
          actions: [
            AppDialogAction(
              onPressed: controller.isSaving.value ? null : () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel'.tr, style: const TextStyle(fontSize: 13)),
            ),
            AppDialogAction(
              onPressed: controller.isSaving.value ? null : () => save(dialogContext),
              child: Text(controller.isSaving.value ? 'Saving...'.tr : 'Save changes'.tr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      )),
    );
    if (!controller.isClosed && controller.isEditing.value) controller.cancelEdit();
  }

  Widget _surface(Widget child) => SizedBox(width: double.infinity, child: AppPanel(child: child));

  Widget _heading(String title, {String? detail}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AppSectionHeading(title: title, detail: detail),
  );

  Widget _stat(String label, String value, List<List<dynamic>> icon, double width) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          HugeIcon(icon: icon, size: AppStyle.iconSize, color: AppColor.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: TextStyle(fontSize: 11, color: AppColor.muted))),
        ]),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ]),
    ),
  );

  Widget _badge(String label, BadgeProgress progress, String unit, List<List<dynamic>> icon, {bool watchTime = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [HugeIcon(icon: icon, size: AppStyle.iconSize, color: (Get.isDarkMode ? Colors.amberAccent : Colors.orange.shade800)), const SizedBox(width: 8), Expanded(child: Text(label, style: TextStyle(fontSize: 11, color: AppColor.muted)))]),
      const SizedBox(height: 12),
      Text(progress.currentTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      _progress(progress.percent, (Get.isDarkMode ? Colors.amberAccent : Colors.orange.shade800)),
      const SizedBox(height: 8),
      Text(progress.isMaxLevel ? 'Max level reached'.tr : '@{currentValue}/@{targetValue} @{unit} · Next: @{nextTitle}'.trNamed({'currentValue': watchTime ? _watchTime(progress.currentValue) : '${progress.currentValue}', 'targetValue': watchTime ? _watchTime(progress.targetValue) : '${progress.targetValue}', 'unit': watchTime ? '' : unit, 'nextTitle': '${progress.nextTitle}'}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
    ],
  );

  Widget _achievement(AchievementProgress item) {
    final color = item.isUnlocked ? AppColor.success : AppColor.muted;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColor.border, width: .5))),
      child: LayoutBuilder(builder: (context, constraints) {
        final details = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          HugeIcon(icon: item.isUnlocked ? HugeIcons.strokeRoundedCheckmarkBadge01 : _groupIcon(item.group), size: AppStyle.iconSize, color: color),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(item.title.tr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text(item.group.tr, style: TextStyle(fontSize: 10, color: AppColor.muted)),
              if (item.xp > 0) Text('+${item.xp} XP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColor.accentForeground)),
            ]),
            const SizedBox(height: 4),
            Text(item.description.tr, style: TextStyle(fontSize: 11, color: AppColor.muted)),
          ])),
        ]);
        final progress = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _progress(item.percent, color),
          const SizedBox(height: 6),
          Text(item.isUnlocked ? 'Unlocked @{unlockedAt}'.trNamed({'unlockedAt': '${_date(item.unlockedAt)}'}) : _achievementStatus(item), style: TextStyle(fontSize: 11, color: color)),
        ]);
        if (constraints.maxWidth < 600) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          details,
          Padding(padding: const EdgeInsets.only(left: 28, top: 12), child: progress),
        ]);
        return Row(children: [Expanded(child: details), const SizedBox(width: 24), SizedBox(width: 220, child: progress)]);
      }),
    );
  }

  Widget _filter(String label, RxString selected) => Semantics(
    selected: selected.value == label,
    child: AppButton(label: label.tr, height: 28, labelSize: 11,
      variant: selected.value == label ? AppButtonVariant.tonal : AppButtonVariant.text,
      onPressed: () => selected.value = label),
  );

  Widget _goal(AchievementProgress item) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      HugeIcon(icon: _groupIcon(item.group), size: AppStyle.iconSize, color: AppColor.accentForeground),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.title.tr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('@{remaining} more @{unit} · +@{xp} XP'.trNamed({'remaining': '${item.remaining}', 'unit': item.unit.tr, 'xp': '${item.xp}'}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
        const SizedBox(height: 8),
        _progress(item.percent, AppColor.accentForeground),
      ])),
      const SizedBox(width: 8),
      AppButton(label: 'View goals'.tr, height: 28, labelSize: 11, onPressed: () {
        controller.achievementGroup.value = item.group;
        controller.achievementFilter.value = 'In progress';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = controller.achievementSectionKey.currentContext;
          if (context != null) Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 250));
        });
      }),
    ]),
  );

  List<List<dynamic>> _groupIcon(String group) => switch (group) {
    'Collection' => HugeIcons.strokeRoundedLayers01,
    'Curation' => HugeIcons.strokeRoundedFavourite,
    'Exploration' => HugeIcons.strokeRoundedSearch01,
    'Watch Time' => HugeIcons.strokeRoundedPlaySquare,
    'Streak' => HugeIcons.strokeRoundedFire,
    _ => HugeIcons.strokeRoundedAward01,
  };

  String _achievementStatus(AchievementProgress item) {
    if (item.unit == 'minutes') return '@{currentValue}/@{targetValue} · In progress'.trNamed({
      'currentValue': _watchTime(item.currentValue * 60), 'targetValue': _watchTime(item.targetValue * 60),
    });
    if (item.unit.isEmpty) return '@{currentValue}/@{targetValue} · In progress'.trNamed({'currentValue': '${item.currentValue}', 'targetValue': '${item.targetValue}'});
    return '@{currentValue}/@{targetValue} @{unit} · In progress'.trNamed({'currentValue': '${item.currentValue}', 'targetValue': '${item.targetValue}', 'unit': item.unit.tr});
  }

  String _watchTime(int seconds) {
    final time = Duration(seconds: seconds);
    if (seconds < 60) return '@{seconds}s'.trNamed({'seconds': '$seconds'});
    return '@{hours}h @{minutes}m'.trNamed({'hours': '${time.inHours}', 'minutes': '${time.inMinutes.remainder(60)}'});
  }

  Widget _progress(int percent, Color color) => LinearProgressIndicator(
    value: percent / 100,
    minHeight: 4,
    borderRadius: BorderRadius.circular(8),
    color: color,
    backgroundColor: AppColor.hover,
  );

  String _date(String? value) {
    final date = DateTime.tryParse(value ?? '');
    return date == null ? '—' : DateFormat('MMM d, yyyy').format(date);
  }
}
