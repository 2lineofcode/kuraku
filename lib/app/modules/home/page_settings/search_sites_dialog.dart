import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/app_color.dart';
import '../../../core/app_pref.dart';
import '../../../data/database/db_search_site.dart';
import '../../../data/models/search_site.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_style.dart';
import '../../widgets/widget_surfaces.dart';

class SearchSitesDialog extends StatefulWidget {
  const SearchSitesDialog({super.key});

  @override
  State<SearchSitesDialog> createState() => _SearchSitesDialogState();
}

class _SearchSitesDialogState extends State<SearchSitesDialog> {
  bool editing = false;
  SearchSite? selected;

  void edit(SearchSite? site) => setState(() { selected = site; editing = true; });

  @override
  Widget build(BuildContext context) {
    if (editing) return SearchSiteEditor(site: selected, onDone: () => setState(() => editing = false));
    return AppDialog(
      maxWidth: 440,
      titlePadding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
      contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      title: Row(children: [
        Expanded(child: Text('Search sites'.tr)),
        AppButton(onPressed: () => edit(null), icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: AppStyle.iconSize), child: Text('Add site'.tr)),
        const SizedBox(width: 4),
        AppIconButton(tooltip: 'Close'.tr, onPressed: () => Navigator.pop(context),
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize)),
      ]),
      content: SizedBox(width: 440, child: Material(type: MaterialType.transparency, child: Obx(() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final site in DBSearchSite.sites) InkWell(
            key: ValueKey('search-site-${site.name}'),
            onTap: () => edit(site),
            borderRadius: BorderRadius.circular(AppStyle.radius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                Expanded(child: Row(children: [
                  Flexible(child: Text(site.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                  if (site.name == AppPref.getDefaultSearchEngine()) Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Tooltip(message: 'Default'.tr, child: HugeIcon(icon: HugeIcons.strokeRoundedTick02, size: 14, color: AppColor.muted)),
                  ),
                ])),
                const SizedBox(width: 12),
                Expanded(child: Text(Uri.parse(site.searchUrl.replaceAll('{code}', 'ABC-001')).host.replaceFirst(RegExp(r'^www\.'), ''),
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: AppColor.muted))),
                const SizedBox(width: 8),
                AppIconButton(tooltip: 'Edit'.tr, onPressed: () => edit(site),
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: AppStyle.iconSize)),
              ]),
            ),
          ),
        ],
      )))),
    );
  }
}

class SearchSiteEditor extends StatefulWidget {
  const SearchSiteEditor({super.key, this.site, required this.onDone});
  final SearchSite? site;
  final VoidCallback onDone;

  @override
  State<SearchSiteEditor> createState() => _SearchSiteEditorState();
}

class _SearchSiteEditorState extends State<SearchSiteEditor> {
  late final name = TextEditingController(text: widget.site?.name);
  late final search = TextEditingController(text: widget.site?.searchUrl);
  late final download = TextEditingController(text: widget.site?.downloadUrl == widget.site?.searchUrl ? '' : widget.site?.downloadUrl);
  late bool showDownload = download.text.isNotEmpty;
  String? nameError, searchError, downloadError, error;
  bool busy = false;
  bool deleting = false;

  @override
  void dispose() {
    name.dispose();
    search.dispose();
    download.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || deleting) return;
    setState(() {
      nameError = name.text.trim().isEmpty || name.text.trim().length > 60 ? 'Enter a name (1–60 characters).'.tr : null;
      searchError = SearchSite.validTemplate(search.text.trim()) ? null : 'Use an HTTP(S) URL with {code}.'.tr;
      downloadError = download.text.trim().isEmpty || SearchSite.validTemplate(download.text.trim()) ? null : 'Use an HTTP(S) URL with {code}.'.tr;
      if (downloadError != null) showDownload = true;
      error = null;
    });
    if (nameError != null || searchError != null || downloadError != null) return;
    setState(() => busy = true);
    try {
      final site = SearchSite(name.text.trim(), search.text.trim(), download.text.trim().isEmpty ? search.text.trim() : download.text.trim());
      await DBSearchSite.save(site, update: widget.site != null);
      if (mounted) widget.onDone();
    } on DatabaseException catch (e) {
      if (mounted) setState(() {
        if (e.isUniqueConstraintError()) { nameError = 'A site with this name already exists.'.tr; }
        else { error = 'Could not save search site.'.tr; }
      });
    } catch (_) {
      if (mounted) setState(() => error = 'Could not save search site.'.tr);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final site = widget.site!;
      final selected = AppPref.getDefaultSearchEngine();
      await DBSearchSite.remove(site);
      if (selected == site.name) AppPref.setDefaultSearchEngine('NJAV');
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) setState(() => error = 'Could not delete search site.'.tr);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AppDialog(
      maxWidth: 440,
      titlePadding: const EdgeInsets.fromLTRB(8, 10, 16, 12),
      title: Row(children: [
        AppIconButton(tooltip: 'Back'.tr, onPressed: busy ? null : widget.onDone,
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: AppStyle.iconSize)),
        const SizedBox(width: 8),
        Expanded(child: Text(widget.site?.name ?? 'Add site'.tr, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
      content: SizedBox(width: 440, child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.site == null) ...[
            AppTextField(key: const ValueKey('site-name'), semanticsLabel: 'Name'.tr, controller: name, enabled: !busy, autofocus: true, placeholder: '',
              textInputAction: TextInputAction.next, decoration: InputDecoration(labelText: 'Name'.tr, errorText: nameError)),
            const SizedBox(height: 12),
          ],
          AppTextField(key: const ValueKey('site-search-url'), semanticsLabel: 'Search URL'.tr, controller: search, enabled: !busy, autofocus: widget.site != null,
            autocorrect: false, enableSuggestions: false, keyboardType: TextInputType.url,
            textInputAction: showDownload ? TextInputAction.next : TextInputAction.done,
            onSubmitted: (_) { if (!showDownload) save(); },
            decoration: InputDecoration(labelText: 'Search URL'.tr, errorText: searchError), placeholder: 'https://example.com/search?q={code}'),
          const SizedBox(height: 6),
          Text('{code} = video code'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted)),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: AppButton(
            padding: EdgeInsets.zero,
            onPressed: busy ? null : () => setState(() => showDownload = !showDownload),
            icon: HugeIcon(icon: showDownload ? HugeIcons.strokeRoundedArrowUp01 : HugeIcons.strokeRoundedArrowDown01, size: 14),
            child: Text('Download URL (optional)'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted)),
          )),
          if (showDownload) AppTextField(key: const ValueKey('site-download-url'), semanticsLabel: 'Download URL (optional)'.tr, controller: download, enabled: !busy,
            autocorrect: false, enableSuggestions: false, keyboardType: TextInputType.url, textInputAction: TextInputAction.done,
            onSubmitted: (_) => save(), placeholder: 'Same as Search URL'.tr, decoration: InputDecoration(errorText: downloadError)),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error))),
        ],
      )),
      actions: [
        SizedBox(width: double.infinity, child: Row(children: [
          if (deleting) ...[
            Expanded(child: Text('Delete this site?'.tr, style: const TextStyle(fontSize: 12))),
            AppButton(onPressed: busy ? null : () => setState(() => deleting = false), child: Text('Cancel'.tr)),
            AppButton(onPressed: busy ? null : remove, labelColor: Theme.of(context).colorScheme.error, child: Text('Delete'.tr)),
          ] else ...[
            if (widget.site != null && !widget.site!.isDefault) AppIconButton(tooltip: 'Delete site'.tr,
              onPressed: busy ? null : () => setState(() => deleting = true),
              icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: AppStyle.iconSize, color: AppColor.muted)),
            const Spacer(),
            AppButton(onPressed: busy ? null : widget.onDone, child: Text('Cancel'.tr)),
            const SizedBox(width: 8),
            AppButton(variant: AppButtonVariant.outlined, onPressed: busy ? null : save, child: Text('Save'.tr)),
          ],
        ])),
      ],
    ),
  );
}
