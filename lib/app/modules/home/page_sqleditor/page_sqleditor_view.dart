import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:get/get.dart';

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../utils/helper_loading.dart';
import '../../../utils/helper_opener.dart';
import '../../widgets/widget_search_tab_bar.dart';
import '../../widgets/widget_thumbnail.dart';
import 'page_sqleditor_controller.dart';
import 'page_sqleditor_tab.dart';

class PageSqleditorView extends GetView<PageSqleditorController> {
  const PageSqleditorView({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
    Obx(() => controller.activeTab.resultsExpanded.value ? const SizedBox.shrink() : Padding(
      padding: const EdgeInsets.only(bottom: 8), child: SearchTabBar(
      tabs: controller.tabs.map((tab) => (title: tab.title, isLoading: tab.running.value || tab.generating.value)).toList(),
      activeIndex: controller.activeTabIndex.value,
      scrollController: controller.tabScrollController,
      onSelect: controller.selectTab, onClose: controller.closeTab, onAdd: controller.addTab,
      addTooltip: 'New SQL tab',
    ))),
    Obx(() => controller.saveError.value.isEmpty ? const SizedBox.shrink() : Row(children: [
      Expanded(child: Text(controller.saveError.value, style: TextStyle(fontSize: 11, color: Get.theme.colorScheme.error))),
      TextButton(onPressed: controller.saveTabs, child: const Text('Retry', style: TextStyle(fontSize: 11))),
    ])),
    Expanded(child: Obx(() {
      final tab = controller.activeTab;
      return PageSqleditorTabView(key: ValueKey(tab.id), controller: tab);
    })),
  ]);
}

class PageSqleditorTabView extends StatelessWidget {
  const PageSqleditorTabView({super.key, required this.controller, this.openVideoInfo = HelperOpener.openVideoInfo});

  final PageSqleditorTab controller;
  final Future<void> Function(dynamic item) openVideoInfo;

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Obx(() => controller.resultsExpanded.value ? _results() : Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 30,
          child: Row(children: [
            Expanded(child: Obx(() => Tooltip(
              message: controller.sources[controller.source.value] ?? 'No R18 database is loaded',
              child: DropdownButtonFormField<String>(
                initialValue: controller.source.value,
                isExpanded: true,
                style: TextStyle(fontSize: 12, color: AppColor.text),
                iconSize: 16,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  prefixIcon: Icon(Icons.storage_rounded, size: 14, color: AppColor.muted),
                  prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 28),
                ),
                items: controller.sources.keys.map((source) => DropdownMenuItem(value: source, child: Text(source))).toList(),
                onChanged: controller.running.value || controller.generating.value ? null : (value) { if (value != null) controller.selectSource(value); },
              ),
            ))),
            Obx(() => IconButton(
              tooltip: controller.schemaLoading.value ? 'Loading schema…'
                  : controller.schemaError.value.isNotEmpty ? controller.schemaError.value : 'Refresh table and column suggestions',
              visualDensity: VisualDensity.compact,
              icon: Icon(controller.schemaError.value.isEmpty ? Icons.refresh_rounded : Icons.error_outline, size: 14),
              onPressed: controller.schemaLoading.value ? null : controller.refreshSchema,
            )),
            const SizedBox(width: 4),
            Obx(() {
              controller.revision.value;
              final selection = controller.input.selection;
              final hasSelection = selection.isValid && !selection.isCollapsed;
              return Tooltip(
                message: controller.running.value ? 'Stop query' : '⌘ + Enter: ${hasSelection ? 'run selection' : 'run query'}. DELETE is blocked.',
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: controller.committing.value ? null : controller.running.value ? controller.stopQuery
                      : controller.query == null ? null : () => _runQuery(context),
                  icon: Icon(controller.running.value ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 14),
                  label: Text(controller.committing.value ? 'Saving…' : controller.running.value ? 'Stop' : hasSelection ? 'Run selection' : 'Run'),
                ),
              );
            }),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 3,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: AppColor.panel, border: Border.all(color: AppColor.border), borderRadius: BorderRadius.circular(6)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(children: [
                  const Text('Query', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Format SQL (selection or entire query)',
                    style: IconButton.styleFrom(minimumSize: const Size(28, 28), maximumSize: const Size(28, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.format_align_left_rounded, size: 14),
                    onPressed: controller.formatQuery,
                  ),
                  IconButton(
                    tooltip: 'Query parameters (JSON)',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.tune_rounded, size: 14),
                    onPressed: () => _showParameters(context),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap, textStyle: const TextStyle(fontSize: 11)),
                    icon: const Icon(Icons.code_rounded, size: 14),
                    label: const Text('Snippets'),
                    onPressed: () => _showSnippets(context),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap, textStyle: const TextStyle(fontSize: 11)),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 14),
                    label: const Text('Ask AI'),
                    onPressed: () => _showAi(context),
                  ),
                  IconButton(
                    tooltip: 'Clear query',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.clear_rounded, size: 14),
                    onPressed: () { controller.input.clear(); controller.focusNode.requestFocus(); },
                  ),
                ]),
              ),
              Divider(height: 1, color: AppColor.border),
              Expanded(child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter, meta: true, includeRepeats: false): () => _runQuery(context),
                },
                child: _SqlQueryInput(controller: controller),
              )),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Obx(() {
          controller.revision.value;
          final value = controller.input.value;
          final cursor = value.selection.isValid ? value.selection.extentOffset : 0;
          final before = value.text.substring(0, cursor);
          return Text('Ln ${'\n'.allMatches(before).length + 1}, Col ${cursor - before.lastIndexOf('\n')}  ·  Ctrl + Space suggest · ↑ ↓ select · Tab / Enter complete · Esc dismiss',
            style: TextStyle(fontSize: 10, color: AppColor.muted));
        }),
        const SizedBox(height: 8),
        Expanded(flex: 2, child: _results()),
      ],
    ));
  }

  void _runQuery(BuildContext context) {
    if (!controller.input.value.composing.isCollapsed) return;
    unawaited(controller.runQuery((sql, source, parameters) => _confirmWrite(context, sql, source, parameters)));
  }

  Future<bool> _confirmWrite(BuildContext context, String sql, String source, String parameters) async {
    if (!context.mounted) return false;
    return await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Confirm database change', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Source: $source', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          SelectableText(sql, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          const SizedBox(height: 8),
          SelectableText('Parameters: $parameters', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          const SizedBox(height: 8),
          const Text('This INSERT/UPDATE will be committed to the database. DELETE is blocked.', style: TextStyle(fontSize: 11)),
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply changes')),
      ],
    )) ?? false;
  }

  Future<void> _showParameters(BuildContext context) => showDialog<void>(context: context, builder: (context) => AlertDialog(
    title: const Text('Query parameters', style: TextStyle(fontSize: 14)),
    content: SizedBox(width: 400, child: TextField(
      controller: controller.parameters, minLines: 3, maxLines: 6,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      decoration: const InputDecoration(border: OutlineInputBorder(), helperText: 'Named: {"value": "example"} · Positional: [1, "text"]', helperMaxLines: 2),
    )),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
  ));

  Widget _results() => Obx(() {
    final result = controller.result.value;
    final columns = (result?['columns'] as List?) ?? [];
    final rows = (result?['rows'] as List?) ?? [];
    final thumbnailColumn = columns.indexWhere((column) => '$column'.trim().toLowerCase() == 'jacket_thumb_url');
    final hasThumbnail = thumbnailColumn >= 0;
    final message = controller.running.value ? controller.committing.value ? 'Saving changes…' : 'Running query…'
        : controller.queryError.value.isNotEmpty ? controller.queryError.value
        : result == null ? 'Run a query to see results.' : result['write'] == true ? '${result['affected_rows']} row(s) changed.' : 'No rows returned.';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(border: Border.all(color: AppColor.border), borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Row(children: [
          const Text('Results', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(child: Text(result == null ? ''
              : '${controller.resultSource.value} · ${result['write'] == true ? '${result['affected_rows']} changed · ' : ''}${rows.length} rows · ${result['elapsed_ms']} ms${result['truncated'] == true ? ' · truncated' : ''}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: AppColor.muted))),
          IconButton(
            tooltip: controller.resultsExpanded.value ? 'Restore query editor' : 'Expand results',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            padding: EdgeInsets.zero,
            icon: Icon(controller.resultsExpanded.value ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, size: 16),
            onPressed: () {
              controller.dismissSuggestions();
              controller.focusNode.unfocus();
              controller.resultsExpanded.toggle();
            },
          ),
        ])),
        Expanded(child: result == null || rows.isEmpty || columns.isEmpty
            ? Center(child: SingleChildScrollView(padding: const EdgeInsets.all(8), child: SelectableText(message, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: controller.queryError.value.isEmpty ? AppColor.muted : Get.theme.colorScheme.error))))
            : SelectionArea(key: const ValueKey('sql-results-table'), child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: columns.length * 160.0 + (hasThumbnail ? 96 : 0), height: constraints.maxHeight, child: Column(children: [
                  Container(color: AppColor.container, height: 28, child: Row(children: [
                    if (hasThumbnail) const SizedBox(width: 96, child: Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Thumbnail', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)))),
                    for (final column in columns) SizedBox(width: 160, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('$column', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)))),
                  ])),
                  Expanded(child: ListView.builder(itemCount: rows.length, itemExtent: hasThumbnail ? 64 : 30, itemBuilder: (context, index) => Row(children: [
                    if (hasThumbnail) _resultThumbnail(context, rows[index][thumbnailColumn]),
                    for (var column = 0; column < columns.length; column++) SizedBox(width: 160, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _resultCell(context, '${columns[column]}', rows[index][column]))),
                  ]))),
                ])),
              )))),
      ]),
    );
  });

  Widget _resultThumbnail(BuildContext context, dynamic value) {
    var url = value is String ? value.trim() : '';
    final uri = Uri.tryParse(url);
    if (uri?.host == 'pics.dmm.co.jp') url = uri!.path.replaceFirst(RegExp(r'^/'), '');
    final valid = uri != null && (['http', 'https'].contains(uri.scheme) && uri.hasAuthority
        || uri.scheme.isEmpty && uri.host.isEmpty && url.contains('/') && !url.startsWith('/'));
    final fallback = Icon(Icons.image_not_supported_outlined, size: 18, color: AppColor.muted);
    return SizedBox(width: 96, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(height: 56,
        child: !valid ? Center(child: fallback)
            : ExThumbnail(imageUrl: url, width: 80, height: 56, iconSize: 18, fitUrl: BoxFit.contain),
      )),
    ));
  }

  Widget _resultCell(BuildContext context, String column, dynamic value) {
    final text = value == null ? 'NULL' : '$value';
    if (['dvd_id', 'video_code'].contains(column.trim().toLowerCase()) && value is String && value.trim().isNotEmpty) {
      return TextButton(
        style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero,
          minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        onPressed: () async {
          try {
            await openVideoInfo(<String, dynamic>{'video_code': value.trim()});
          } catch (_) {
            HelperLoading.dismiss();
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open video info. Please retry.')));
          }
        },
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, decoration: TextDecoration.underline)),
      );
    }
    final style = TextStyle(fontFamily: 'monospace', fontSize: 11, color: value == null ? AppColor.muted : AppColor.text);
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(text: TextSpan(text: text, style: style), maxLines: 1,
        textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout(maxWidth: constraints.maxWidth);
      final truncated = painter.didExceedMaxLines;
      painter.dispose();
      final cell = Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
      return truncated ? Tooltip(message: text, child: cell) : cell;
    });
  }

  Future<void> _showSnippets(BuildContext context, {bool showSaved = false}) async {
    final tables = controller.schemaTables;
    var table = tables.isEmpty ? 'table_name' : tables.first;
    var action = 'SELECT';
    final loadedName = controller.loadedSnippetName;
    final loadedSql = controller.loadedSnippetSql;
    var saved = showSaved || loadedName != null;
    String? nextSource;
    var busy = false;
    var adding = false;
    var error = '';
    String? selected = loadedName;
    final source = controller.source.value;
    final selection = controller.input.selection;
    final currentSql = loadedSql ?? (selection.isValid && !selection.isCollapsed ? selection.textInside(controller.input.text) : controller.input.text);
    var name = '';
    final sql = await showDialog<String>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: AppColor.border)),
        insetPadding: const EdgeInsets.all(16),
        titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        title: Row(children: [
          const Icon(Icons.code_rounded, size: 16),
          const SizedBox(width: 8),
          const Expanded(child: Text('SQL snippets', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          PopupMenuButton<String>(
            tooltip: 'Snippet source', enabled: !busy && !controller.running.value && !controller.generating.value,
            onSelected: (value) { if (value != source) { nextSource = value; Navigator.pop(context); } },
            itemBuilder: (_) => [for (final item in controller.sources.keys)
              PopupMenuItem(value: item, child: Text('$item · ${controller.snippetsFor(item).length} saved', style: const TextStyle(fontSize: 12)))],
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(source, style: TextStyle(fontSize: 11, color: AppColor.muted)),
              const Icon(Icons.arrow_drop_down, size: 16),
            ])),
        ]),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: 6, children: [
              ChoiceChip(label: const Text('Templates', style: TextStyle(fontSize: 11)), selected: !saved, showCheckmark: false, visualDensity: VisualDensity.compact,
                onSelected: busy ? null : (_) => setState(() => saved = false)),
              ChoiceChip(label: const Text('Saved queries', style: TextStyle(fontSize: 11)), selected: saved, showCheckmark: false, visualDensity: VisualDensity.compact,
                onSelected: busy ? null : (_) => setState(() => saved = true)),
            ]),
            const SizedBox(height: 8),
            if (saved) ...[
              if (loadedName != null && controller.snippetsFor(source).containsKey(loadedName))
                Row(children: [
                  Expanded(child: Text('Editing: $loadedName', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                  TextButton.icon(icon: const Icon(Icons.save_outlined, size: 14),
                    label: const Text('Update snippet', style: TextStyle(fontSize: 11)),
                    onPressed: busy || loadedSql == null || loadedSql.trim().isEmpty || loadedSql.trim() == controller.snippetsFor(source)[loadedName] ? null : () async {
                      setState(() { busy = true; error = ''; });
                      try {
                        await controller.saveSnippet(source, loadedName, loadedSql, update: true);
                        if (context.mounted) setState(() => selected = loadedName);
                      } catch (_) {
                        if (context.mounted) setState(() => error = 'Could not update snippet. Please retry.');
                      } finally {
                        if (context.mounted) setState(() => busy = false);
                      }
                    }),
                ]),
              Row(children: [
                Expanded(child: Text('${controller.snippetsFor(source).length} saved queries', style: TextStyle(fontSize: 11, color: AppColor.muted))),
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: Icon(adding ? Icons.close : Icons.add, size: 14),
                  label: Text(adding ? 'Cancel save' : loadedName != null ? 'Save as new' : 'Save current query', style: const TextStyle(fontSize: 11)),
                  onPressed: busy || currentSql.trim().isEmpty ? null : () => setState(() { adding = !adding; error = ''; })),
              ]),
              if (adding) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: TextFormField(initialValue: name, autofocus: true, style: const TextStyle(fontSize: 12), enabled: !busy,
                    decoration: const InputDecoration(hintText: 'Snippet name', hintStyle: TextStyle(fontSize: 12), isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9), border: OutlineInputBorder()),
                    onChanged: (value) => name = value)),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 32), visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                    onPressed: busy ? null : () async {
                      setState(() { busy = true; error = ''; });
                      try {
                        await controller.saveSnippet(source, name, currentSql);
                        if (context.mounted) setState(() { selected = name.trim(); adding = false; name = ''; });
                      } catch (e) {
                        AppLog.logW('Failed to save SQL snippet: $e');
                        if (context.mounted) setState(() => error = e is StateError ? e.message.toString() : 'Could not save snippet. Please retry.');
                      } finally {
                        if (context.mounted) setState(() => busy = false);
                      }
                    }, child: Text(busy ? 'Saving…' : 'Save', style: const TextStyle(fontSize: 11))),
                ]),
                const SizedBox(height: 6),
                Text('SQL only · ${loadedName != null ? 'Loaded snippet' : selection.isValid && !selection.isCollapsed ? 'Selected text' : 'Full query'} · Parameters excluded',
                  style: TextStyle(fontSize: 10, color: AppColor.muted)),
                const SizedBox(height: 8),
              ],
              if (controller.snippetsFor(source).isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Column(children: [
                  Icon(Icons.bookmark_border_rounded, size: 24, color: AppColor.muted),
                  const SizedBox(height: 8),
                  Text('No saved queries in $source', style: const TextStyle(fontSize: 12)),
                  for (final item in controller.sources.keys.where((item) => item != source && controller.snippetsFor(item).isNotEmpty))
                    TextButton(onPressed: busy || controller.running.value || controller.generating.value ? null : () { nextSource = item; Navigator.pop(context); },
                      child: Text('View ${controller.snippetsFor(item).length} saved in $item', style: const TextStyle(fontSize: 11))),
                  const SizedBox(height: 4),
                  Text(currentSql.trim().isEmpty ? 'Write a query in the editor to save it here.' : 'Save your current query to reuse it later.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColor.muted)),
                ]))
              else Container(
                constraints: const BoxConstraints(maxHeight: 128),
                decoration: BoxDecoration(border: Border.all(color: AppColor.border), borderRadius: BorderRadius.circular(6)),
                child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                  for (final entry in controller.snippetsFor(source).entries)
                    ListTile(dense: true, visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      selected: selected == entry.key, selectedTileColor: Get.theme.colorScheme.primary.withValues(alpha: 0.10),
                      leading: const Icon(Icons.code, size: 16), minLeadingWidth: 16,
                      title: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      trailing: selected == entry.key ? const Icon(Icons.check, size: 14) : null,
                      onTap: busy ? null : () => setState(() { selected = entry.key; error = ''; })),
                ])),
              if (selected != null) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 140), padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColor.container, borderRadius: BorderRadius.circular(6)),
                  child: SingleChildScrollView(child: SelectableText(controller.snippetsFor(source)[selected] ?? '',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5)))),
                Align(alignment: Alignment.centerRight, child: TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColor.muted),
                  icon: const Icon(Icons.delete_outline, size: 14), label: const Text('Delete snippet', style: TextStyle(fontSize: 12)),
                  onPressed: busy ? null : () async {
                    setState(() { busy = true; error = ''; });
                    try {
                      await controller.saveSnippet(source, selected!, null);
                      if (context.mounted) setState(() => selected = null);
                    } catch (_) {
                      if (context.mounted) setState(() => error = 'Could not delete snippet. Please retry.');
                    } finally {
                      if (context.mounted) setState(() => busy = false);
                    }
                  })),
              ],
              if (error.isNotEmpty) Text(error, style: TextStyle(fontSize: 11, color: Get.theme.colorScheme.error)),
              if (selected != null) Text('Adds to editor · Does not run', style: TextStyle(fontSize: 10, color: AppColor.muted)),
            ] else ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 110, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Operation', style: TextStyle(fontSize: 10, color: AppColor.muted)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('snippet-operation'), initialValue: action, isExpanded: true, iconSize: 16,
                    style: TextStyle(fontSize: 11, color: AppColor.text),
                    decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6))),
                    items: PageSqleditorTab.snippetActions.where((item) => item != 'DELETE')
                        .map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) { if (value != null) setState(() => action = value); }),
                ])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Table', style: TextStyle(fontSize: 10, color: AppColor.muted)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<String>(
                    initialValue: table, isExpanded: true, iconSize: 16, menuMaxHeight: 260,
                    style: TextStyle(fontSize: 12, color: AppColor.text),
                    decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6))),
                    items: (tables.isEmpty ? ['table_name'] : tables).map((name) => DropdownMenuItem(value: name,
                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (value) { if (value != null) setState(() => table = value); }),
                ])),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                const Expanded(child: Text('SQL preview', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600))),
                Text('Editable after adding', style: TextStyle(fontSize: 10, color: AppColor.muted)),
              ]),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 180), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColor.container, border: Border.all(color: AppColor.border), borderRadius: BorderRadius.circular(6)),
                child: SingleChildScrollView(child: SelectableText(controller.buildSnippet(action, table),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.6))),
              ),
              const SizedBox(height: 8),
              Text(action == 'SELECT' ? 'Adds to editor · Does not run' : 'Set :value in Parameters before running.',
                style: TextStyle(fontSize: 10, color: AppColor.muted)),
            ],
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(fontSize: 12))),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 30), visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))), onPressed: busy || (saved && selected == null) ? null : () => Navigator.pop(context, saved ? controller.snippetsFor(source)[selected] : controller.buildSnippet(action, table)),
            child: Text(saved ? 'Load snippet' : 'Add to editor', style: const TextStyle(fontSize: 12))),
        ],
      ),
    ));
    if (nextSource != null && context.mounted) {
      controller.selectSource(nextSource!);
      await _showSnippets(context, showSaved: true);
    } else if (sql != null) {
      controller.appendSnippet(sql, name: saved ? selected : null);
    }
  }

  Future<void> _showAi(BuildContext context) {
    return showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('Generate SQL with AI', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Obx(() => Tooltip(
            message: controller.schemaTables.join(', '),
            child: Text('${controller.source.value} · ${controller.schemaLoading.value ? 'Loading schema…' : controller.schemaError.value.isNotEmpty ? 'Schema unavailable' : '${controller.schemaTables.length} tables / views'}',
              style: TextStyle(fontSize: 11, color: AppColor.muted)),
          )),
          const SizedBox(height: 12),
          TextField(
            controller: controller.aiPrompt,
            onChanged: (_) { controller.stopGeneration(); controller.aiSql.value = ''; controller.aiError.value = ''; },
            minLines: 3,
            maxLines: 5,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              labelText: 'Describe your query', labelStyle: TextStyle(fontSize: 12),
              hintText: 'Example: Show the 20 most recently added videos',
              hintStyle: TextStyle(fontSize: 11),
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(10),
            ),
          ),
          const SizedBox(height: 8),
          Text('Your prompt and table/column names are sent to the configured AI provider. Review SQL before running it.', style: TextStyle(fontSize: 11, color: AppColor.muted)),
          const SizedBox(height: 12),
          const Text('SQL preview', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColor.container, borderRadius: BorderRadius.circular(6)),
            child: Obx(() => SelectableText(controller.generating.value ? 'Generating and validating SQL…'
                : controller.aiError.value.isNotEmpty ? controller.aiError.value
                : controller.aiSql.value.isEmpty ? 'Generated SQL will appear here for review.' : controller.aiSql.value,
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: controller.aiError.value.isEmpty ? AppColor.text : Theme.of(context).colorScheme.error, height: 1.5))),
          ),
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(fontSize: 12))),
        Obx(() => TextButton(onPressed: controller.generating.value || controller.aiSql.value.isEmpty ? null : () {
          Navigator.pop(context);
          controller.insertGeneratedSql();
        }, child: const Text('Insert SQL', style: TextStyle(fontSize: 12)))),
        Obx(() => FilledButton(onPressed: controller.generating.value ? controller.stopGeneration : controller.generateSql,
          child: Text(controller.generating.value ? 'Stop' : controller.aiError.value.isEmpty ? 'Generate' : 'Retry', style: const TextStyle(fontSize: 12)))),
      ],
    )).whenComplete(controller.stopGeneration);
  }

}

class _SqlQueryInput extends StatefulWidget {
  const _SqlQueryInput({required this.controller});

  final PageSqleditorTab controller;

  @override
  State<_SqlQueryInput> createState() => _SqlQueryInputState();
}

class _SqlQueryInputState extends State<_SqlQueryInput> {
  final _stackKey = GlobalKey();
  final _scroll = ScrollController();
  Rect? _caret;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.input.addListener(_schedulePosition);
    widget.controller.focusNode.addListener(_schedulePosition);
    _scroll.addListener(_schedulePosition);
  }

  void _schedulePosition() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final editable = widget.controller.focusNode.context?.findAncestorStateOfType<EditableTextState>();
      final render = editable?.renderEditable;
      final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
      final selection = widget.controller.input.selection;
      Rect? caret;
      if (render != null && render.hasSize && stack != null && stack.hasSize && selection.isValid) {
        final local = render.getLocalRectForCaret(selection.extent);
        if (local.overlaps(Offset.zero & render.size)) {
          caret = local.shift(render.localToGlobal(Offset.zero, ancestor: stack));
        }
      }
      if (_caret != caret) setState(() => _caret = caret);
    });
  }

  @override
  void dispose() {
    widget.controller.input.removeListener(_schedulePosition);
    widget.controller.focusNode.removeListener(_schedulePosition);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    _schedulePosition();
    final controller = widget.controller;
    final width = constraints.maxWidth.clamp(0.0, 360.0);
    return Stack(key: _stackKey, children: [
      Positioned.fill(child: Focus(
        onKeyEvent: controller.onKeyEvent,
        child: TextField(
          controller: controller.input,
          focusNode: controller.focusNode,
          scrollController: _scroll,
          expands: true, minLines: null, maxLines: null,
          autocorrect: false, enableSuggestions: false,
          smartDashesType: SmartDashesType.disabled, smartQuotesType: SmartQuotesType.disabled,
          textAlignVertical: TextAlignVertical.top, keyboardType: TextInputType.multiline,
          style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.45, color: AppColor.text),
          decoration: const InputDecoration(hintText: 'Write a SQL query…', border: InputBorder.none, contentPadding: EdgeInsets.all(10)),
        ),
      )),
      if (_caret != null) Positioned(
        left: _caret!.left.clamp(0.0, constraints.maxWidth - width),
        top: _caret!.top,
        width: width,
        height: _caret!.height,
        child: TypeAheadField<String>(
          controller: controller.input,
          focusNode: controller.focusNode,
          suggestionsController: controller.completionPopup,
          debounceDuration: Duration.zero,
          animationDuration: Duration.zero,
          transitionBuilder: (context, animation, child) => child,
          hideOnEmpty: true, hideOnLoading: true, retainOnLoading: false,
          offset: const Offset(0, 2),
          constraints: const BoxConstraints(maxHeight: 180),
          suggestionsCallback: (_) {
            if (controller.suggestions.isEmpty) {
              controller.completionPopup.close(retainFocus: true);
              return null;
            }
            return controller.suggestions.toList();
          },
          onSelected: controller.complete,
          builder: (_, input, focusNode) => const SizedBox.expand(),
          decorationBuilder: (context, child) => Material(
            key: const ValueKey('sql-completion-popup'),
            color: AppColor.panel, elevation: 4, clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: AppColor.border)),
            child: child,
          ),
          itemBuilder: (context, suggestion) {
            final selection = controller.input.selection;
            final before = selection.isValid ? controller.input.text.substring(0, selection.extentOffset) : '';
            final prefix = RegExp(r'[A-Za-z_][A-Za-z_0-9]*$').stringMatch(before) ?? '';
            final matched = PageSqleditorTab.completionMatch(suggestion, prefix)?.toSet() ?? <int>{};
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                Icon(PageSqleditorTab.keywords.contains(suggestion) ? Icons.code_rounded
                    : controller.schemaTables.contains(suggestion) ? Icons.table_chart_outlined : Icons.view_column_outlined,
                  size: 14, color: AppColor.muted),
                const SizedBox(width: 6),
                Expanded(child: Text.rich(TextSpan(children: [
                  for (var index = 0; index < suggestion.length; index++)
                    TextSpan(text: suggestion[index], style: matched.contains(index)
                        ? TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600) : null),
                ]), style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColor.text))),
              ]),
            );
          },
        ),
      ),
    ]);
  });
}
