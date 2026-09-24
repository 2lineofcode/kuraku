import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/app_color.dart';
import '../../../data/database/db_gamification.dart';
import '../../../utils/helper_badge.dart';
import 'page_profile_controller.dart';

class PageProfileView extends GetView<PageProfileController> {
  const PageProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Obx(() {
      if (controller.isLoading.value) return const Center(child: CircularProgressIndicator());
      if (controller.error.value.isNotEmpty) {
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(controller.error.value),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: controller.onRefresh, child: const Text('Retry')),
        ]));
      }
      final home = controller.home;
      final profile = home.profile.value;
      final watch = Duration(seconds: profile.totalWatchDuration ?? 0);
      final achievements = home.achievementProgress.toList();
      return SingleChildScrollView(
        key: const PageStorageKey('profile'),
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: LayoutBuilder(builder: (context, constraints) => Obx(() {
              final wide = constraints.maxWidth >= 700;
              final columns = constraints.maxWidth >= 900 ? 4 : constraints.maxWidth >= 400 ? 2 : 1;
              final statWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
              final panelWidth = wide ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(radius: 25, backgroundColor: AppColor.selected, child: Icon(Icons.person_outline_rounded, size: 28)),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(profile.name?.trim().isNotEmpty == true ? profile.name! : 'Your profile', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Member since ${_date(profile.createdAt)}', style: TextStyle(fontSize: 12, color: AppColor.muted)),
                    ])),
                    if (!controller.isEditing.value && wide)
                      TextButton.icon(onPressed: controller.editName, icon: Icon(Icons.edit_outlined, size: 16), label: const Text('Edit profile')),
                  ]),
                  if (!controller.isEditing.value && !wide)
                    Padding(padding: const EdgeInsets.only(top: 12), child: TextButton.icon(onPressed: controller.editName, icon: Icon(Icons.edit_outlined, size: 16), label: const Text('Edit profile'))),
                  if (controller.isEditing.value) ...[
                    const SizedBox(height: 24),
                    const Text('Display name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: TextField(
                        controller: controller.tecName,
                        autofocus: true,
                        enabled: !controller.isSaving.value,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Your name',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          errorText: controller.nameError.value.isEmpty ? null : controller.nameError.value,
                        ),
                        onSubmitted: (_) => controller.saveName(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      FilledButton(onPressed: controller.isSaving.value ? null : controller.saveName, child: Text(controller.isSaving.value ? 'Saving...' : 'Save changes')),
                      const SizedBox(width: 8),
                      TextButton(onPressed: controller.isSaving.value ? null : controller.cancelEdit, child: const Text('Cancel')),
                    ]),
                  ],
                  if (controller.notice.value.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(controller.notice.value, style: TextStyle(fontSize: 12, color: (Get.isDarkMode ? Colors.greenAccent : Colors.green.shade700))),
                  ],
                ])),
                const SizedBox(height: 24),
                _heading('Activity overview', 'Your collection and activity so far'),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _stat('Videos', '${home.totalVideo.value}', Icons.video_library_outlined, statWidth),
                  _stat('Watch time', '${watch.inHours}h ${watch.inMinutes.remainder(60)}m', Icons.schedule_rounded, statWidth),
                  _stat('Current streak', '${home.streakDays.value} days', Icons.local_fire_department_outlined, statWidth),
                  _stat('Total relapse', '${controller.totalRelapse.value} times', Icons.history_rounded, statWidth),
                ]),
                const SizedBox(height: 24),
                _heading('Badges & progress', 'Your current levels and next milestones'),
                Wrap(spacing: 16, runSpacing: 16, children: [
                  SizedBox(width: panelWidth, child: _badge('Collection', HelperBadge.getCollectionProgress(home.totalVideo.value), 'videos', Icons.collections_bookmark_outlined)),
                  SizedBox(width: panelWidth, child: _badge('Watch time', HelperBadge.getWatchDurationProgress(profile.totalWatchDuration ?? 0), 'hours', Icons.ondemand_video_rounded)),
                ]),
                const SizedBox(height: 24),
                _heading('Achievements', '${home.achievementCount.value} of ${achievements.length} unlocked'),
                if (home.latestAchievementTitles.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(bottom: 16), child: Text('Latest: ${home.latestAchievementTitles.join(' · ')}', style: TextStyle(fontSize: 12, color: AppColor.muted))),
                if (achievements.isEmpty)
                  _card(Text('No achievements yet. Your progress will appear here.', style: TextStyle(fontSize: 13, color: AppColor.muted)))
                else
                  Wrap(spacing: 16, runSpacing: 16, children: achievements.map((item) => SizedBox(width: panelWidth, child: _achievement(item))).toList()),
              ]);
            })),
          ),
        ),
      );
    });
  }

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: AppColor.appBar, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColor.border)),
    child: child,
  );

  Widget _heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(subtitle, style: TextStyle(fontSize: 12, color: AppColor.muted)),
    ]),
  );

  Widget _stat(String label, String value, IconData icon, double width) => SizedBox(width: width, child: _card(
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 20, color: AppColor.muted),
      const SizedBox(height: 14),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 12, color: AppColor.muted)),
    ]),
  ));

  Widget _badge(String label, BadgeProgress progress, String unit, IconData icon) => _card(
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 20, color: (Get.isDarkMode ? Colors.amberAccent : Colors.orange.shade800)), const SizedBox(width: 10), Text(label, style: TextStyle(fontSize: 12, color: AppColor.muted))]),
      const SizedBox(height: 12),
      Text(progress.currentTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      _progress(progress.percent, (Get.isDarkMode ? Colors.amberAccent : Colors.orange.shade800)),
      const SizedBox(height: 8),
      Text(progress.isMaxLevel ? 'Max level reached' : '${progress.currentValue}/${progress.targetValue} $unit · Next: ${progress.nextTitle}', style: TextStyle(fontSize: 11, color: AppColor.muted)),
    ]),
  );

  Widget _achievement(AchievementProgress item) {
    final color = item.isUnlocked ? (Get.isDarkMode ? Colors.greenAccent : Colors.green.shade700) : AppColor.muted;
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(item.isUnlocked ? Icons.verified_outlined : Icons.lock_outline_rounded, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(item.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        const SizedBox(width: 8),
        Text(item.group, style: TextStyle(fontSize: 10, color: color)),
      ]),
      const SizedBox(height: 10),
      Text(item.description, style: TextStyle(fontSize: 12, color: AppColor.muted)),
      const SizedBox(height: 16),
      _progress(item.percent, color),
      const SizedBox(height: 8),
      Text(item.isUnlocked ? 'Unlocked ${_date(item.unlockedAt)}' : '${item.currentValue}/${item.targetValue} · In progress', style: TextStyle(fontSize: 11, color: color)),
    ]));
  }

  Widget _progress(int percent, Color color) => LinearProgressIndicator(
    value: percent / 100,
    minHeight: 5,
    borderRadius: BorderRadius.circular(8),
    color: color,
    backgroundColor: AppColor.hover,
  );

  String _date(String? value) {
    final date = DateTime.tryParse(value ?? '');
    return date == null ? '—' : DateFormat('MMM d, yyyy').format(date);
  }
}
