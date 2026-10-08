import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../widgets/widget_controls.dart';

class PageDeletedItemsView extends StatefulWidget {
  const PageDeletedItemsView({super.key});

  @override
  State<PageDeletedItemsView> createState() => _PageDeletedItemsViewState();
}

class _PageDeletedItemsViewState extends State<PageDeletedItemsView> {
  final _search = TextEditingController();
  late final Worker _worker;
  List<Videos> _videos = [];
  bool _loading = true;
  String? _restoring;
  String _error = '';
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _worker = ever(DBVideos.revision, (_) => _load());
    unawaited(_load());
  }

  @override
  void dispose() {
    _worker.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() { _loading = true; _error = ''; });
    try {
      final videos = await DBVideos.getAll(
        includeDeleted: true, where: 'is_deleted = 1', orderBy: 'updated_at DESC, id ASC',
      );
      if (!mounted || request != _request) return;
      setState(() { _videos = videos; _loading = false; });
    } catch (e) {
      AppLog.logE('Loading deleted items failed: $e');
      if (!mounted || request != _request) return;
      setState(() { _loading = false; _error = 'Could not load deleted items. Try again.'.tr; });
    }
  }

  Future<void> _restore(Videos video) async {
    setState(() { _restoring = video.id; _error = ''; });
    try {
      final changed = await DBVideos.restore(video);
      if (mounted && changed == 0) await _load();
    } catch (e) {
      AppLog.logE('Restoring deleted item failed: $e');
      if (mounted) setState(() => _error = 'Could not restore the record. Try again.'.tr);
    } finally {
      if (mounted) setState(() => _restoring = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    final query = _search.text.trim().toLowerCase();
    final videos = _videos.where((video) => [video.videoCode, video.title, video.videoPath]
      .any((value) => (value ?? '').toLowerCase().contains(query))).toList();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Deleted Items'.tr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          Text('${videos.length} / ${_videos.length}', style: TextStyle(fontSize: 11, color: AppColor.muted)),
          const SizedBox(width: 8),
          AppButton(onPressed: _loading || _restoring != null ? null : _load, label: 'Refresh'.tr),
        ]),
        const SizedBox(height: 8),
        Text('Restoring only returns the record to your library. It does not recover a file deleted from disk. Missing or offline files remain unavailable.'.tr,
          style: TextStyle(fontSize: 11, color: AppColor.muted)),
        const SizedBox(height: 12),
        AppTextField(
          controller: _search,
          placeholder: 'Search video code, title or path'.tr,
          clearButtonMode: OverlayVisibilityMode.editing,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (_error.isNotEmpty) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_error, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error)),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _videos.isEmpty
          ? Center(child: Text(_loading ? 'Loading...'.tr : _error.isNotEmpty ? '' : 'No deleted items.'.tr))
          : videos.isEmpty
            ? Center(child: Text('No matching items'.tr))
            : ListView.separated(
                itemCount: videos.length,
                separatorBuilder: (_, _) => Divider(height: 1, thickness: .5, color: AppColor.border),
                itemBuilder: (_, index) {
                  final video = videos[index];
                  return Padding(
                    key: ValueKey(video.id),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(video.videoCode ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        if ((video.title ?? '').isNotEmpty)
                          Text(video.title!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                        const SizedBox(height: 4),
                        SelectableText(video.videoPath ?? '', style: TextStyle(fontSize: 10, color: AppColor.muted)),
                      ])),
                      const SizedBox(width: 12),
                      AppButton(
                        onPressed: _restoring != null || _loading ? null : () => _restore(video),
                        label: _restoring == video.id ? 'Restoring…'.tr : 'Restore record'.tr,
                        variant: AppButtonVariant.outlined,
                      ),
                    ]),
                  );
                },
              ),
        ),
      ]),
    );
  }
}
