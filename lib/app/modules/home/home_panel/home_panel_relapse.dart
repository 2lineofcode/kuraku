import 'dart:async';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';

import '../../../core/app_color.dart';
import '../../../core/app_pref.dart';
import '../../../core/app_translations.dart';
import '../../../core/const.dart';
import '../../../data/database/db_activity.dart';
import '../../../data/models/activity_entity.dart';
import '../home_controller.dart';
import '../page_profile/page_profile_controller.dart';
import '../page_settings/page_settings_controller.dart';

mixin HomePanelRelapse {
  static Future<void> open() async {
    if (Overlayment.count > 0) { await Overlayment.dismissLast(); return; }
    WidgetsBinding.instance.scheduleFrame();
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerRight,
        width: 320,
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverSlideAnimation(beginAlignment: Alignment.centerRight, reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: AppColor.panel,
        child: const _RelapsePanel(),
      ),
    );
  }
}

class _RelapsePanel extends StatefulWidget {
  const _RelapsePanel();

  @override
  State<_RelapsePanel> createState() => _RelapsePanelState();
}

class _RelapsePanelState extends State<_RelapsePanel> {
  List<Activity> _items = [];
  Activity? _removed;
  bool _busy = false;
  bool _loaded = false;
  String _error = '';
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _run();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _run());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _run([Future<void> Function()? action]) async {
    if (_busy) return;
    setState(() { _busy = true; _error = ''; });
    var saved = false;
    try {
      if (action != null) { await action(); saved = true; }
      final items = await DBActivity.getAllRelapse();
      final todayCount = await DBActivity.getCountRelapseToday();
      Get.find<HomeController>().isDangerMode.value = todayCount >= AppPref.getAppMaxColi();
      if (Get.isRegistered<PageSettingsController>() && !Get.isPrepared<PageSettingsController>()) {
        await Get.find<PageSettingsController>().refreshRelapse();
      }
      if (Get.isRegistered<PageProfileController>() && !Get.isPrepared<PageProfileController>()) {
        Get.find<PageProfileController>().totalRelapse.value = await DBActivity.countRelapse();
      }
      if (mounted) setState(() { _items = items; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() {
        _error = saved ? 'Saved, but could not refresh. Retry loading.'.tr : 'Could not complete the request. Please retry.'.tr;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  DateTime? _day(Activity item) {
    final raw = item.content ?? '';
    final date = DateTime.tryParse(raw);
    return date != null && date.toStringEx(format: kYMd) == raw ? date : null;
  }

  String _elapsed(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now'.tr;
    if (diff.inMinutes < 60) return '@{inMinutes} min ago'.trNamed({'inMinutes': '${diff.inMinutes}'});
    if (diff.inHours < 24) return '@{inHours} hr ago'.trNamed({'inHours': '${diff.inHours}'});
    return '@{inDays} days ago'.trNamed({'inDays': '${diff.inDays}'});
  }

  Widget _stat(String label, int value) => Expanded(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text(label, style: TextStyle(fontSize: 12, color: AppColor.muted)),
      const SizedBox(height: 4), Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))],
  ));

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final week = DateTime(today.year, today.month, today.day - today.weekday + 1);
    final previousWeek = DateTime(week.year, week.month, week.day - 7);
    final month = DateTime(today.year, today.month, 1);
    final limit = AppPref.getAppMaxColi();
    var todayCount = 0, weekCount = 0, monthCount = 0, total = 0, previousCount = 0;
    DateTime? latest;
    for (final item in _items) {
      final day = _day(item);
      if (day == null || day.isAfter(today)) continue;
      final count = item.times ?? 1;
      total += count;
      if (day == today) todayCount += count;
      if (!day.isBefore(week)) weekCount += count;
      if (!day.isBefore(month)) monthCount += count;
      if (!day.isBefore(previousWeek) && day.isBefore(week)) previousCount += count;
      final stamp = DateTime.tryParse(item.createdAt ?? '');
      if (stamp != null && !stamp.isAfter(now) && (latest == null || stamp.isAfter(latest))) latest = stamp;
    }
    final reached = todayCount >= limit;
    final difference = weekCount - previousCount;
    return Material(
      color: AppColor.panel,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Relapse'.tr, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            IconButton(tooltip: 'Close'.tr, icon: const Icon(Icons.close, size: 18), onPressed: () => Overlayment.dismissLast()),
          ]),
          const SizedBox(height: 12),
          Text('TODAY'.tr, style: TextStyle(fontSize: 12, color: AppColor.muted)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Text(_loaded ? '$todayCount / $limit' : '— / $limit', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600,
              color: _loaded && reached ? Theme.of(context).colorScheme.error : AppColor.text))),
            Text(_loaded && reached ? 'Daily limit reached'.tr : 'Daily limit'.tr, style: TextStyle(fontSize: 12, color: AppColor.muted)),
          ]),
          const SizedBox(height: 6),
          Text(latest == null ? 'No records yet'.tr : 'Last recorded @{latest}'.trNamed({'latest': '${_elapsed(latest)}'}), style: TextStyle(fontSize: 12, color: AppColor.muted)),
          const SizedBox(height: 16),
          ExButtonOutline(
            width: double.infinity,
            height: 32,
            radius: 4,
            label: 'Log relapse'.tr,
            labelSize: 12,
            labelColor: _busy || !_loaded ? AppColor.muted : AppColor.text,
            borderColor: AppColor.border,
            backgroundColor: AppColor.container,
            icon: Icon(Icons.add, size: 14, color: _busy || !_loaded ? AppColor.muted : AppColor.text),
            onPressed: _busy || !_loaded ? null : () => _run(() async {
              if (await DBActivity.addRelapse() == null) throw StateError('Record was not saved'.tr);
            }),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_error.isNotEmpty) Row(children: [
            Expanded(child: Text(_error, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error))),
            TextButton(onPressed: _busy ? null : () => _run(), child: Text('Retry'.tr)),
          ]),
          if (_removed != null) Row(children: [
            Expanded(child: Text('Entry removed'.tr, style: TextStyle(fontSize: 12))),
            TextButton(onPressed: _busy ? null : () => _run(() async {
              await DBActivity.restoreRelapse(_removed!);
              _removed = null;
            }), child: Text('Undo'.tr)),
          ]),
          const SizedBox(height: 16),
          Row(children: [_stat('This week'.tr, weekCount), _stat('This month'.tr, monthCount), _stat('Total'.tr, total)]),
          const SizedBox(height: 8),
          Text('@{difference}@{difference2} vs last full week (@{previousCount})'.trNamed({'difference': '${difference > 0 ? '+' : ''}', 'difference2': '$difference', 'previousCount': '$previousCount'}), style: TextStyle(fontSize: 12, color: AppColor.muted)),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
          Text('History'.tr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Expanded(child: _items.isEmpty
            ? Center(child: Text(_loaded ? 'No records yet'.tr : 'Loading history…'.tr, style: TextStyle(fontSize: 13, color: AppColor.muted)))
            : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                final day = _day(item);
                final yesterday = DateTime(today.year, today.month, today.day - 1);
                final title = day == null ? 'Invalid date'.tr : day == today ? 'Today'.tr : day == yesterday ? 'Yesterday'.tr : day.toStringEx(format: 'MMM d, yyyy');
                final stamp = DateTime.tryParse(item.createdAt ?? '');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(stamp == null ? 'Time unavailable'.tr : 'Last recorded at @{mm}'.trNamed({'mm': '${stamp.toStringEx(format: 'HH:mm')}'}), style: TextStyle(fontSize: 12, color: AppColor.muted)),
                    ])),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColor.selected, borderRadius: BorderRadius.circular(12)),
                      child: Text('${item.times ?? 1}×', style: const TextStyle(fontSize: 12))),
                    MenuAnchor(
                      builder: (_, menu, child) => IconButton(
                        tooltip: 'Entry actions'.tr, icon: const Icon(Icons.more_horiz, size: 18),
                        onPressed: _busy ? null : () => menu.isOpen ? menu.close() : menu.open(),
                      ),
                      menuChildren: [MenuItemButton(
                        onPressed: _busy ? null : () => _run(() async {
                          _removed = await DBActivity.deleteRelapseByDateLimitOne(item.content ?? '');
                        }),
                        child: Text('Remove latest entry'.tr),
                      )],
                    ),
                  ]),
                );
              },
            )),
        ]),
      ),
    );
  }
}
