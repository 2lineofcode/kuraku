import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
      maxWidth: 480,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xff282828) : const Color(0xfff3f3f3),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      title: Text('Search sites'.tr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      content: SizedBox(width: 480, child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xff202020) : Colors.white,
          border: Border.all(color: AppColor.border, width: .5),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Obx(() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final site in DBSearchSite.sites) ...[
              if (site != DBSearchSite.sites.first) Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Divider(height: .5, thickness: .5, color: AppColor.border),
              ),
              Tooltip(message: 'Edit'.tr, child: CupertinoButton(
                key: ValueKey('search-site-${site.name}'),
                minimumSize: const Size(0, 35),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                onPressed: () => edit(site),
                child: Row(children: [
                  Expanded(child: Row(children: [
                    Flexible(child: Text(site.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColor.text))),
                    if (site.name == AppPref.getDefaultSearchEngine()) Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Tooltip(message: 'Default'.tr, child: Icon(CupertinoIcons.check_mark, size: 12, color: AppColor.muted)),
                    ),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Text(Uri.parse(site.searchUrl.replaceAll('{code}', 'ABC-001')).host.replaceFirst(RegExp(r'^www\.'), ''),
                    maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: AppColor.muted))),
                  const SizedBox(width: 10),
                  Icon(CupertinoIcons.chevron_right, size: 10, color: AppColor.muted),
                ]),
              )),
            ],
          ],
        ))),
      )),
      actions: [SizedBox(width: double.infinity, child: Row(children: [
        AppButton(variant: AppButtonVariant.outlined, height: 28,
          onPressed: () => edit(null), icon: const Icon(CupertinoIcons.add, size: 13), child: Text('Add site'.tr)),
        const Spacer(),
        Tooltip(message: 'Close'.tr, child: AppButton(variant: AppButtonVariant.filled, height: 28, width: 70,
          backgroundColor: CupertinoColors.activeBlue.resolveFrom(context), labelColor: CupertinoColors.white,
          onPressed: () => Navigator.pop(context), child: Text('Done'.tr))),
      ]))],
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

  Widget formRow(String label, Widget field) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 94, child: Padding(padding: const EdgeInsets.only(top: 7),
        child: Text(label, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: AppColor.text)))),
      const SizedBox(width: 10),
      Expanded(child: field),
    ]),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AppDialog(
      maxWidth: 480,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xff282828) : const Color(0xfff3f3f3),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      title: Text(widget.site?.name ?? 'Add site'.tr, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      content: SizedBox(width: 480, child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.site == null) formRow('Name'.tr,
            AppTextField(key: const ValueKey('site-name'), semanticsLabel: 'Name'.tr, controller: name, enabled: !busy, autofocus: true, placeholder: '',
              textInputAction: TextInputAction.next, decoration: InputDecoration(errorText: nameError)),
          ),
          formRow('Search URL'.tr, Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            AppTextField(key: const ValueKey('site-search-url'), semanticsLabel: 'Search URL'.tr, controller: search, enabled: !busy, autofocus: widget.site != null,
              autocorrect: false, enableSuggestions: false, keyboardType: TextInputType.url,
              textInputAction: showDownload ? TextInputAction.next : TextInputAction.done,
              onSubmitted: (_) { if (!showDownload) save(); },
              decoration: InputDecoration(errorText: searchError), placeholder: 'https://example.com/search?q={code}'),
            const SizedBox(height: 5),
            Text('{code} = video code'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted)),
          ])),
          Align(alignment: Alignment.centerLeft, child: AppButton(
            height: 24, padding: EdgeInsets.zero,
            onPressed: busy ? null : () => setState(() => showDownload = !showDownload),
            icon: Icon(showDownload ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right, size: 10, color: AppColor.muted),
            child: Text('Download URL (optional)'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted)),
          )),
          if (showDownload) Padding(padding: const EdgeInsets.only(top: 6), child: formRow('Download URL'.tr,
            AppTextField(key: const ValueKey('site-download-url'), semanticsLabel: 'Download URL (optional)'.tr, controller: download, enabled: !busy,
              autocorrect: false, enableSuggestions: false, keyboardType: TextInputType.url, textInputAction: TextInputAction.done,
              onSubmitted: (_) => save(), placeholder: 'Same as Search URL'.tr, decoration: InputDecoration(errorText: downloadError)),
          )),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error))),
        ],
      )),
      actions: [
        SizedBox(width: double.infinity, child: Row(children: [
          if (deleting) ...[
            Expanded(child: Text('Delete this site?'.tr, style: const TextStyle(fontSize: 12))),
            AppButton(variant: AppButtonVariant.outlined, height: 28,
              onPressed: busy ? null : () => setState(() => deleting = false), child: Text('Cancel'.tr)),
            const SizedBox(width: 8),
            AppButton(variant: AppButtonVariant.filled, height: 28, backgroundColor: CupertinoColors.systemRed.resolveFrom(context), labelColor: CupertinoColors.white,
              onPressed: busy ? null : remove, child: Text('Delete'.tr)),
          ] else ...[
            if (widget.site != null && !widget.site!.isDefault) AppIconButton(tooltip: 'Delete site'.tr,
              onPressed: busy ? null : () => setState(() => deleting = true),
              icon: Icon(CupertinoIcons.trash, size: AppStyle.iconSize, color: AppColor.muted)),
            const Spacer(),
            AppButton(variant: AppButtonVariant.outlined, height: 28, width: 70,
              onPressed: busy ? null : widget.onDone, child: Text('Cancel'.tr)),
            const SizedBox(width: 8),
            AppButton(variant: AppButtonVariant.filled, height: 28, width: 70,
              backgroundColor: CupertinoColors.activeBlue.resolveFrom(context), labelColor: CupertinoColors.white,
              onPressed: busy ? null : save, child: Text('Save'.tr)),
          ],
        ])),
      ],
    ),
  );
}
