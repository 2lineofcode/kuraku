import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_color.dart';
import '../../../core/app_translations.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/database/library_health_check.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_opener.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_style.dart';
import '../../widgets/widget_surfaces.dart';
import '../../widgets/widget_thumbnail.dart';

class LibraryHealthDialog extends StatefulWidget {
  const LibraryHealthDialog({super.key, required this.check, this.openVideoInfo = HelperOpener.openVideoInfo});

  final Future<List<LibraryHealthIssue>> check;
  final Future<void> Function(dynamic) openVideoInfo;

  @override
  State<LibraryHealthDialog> createState() => _LibraryHealthDialogState();
}

class _LibraryHealthDialogState extends State<LibraryHealthDialog> {
  final _scroll = ScrollController();
  final _videos = <String, Future<Videos?>>{};
  LibraryHealthStatus? _selected;
  String _query = '', _copiedPath = '';
  String? _openError;
  bool _opening = false;
  bool _deleting = false;
  final _removedPaths = <String>{};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _label(LibraryHealthStatus status) => switch (status) {
    LibraryHealthStatus.offlineDrive => 'Offline drives',
    LibraryHealthStatus.missingFile => 'Missing files',
    LibraryHealthStatus.incompleteMetadata => 'Incomplete metadata',
    LibraryHealthStatus.unreadableFile => 'Unreadable files',
  };

  String _field(String field) => switch (field) {
    'video_code' => 'Video Code',
    'title' => 'Title',
    'poster' => 'Poster',
    'release_date' => 'Release Date',
    'duration' => 'Duration',
    'actress' => 'Actress',
    'category' => 'Category',
    _ => field,
  };

  Color _color(LibraryHealthStatus status) => switch (status) {
    LibraryHealthStatus.missingFile || LibraryHealthStatus.unreadableFile => Theme.of(context).colorScheme.error,
    _ => AppColor.accentForeground,
  };

  Future<void> _openVideoInfo(String path) async {
    if (_opening || _deleting) return;
    setState(() { _opening = true; _openError = null; });
    Videos? video;
    try {
      video = await DBVideos.getByVideoPath(path);
      if (!mounted) return;
      if (video == null) {
        setState(() => _openError = 'Video is no longer in the library.'.tr);
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _openError = 'Could not open video info.'.tr);
      return;
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (!mounted) return;
    await widget.openVideoInfo(video);
  }

  Future<void> _deleteMissingFiles(List<LibraryHealthIssue> issues) async {
    if (_deleting || _opening) return;
    final paths = issues.where((issue) => issue.status == LibraryHealthStatus.missingFile
      && issue.path.isNotEmpty && !issue.details.contains('Library folder')).map((issue) => issue.path).toSet().toList();
    if (paths.isEmpty) return;
    setState(() { _deleting = true; _openError = null; });
    try {
      final confirmed = await showCupertinoDialog<bool>(context: context, builder: (context) => AppConfirmDialog(
        title: Text('Delete all missing files?'.tr),
        content: Text('Move all @count missing file records to Deleted Items, including items hidden by search? Files are checked again before removal. Offline drives, library folders and files on disk are kept.'.trParams({'count': '${paths.length}'})),
        actions: [
          AppDialogAction(onPressed: () => Navigator.pop(context, false), child: Text('Cancel'.tr)),
          AppDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: Text('Delete all'.tr)),
        ],
      ));
      if (confirmed != true || !mounted) return;
      final removed = await LibraryHealthCheck.deleteMissingFiles(paths);
      if (mounted) setState(() => _removedPaths.addAll(removed));
    } catch (_) {
      if (mounted) setState(() => _openError = 'Could not delete missing file records. Try again.'.tr);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _results(List<LibraryHealthIssue> report) {
    final issues = report.where((issue) => !_removedPaths.contains(issue.path)).toList();
    final visible = issues.where((issue) => (_selected == null || issue.status == _selected)
      && '${issue.path} ${issue.details.map((field) => _field(field).tr).join(' ')}'.toLowerCase().contains(_query)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Column(children: [
        LayoutBuilder(builder: (_, constraints) {
          final columns = constraints.maxWidth < 560 ? 2 : 4;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final status in LibraryHealthStatus.values)
              SizedBox(width: (constraints.maxWidth - (columns - 1) * 8) / columns,
                child: Semantics(selected: _selected == status, child: AppButton(
                  variant: _selected == status ? AppButtonVariant.tonal : AppButtonVariant.outlined,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  onPressed: () {
                    setState(() => _selected = _selected == status ? null : status);
                    if (_scroll.hasClients) _scroll.jumpTo(0);
                  },
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${issues.where((issue) => issue.status == status).length}',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600,
                        color: issues.any((issue) => issue.status == status) ? _color(status) : AppColor.muted)),
                    SizedBox(height: 28, child: Text(_label(status).tr, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppColor.muted))),
                  ]),
                ))),
          ]);
        }),
        const SizedBox(height: 12),
        AppTextField(
          placeholder: 'Search file, path or missing metadata'.tr,
          clearButtonMode: OverlayVisibilityMode.editing,
          prefix: Padding(padding: const EdgeInsets.only(left: 8),
            child: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: AppStyle.iconSize, color: AppColor.muted)),
          onChanged: (value) {
            setState(() => _query = value.trim().toLowerCase());
            if (_scroll.hasClients) _scroll.jumpTo(0);
          },
        ),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
        Expanded(child: Text(_selected == null ? 'All issues'.tr : _label(_selected!).tr,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
        Text('${visible.length}', style: TextStyle(fontSize: 11, color: AppColor.muted)),
        if (_selected == LibraryHealthStatus.missingFile) ...[
          const SizedBox(width: 8),
          AppButton(label: (_deleting ? 'Deleting…' : 'Delete all').tr, labelSize: 11,
            labelColor: Theme.of(context).colorScheme.error,
            onPressed: _deleting || _opening || !issues.any((issue) => issue.status == LibraryHealthStatus.missingFile
              && issue.path.isNotEmpty && !issue.details.contains('Library folder')) ? null : () => _deleteMissingFiles(issues)),
        ],
        if (_selected != null) ...[
          const SizedBox(width: 8),
          AppButton(label: 'Show all'.tr, labelSize: 11, onPressed: () => setState(() => _selected = null)),
        ],
      ])),
      if (issues.any((issue) => issue.status == LibraryHealthStatus.offlineDrive)
          && (_selected == null || _selected == LibraryHealthStatus.offlineDrive))
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Tooltip(message: 'Reconnect offline drives before checking again. Their files are not marked missing.'.tr,
            child: Text('Offline drives are not counted as missing files.'.tr, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColor.muted)))),
      Divider(height: 20, thickness: .5, color: AppColor.border),
      Expanded(child: visible.isEmpty
        ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
            HugeIcon(icon: issues.isEmpty ? HugeIcons.strokeRoundedCheckmarkCircle02 : HugeIcons.strokeRoundedSearch01,
              size: 28, color: issues.isEmpty ? AppColor.success : AppColor.muted),
            const SizedBox(height: 10),
            Text((issues.isEmpty ? 'No library issues found.' : 'No matching issues.').tr,
              textAlign: TextAlign.center),
          ])))
        : Scrollbar(controller: _scroll, thumbVisibility: true, child: ListView.separated(
            controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            itemCount: visible.length,
            separatorBuilder: (_, _) => Divider(height: 20, thickness: .5, color: AppColor.border),
            itemBuilder: (_, index) {
              final issue = visible[index];
              final isVideo = issue.status != LibraryHealthStatus.offlineDrive && issue.path.isNotEmpty
                && !issue.details.contains('Library folder');
              final row = Material(color: Colors.transparent, child: InkWell(
                borderRadius: BorderRadius.circular(AppStyle.radius),
                onTap: isVideo && !_opening && !_deleting
                  ? () => _openVideoInfo(issue.path) : null,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (isVideo)
                  Padding(padding: const EdgeInsets.only(right: 10), child: IgnorePointer(child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppStyle.radius),
                    child: FutureBuilder<Videos?>(
                      key: ValueKey(issue.path),
                      future: _videos.putIfAbsent(issue.path, () => DBVideos.getByVideoPath(issue.path)),
                      builder: (_, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const SizedBox(width: 64, height: 80, child: Center(child: CupertinoActivityIndicator()));
                        }
                        final video = snapshot.data;
                        final poster = (video?.poster ?? '').trim();
                        return ExThumbnail(imageUrl: poster.isNotEmpty ? poster : video?.fanArt ?? '',
                          videoPath: issue.path, videoCode: video?.videoCode, width: 64, height: 80, prefix: 1.9);
                      },
                    ),
                  )))
                else
                Padding(padding: const EdgeInsets.only(top: 2, right: 10),
                  child: HugeIcon(icon: issue.status == LibraryHealthStatus.offlineDrive
                    ? HugeIcons.strokeRoundedFolder01 : HugeIcons.strokeRoundedFile01,
                    size: AppStyle.iconSize, color: _color(issue.status))),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(issue.path.isEmpty ? 'Missing path'.tr : p.basename(issue.path),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Tooltip(message: issue.path, child: Text(issue.path.isEmpty ? 'Missing path'.tr : p.dirname(issue.path),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColor.muted))),
                  const SizedBox(height: 6),
                  if (_selected == null || issue.details.isEmpty)
                    Text(_label(issue.status).tr, style: TextStyle(fontSize: 11, color: _color(issue.status))),
                  if (issue.details.isNotEmpty)
                    Text(issue.status == LibraryHealthStatus.incompleteMetadata
                      ? 'Missing: @{fields}'.trNamed({'fields': issue.details.map((field) => _field(field).tr).join(', ')})
                      : issue.details.map((field) => _field(field).tr).join(', '),
                      style: TextStyle(fontSize: 11, color: AppColor.muted)),
                ])),
                const SizedBox(width: 8),
                AppIconButton(
                  tooltip: (_copiedPath == issue.path ? 'Copied' : 'Copy path').tr,
                  icon: HugeIcon(icon: _copiedPath == issue.path ? HugeIcons.strokeRoundedCheckmarkCircle02 : HugeIcons.strokeRoundedCopy01,
                    size: AppStyle.iconSize, color: AppColor.muted),
                  onPressed: issue.path.isEmpty ? null : () async {
                    await Clipboard.setData(ClipboardData(text: issue.path));
                    if (mounted) setState(() => _copiedPath = issue.path);
                  },
                ),
              ])));
              return isVideo ? ExVideoContextMenu(videoPath: issue.path, child: row) : row;
            },
          ))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return AppDialog(child: SizedBox(
      width: math.min(640, MediaQuery.sizeOf(context).width - 32),
      height: math.min(560, MediaQuery.sizeOf(context).height * .85),
      child: DefaultTextStyle.merge(style: TextStyle(fontSize: AppStyle.fontSize, color: AppColor.text),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Library Health Check'.tr, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Review library issues and remove missing file records.'.tr, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColor.muted)),
          ])),
          if (_openError != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(_openError!, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error))),
          Expanded(child: FutureBuilder<List<LibraryHealthIssue>>(
            future: widget.check,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24),
                child: Text('Health check failed. Check folder permissions and try again.'.tr, textAlign: TextAlign.center)));
              if (!snapshot.hasData) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CupertinoActivityIndicator(), const SizedBox(height: 12), Text('Checking library…'.tr),
              ]));
              return _results(snapshot.data!);
            },
          )),
          Divider(height: 1, thickness: .5, color: AppColor.border),
          Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            Tooltip(message: 'Readability checks opening the file, not full playback.'.tr,
              child: HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: AppStyle.iconSize, color: AppColor.muted)),
            const SizedBox(width: 8),
            Expanded(child: Text('Files on disk are kept.'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted))),
            AppButton(label: 'Close'.tr, variant: AppButtonVariant.tonal,
              onPressed: _deleting ? null : () => Navigator.of(context).pop()),
          ])),
        ])),
    ));
  }
}
