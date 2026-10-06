import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:uicons_pro/uicons_pro.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_color.dart';
import '../../../core/app_translations.dart';
import '../../../data/models/chat_entity.dart';
import '../../../utils/chat_knowledge.dart';
import '../../../utils/chat_service.dart';
import '../../widgets/widget_thumbnail.dart';
import 'page_chat_controller.dart';

class PageChatView extends GetView<PageChatController> {
  const PageChatView({super.key});

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Column(children: [
      Obx(() => controller.error.value.isEmpty ? const SizedBox.shrink() : Row(children: [
        Expanded(child: Text(controller.error.value.tr, style: const TextStyle(fontSize: 12, color: Colors.red))),
        TextButton(onPressed: controller.busy.value ? null : controller.retry, child: Text('Retry'.tr)),
      ])),
      Obx(() => controller.busy.value ? const LinearProgressIndicator(minHeight: 2) : const SizedBox(height: 2)),
      Expanded(child: Obx(() => AbsorbPointer(
        absorbing: controller.busy.value || !controller.ready.value,
        child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return Scaffold(
              backgroundColor: AppColor.body,
              drawer: wide ? null : Drawer(width: 240, child: _sidebar(closeOnSelect: true)),
              body: Row(children: [
                if (wide) Obx(() => controller.sidebarVisible.value
                  ? SizedBox(width: 224, child: _sidebar()) : const SizedBox.shrink()),
                Expanded(child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      Builder(builder: (context) => IconButton(
                        tooltip: 'Toggle chat history'.tr,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                        padding: EdgeInsets.zero,
                        icon: Icon(UIconsPro.regularRounded.sidebar, size: 14),
                        onPressed: () {
                          if (wide) {
                            controller.toggleSidebar();
                          } else {
                            Scaffold.of(context).openDrawer();
                          }
                        },
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: Obx(() => Text(controller.activeChat.value.title == 'New chat' ? 'New chat'.tr : controller.activeChat.value.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))),
                      IconButton(tooltip: 'Delete chat'.tr,
                        onPressed: () => _editChat(context, controller.activeChat.value, deleting: true),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.delete_outline_rounded, size: 16)).pOnly(right: 8),
                      IconButton(tooltip: 'New chat'.tr, onPressed: controller.newChat,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                        padding: EdgeInsets.zero,
                        icon: Icon(UIconsPro.regularRounded.plus, size: 14)),
                      
                    ]),
                  ),
                  Expanded(child: Center(child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Column(children: [
                        Expanded(child: Obx(() => controller.messages.isEmpty ? _welcome() : _conversation())),
                        const SizedBox(height: 8),
                        _composer(),
                        const SizedBox(height: 8),
                      ]),
                    ),
                  ))),
                ])),
              ]),
            );
        }),
      ))),
    ]);
  }

  Widget _sidebar({bool closeOnSelect = false}) {
    return Builder(builder: (context) => Container(
      decoration: BoxDecoration(color: AppColor.appBar, border: Border(right: BorderSide(color: AppColor.border))),
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(4, 0, 0, 4), child: Row(children: [
          const Expanded(child: Text('JavIt AI', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Delete all chats'.tr, onPressed: () => _deleteAllChats(context),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.delete_sweep_outlined, size: 16)),
        ])),
        SizedBox(width: double.infinity, child: ExButtonOutline(
          height: 38, radius: 12, labelSize: 12,
          borderColor: AppColor.border, labelColor: AppColor.text,
          onPressed: () {
            controller.newChat();
            if (closeOnSelect) Navigator.pop(context);
          },
          icon: Icon(UIconsPro.regularRounded.plus, size: 14, color: AppColor.text),
          label: 'New chat'.tr,
        )),
        const SizedBox(height: 8),
        CupertinoTextField(
          controller: controller.searchInput,
          onChanged: (value) => controller.search.value = value,
          style: TextStyle(fontSize: 12, color: AppColor.text),
          placeholder: 'Search chats'.tr,
          prefix: Icon(UIconsPro.regularRounded.search, size: 12, color: AppColor.muted).pOnly(left: 8),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Text('Your chats'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted))),
        Expanded(child: Obx(() {
          final query = controller.search.value.trim().toLowerCase();
          final active = controller.activeChat.value;
          final chats = controller.chats.where((chat) => chat.title.toLowerCase().contains(query)).toList();
          if (chats.isEmpty) return Center(child: Text('No chats found'.tr, style: TextStyle(fontSize: 12, color: AppColor.muted)));
          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: chat == active ? AppColor.selected : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    minTileHeight: 32,
                    minVerticalPadding: 0,
                    selected: chat == active,
                    selectedColor: AppColor.text,
                    contentPadding: const EdgeInsets.only(left: 8),
                    leading: chat.isPinned ? Icon(Icons.push_pin_rounded, size: 13, color: AppColor.muted) : null,
                    minLeadingWidth: 14,
                    title: Text(chat.title == 'New chat' ? 'New chat'.tr : chat.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    onTap: () {
                      controller.selectChat(chat);
                      if (closeOnSelect) Navigator.pop(context);
                    },
                    trailing: MenuAnchor(
                      menuChildren: [
                        MenuItemButton(
                          leadingIcon: Icon(chat.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, size: 12),
                          onPressed: () => controller.togglePin(chat),
                          child: Text(chat.isPinned ? 'Unpin chat'.tr : 'Pin chat'.tr, style: const TextStyle(fontSize: 12)),
                        ),
                        MenuItemButton(
                          leadingIcon: Icon(UIconsPro.regularRounded.edit, size: 12),
                          onPressed: () => _editChat(context, chat, deleting: false),
                          child: Text('Rename'.tr, style: TextStyle(fontSize: 12)),
                        ),
                        MenuItemButton(
                          leadingIcon: Icon(UIconsPro.regularRounded.trash, size: 12),
                          onPressed: () => _editChat(context, chat, deleting: true),
                          child: Text('Delete'.tr, style: TextStyle(fontSize: 12)),
                        ),
                      ],
                      builder: (context, menu, _) => IconButton(
                        tooltip: 'Chat options'.tr,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(UIconsPro.regularRounded.menu_dots, size: 12),
                        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        })),
      ]),
    ));
  }

  Widget _welcome() {
    return Center(child: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColor.selected, borderRadius: BorderRadius.circular(8)),
          child: Icon(UIconsPro.regularRounded.comment_alt_dots, size: 24, color: AppColor.text),
        ),
        const SizedBox(height: 12),
        Text('What would you like to explore?'.tr, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Ask about your library and the local R18 catalog.'.tr, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColor.muted)),
        const SizedBox(height: 16),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final template in PageChatController.templates.entries)
            ExButtonOutline(height: 36, radius: 18, borderColor: AppColor.border, labelColor: AppColor.text,
              onPressed: () => controller.useTemplate(template.key),
              child: Text(template.value.label.tr, style: TextStyle(fontSize: 11, color: AppColor.text))),
          for (final prompt in ['How many videos do I have?'.tr, 'Show my favorites'.tr, 'Compare my collection with the R18 catalog'.tr])
            ExButtonOutline(height: 36, radius: 18,
              borderColor: AppColor.border, labelColor: AppColor.text,
              onPressed: () => controller.usePrompt(prompt),
              child: Text(prompt, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColor.text))),
        ]),
      ]),
    ));
  }

  Widget _messageEditor() {
    return Obx(() {
      final disabled = controller.busy.value || controller.respondingChatId.value != null;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColor.hover, borderRadius: BorderRadius.circular(18)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          CupertinoTextField(
            key: const ValueKey('edit-message-input'), controller: controller.editInput,
            autofocus: true, minLines: 2, maxLines: 10, readOnly: disabled,
            style: TextStyle(fontSize: 13, color: AppColor.text),
            placeholder: 'Edit message'.tr,
          ),
          const SizedBox(height: 8),
          Text('Resubmitting replaces the messages after this one.'.tr, style: TextStyle(fontSize: 10, color: AppColor.muted)),
          const SizedBox(height: 4),
          Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
            TextButton(onPressed: disabled ? null : controller.cancelEdit, child: Text('Cancel'.tr)),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller.editInput,
              builder: (context, value, _) => FilledButton(
                onPressed: disabled || value.text.trim().isEmpty ? null : controller.submitEdit,
                child: Text('Save & resend'.tr),
              ),
            ),
          ]),
        ]),
      );
    });
  }

  Widget _conversation() {
    return ListView.builder(
      controller: controller.scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: controller.messages.length,
      itemBuilder: (context, index) {
        final position = controller.messages.length - 1 - index;
        final message = controller.messages[position];
        final assistant = message.role == 'assistant';
        final generating = message.status == 'pending' || message.status == 'streaming';
        final invalid = assistant && ChatService.isProtocolText(message.content);
        if (assistant && (message.status == 'failed' || invalid) && position + 1 < controller.messages.length && controller.messages[position + 1].role == 'assistant') {
          return const SizedBox.shrink();
        }
        final content = invalid ? '' : assistant ? ChatKnowledge.normalizeTableHeaders(message.content.trim()) : message.content.trim();
        return LayoutBuilder(key: ValueKey(message.id), builder: (context, constraints) => Align(
          alignment: assistant ? Alignment.centerLeft : Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: assistant ? 760 : constraints.maxWidth * .8),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: assistant ? CrossAxisAlignment.start : CrossAxisAlignment.end, children: [
                if (assistant) ...[
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome_outlined, size: 15, color: AppColor.muted),
                    const SizedBox(width: 8),
                    Text(message.provider == 'local' ? 'Local library'.tr : message.provider ?? 'AI', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 8),
                  if (generating || message.activity.isNotEmpty)
                    _ChatActivityPanel(key: ValueKey('activity-${message.id}'), steps: List.of(message.activity),
                      active: generating, status: message.status, elapsedMs: message.elapsedMs),
                ],
                if (content.isNotEmpty) Obx(() => controller.editingMessageId.value == message.id && !assistant
                  ? _messageEditor()
                  : Container(
                      key: ValueKey('bubble-${message.id}'),
                      padding: assistant ? const EdgeInsets.symmetric(vertical: 8) : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: assistant ? null : BoxDecoration(color: AppColor.hover, borderRadius: BorderRadius.circular(18)),
                      child: _markdown(context, content, databasePaged: message.titleSearch != null),
                    )),
                if (message.titleSearch != null && !generating) Obx(() {
                  final offset = message.titleSearch!['offset'] as int? ?? 0;
                  final disabled = controller.busy.value || controller.respondingChatId.value != null;
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Page @{offset}'.trNamed({'offset': '${offset ~/ 25 + 1}'}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
                    IconButton(tooltip: 'Previous database page'.tr, visualDensity: VisualDensity.compact,
                      onPressed: disabled || offset == 0 ? null : () => controller.loadTitleSearchPage(message, -1),
                      icon: const Icon(Icons.chevron_left_rounded, size: 18)),
                    IconButton(tooltip: 'Next database page'.tr, visualDensity: VisualDensity.compact,
                      onPressed: disabled || message.titleSearch!['has_more'] != true ? null : () => controller.loadTitleSearchPage(message, 1),
                      icon: const Icon(Icons.chevron_right_rounded, size: 18)),
                    if (controller.loadingPageId.value == message.id) const CupertinoActivityIndicator(radius: 6),
                  ]);
                }),
                if (message.errorMessage != null || message.status == 'cancelled' || invalid) Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: AppColor.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColor.border)),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: AppColor.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(invalid ? 'This older response could not be processed. Please retry.'.tr : message.errorMessage?.tr ?? 'Response stopped.'.tr,
                      style: TextStyle(fontSize: 12, color: AppColor.muted))),
                  ]),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (content.isNotEmpty && !generating) IconButton(
                    tooltip: 'Copy message'.tr, visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(width: 30, height: 30), padding: EdgeInsets.zero,
                    icon: Icon(Icons.copy_rounded, size: 14, color: AppColor.muted),
                    onPressed: () => _copy(context, content),
                  ),
                  if (!assistant) Obx(() => IconButton(
                    tooltip: 'Edit message'.tr, visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(width: 30, height: 30), padding: EdgeInsets.zero,
                    icon: Icon(Icons.edit_outlined, size: 14, color: AppColor.muted),
                    onPressed: controller.busy.value || controller.respondingChatId.value != null
                        ? null : () => controller.editMessage(message),
                  )),
                  if (index == 0 && (!assistant || message.status == 'failed' || message.status == 'cancelled' || invalid))
                    Obx(() => controller.respondingChatId.value != null ? const SizedBox.shrink() : TextButton.icon(
                      onPressed: controller.retryResponse,
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: Text('Retry response'.tr, style: TextStyle(fontSize: 11)),
                    )),
                ]),
              ]),
            ),
          ),
        ));
      },
    );
  }

  Widget _markdown(BuildContext context, String content, {bool databasePaged = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final images = RegExp(r'!\[([^\]]*)\]\(([^\s)]*)\)').allMatches(content)
        .map((match) => (url: _imageUrl(match[2]!), code: match[1]!)).where((image) => image.url.isNotEmpty).toList();
    return MarkdownBlock(
      data: content,
      config: (dark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig).copy(configs: [
        PConfig(textStyle: TextStyle(fontSize: 14, height: 1.6, color: AppColor.text)),
        ImgConfig(builder: (url, attributes) {
          final imageUrl = _imageUrl(url);
          final valid = imageUrl.isNotEmpty;
          return Semantics(label: 'Cover for @{video}'.trNamed({'video': '${attributes['alt'] ?? 'video'.tr}'}), image: true,
            child: ClipRRect(borderRadius: BorderRadius.circular(6), child: valid
              ? Tooltip(message: 'Preview image'.tr, child: Material(color: Colors.transparent, child: InkWell(
                  onTap: () => _previewImage(context, imageUrl, attributes['alt'] ?? 'Image', images),
                  child: ExThumbnail(imageUrl: imageUrl, videoCode: attributes['alt'], width: 96, height: 64,
                    iconSize: 20, fitUrl: BoxFit.cover),
                )))
              : Container(width: 96, height: 64, color: AppColor.hover,
                  child: Icon(Icons.image_not_supported_outlined, size: 20, color: AppColor.muted))),
          );
        }),
        TableConfig(
          border: TableBorder.all(color: AppColor.border),
          headerRowDecoration: BoxDecoration(color: AppColor.hover),
          wrapper: (child) => child is Table && (databasePaged || child.children.length > 26)
            ? _ChatTable(table: child, databasePaged: databasePaged) : SingleChildScrollView(scrollDirection: Axis.horizontal, child: child),
        ),
        (dark ? PreConfig.darkConfig : const PreConfig()).copy(
          textStyle: const TextStyle(fontSize: 13, fontFamily: 'monospace', height: 1.5),
          decoration: BoxDecoration(color: AppColor.panel, borderRadius: BorderRadius.circular(12)),
          wrapper: (child, code, language) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(language.isEmpty ? 'Code'.tr : language, style: TextStyle(fontSize: 11, color: AppColor.muted))),
              IconButton(tooltip: 'Copy code'.tr, visualDensity: VisualDensity.compact,
                onPressed: () => _copy(context, code), icon: const Icon(Icons.copy_rounded, size: 14)),
            ]),
            child,
          ]),
        ),
        LinkConfig(style: TextStyle(color: AppColor.accent, decoration: TextDecoration.underline), onTap: (value) async {
          if (value.startsWith('javit-translate:')) {
            try { await _translateTitle(context, Uri.decodeComponent(value.substring('javit-translate:'.length))); } on FormatException { /* Ignore malformed action links. */ }
            return;
          }
          if (value.startsWith('javit-similar:')) {
            try {
              final code = Uri.decodeComponent(value.substring('javit-similar:'.length));
              controller.usePrompt('Find videos similar to @{code} based on themes in their titles and descriptions, not just their cast. Explain the sources of the matches.'.trNamed({'code': '$code'}));
            } on FormatException { /* Ignore malformed action links. */ }
            return;
          }
          final uri = Uri.tryParse(value);
          if (uri == null || !['https', 'http'].contains(uri.scheme) || uri.host.isEmpty) return;
          try {
            if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
          } catch (_) {}
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open this link.'.tr)));
        }),
      ]),
    );
  }

  Future<void> _translateTitle(BuildContext context, String title) {
    Future<String>? translation;
    return showDialog<void>(context: context, builder: (context) => StatefulBuilder(builder: (context, setState) => AlertDialog(
      title: Text('Indonesian translation'.tr, style: TextStyle(fontSize: 16)),
      content: SizedBox(width: 540, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(title, style: TextStyle(fontSize: 12, color: AppColor.muted)),
          const SizedBox(height: 16),
          FutureBuilder<String>(future: translation ??= controller.translateTitle(title), builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const CupertinoActivityIndicator();
            if (snapshot.hasError) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(snapshot.error is ChatException ? (snapshot.error as ChatException).message.tr : 'Could not load or save the translation.'.tr, style: const TextStyle(fontSize: 12)),
              TextButton(onPressed: () => setState(() => translation = null), child: Text('Retry translation'.tr)),
            ]);
            return SelectableText(snapshot.data ?? '', style: const TextStyle(fontSize: 14));
          }),
        ],
      ))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Close'.tr))],
    )));
  }

  String _imageUrl(String url) {
    final localCover = url.startsWith('javit-cover:');
    try {
      final value = localCover ? Uri.decodeComponent(url.substring('javit-cover:'.length)) : url;
      final uri = Uri.tryParse(value);
      return value.isNotEmpty && (localCover && !value.startsWith('/') && uri?.hasScheme == false
          || ['http', 'https'].contains(uri?.scheme) && uri!.host.isNotEmpty) ? value : '';
    } on FormatException { return ''; }
  }

  Future<void> _previewImage(BuildContext context, String imageUrl, String code, List<({String url, String code})> images) {
    var index = images.indexWhere((image) => image.url == imageUrl && image.code == code);
    if (index < 0) {
      images = [(url: imageUrl, code: code)];
      index = 0;
    }
    return showDialog<void>(context: context, builder: (context) => StatefulBuilder(builder: (context, setState) {
      void move(int delta) {
        final next = index + delta;
        if (next >= 0 && next < images.length) setState(() => index = next);
      }
      final image = images[index];
      return CallbackShortcuts(bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => move(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => move(1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => Navigator.pop(context),
      }, child: Focus(autofocus: true, child: Dialog(
        backgroundColor: AppColor.panel,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(width: 960, height: MediaQuery.sizeOf(context).height * .8,
          child: Column(children: [
            Padding(padding: const EdgeInsets.only(left: 16, right: 4), child: Row(children: [
              Expanded(child: Tooltip(message: 'Copy code'.tr, child: TextButton(
                onPressed: () => _copy(context, image.code),
                style: TextButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: AppColor.text),
                child: Text(image.code, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ))),
              Text('${index + 1} / ${images.length}', style: TextStyle(fontSize: 11, color: AppColor.muted)),
              IconButton(tooltip: 'Previous image (←)'.tr, onPressed: index > 0 ? () => move(-1) : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 20)),
              IconButton(tooltip: 'Next image (→)'.tr, onPressed: index + 1 < images.length ? () => move(1) : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 20)),
              IconButton(tooltip: 'Close preview'.tr, onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 20)),
            ])),
            Expanded(child: LayoutBuilder(builder: (context, constraints) => InteractiveViewer(
              key: ValueKey(index), minScale: 1, maxScale: 5,
              child: ExThumbnail(imageUrl: image.url, videoCode: image.code,
                width: constraints.maxWidth, height: constraints.maxHeight,
                fitUrl: BoxFit.contain, backdropColor: Colors.black),
            ))),
            Padding(padding: const EdgeInsets.all(8), child: Text('← Previous · → Next · ↓ Close'.tr,
              style: TextStyle(fontSize: 11, color: AppColor.muted))),
          ]),
        ),
      )));
    }));
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied to clipboard'.tr), duration: Duration(seconds: 2)));
    }
  }

  Widget _composer() {
    return Obx(() {
      final matches = controller.matchingCommands;
      final editing = controller.editingMessageId.value != null;
      final selected = controller.commandIndex.value.clamp(0, matches.isEmpty ? 0 : matches.length - 1);
      return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColor.panel,
        border: Border.all(color: AppColor.border),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (controller.commandNotice.value.isNotEmpty) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 130),
              child: SingleChildScrollView(child: SelectableText(controller.commandNotice.value.tr,
                style: TextStyle(fontSize: 11, height: 1.6, color: AppColor.muted))))),
            IconButton(tooltip: 'Dismiss command result'.tr, visualDensity: VisualDensity.compact,
              onPressed: () => controller.commandNotice.value = '', icon: const Icon(Icons.close_rounded, size: 14)),
          ]),
        ),
        if (matches.isNotEmpty) ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(child: Column(children: [
            for (var index = 0; index < matches.length; index++) Semantics(
              selected: index == selected,
              child: Material(
                color: index == selected ? AppColor.border : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    controller.usePrompt(matches[index]);
                    controller.send();
                  },
                  child: SizedBox(height: 34, child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(children: [
                      SizedBox(width: 88, child: Text(matches[index], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                      Expanded(child: Text(PageChatController.commands[matches[index]]!.tr, maxLines: 1,
                        overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: AppColor.muted))),
                      if (index == selected) const Icon(Icons.keyboard_return_rounded, size: 14),
                    ]),
                  )),
                ),
              ),
            ),
          ])),
        ),
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): controller.submitInput,
            if (matches.isNotEmpty) ...{
              const SingleActivator(LogicalKeyboardKey.arrowDown): () => controller.moveCommand(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () => controller.moveCommand(-1),
              const SingleActivator(LogicalKeyboardKey.tab): controller.completeCommand,
              const SingleActivator(LogicalKeyboardKey.escape): () => controller.commandQuery.value = '',
            },
          },
          child: CupertinoTextField(
            controller: controller.input,
            focusNode: controller.focusNode,
            readOnly: controller.busy.value || !controller.ready.value,
            minLines: 1,
            maxLines: 6,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(),
            style: TextStyle(fontSize: 14, height: 1.5, color: AppColor.text),
            placeholder: 'Ask anything...'.tr,
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text('Enter to send · Shift + Enter newline · / commands'.tr, style: TextStyle(fontSize: 10, color: AppColor.muted))),
          Obx(() => controller.respondingChatId.value != null
            ? IconButton.filled(tooltip: 'Stop response'.tr, onPressed: controller.stopResponse,
                icon: const Icon(Icons.stop_rounded, size: 20))
            : ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller.input,
              builder: (context, value, _) => IconButton.filled(
                tooltip: 'Send message'.tr,
                onPressed: editing || value.text.trim().isEmpty || controller.busy.value || !controller.ready.value ? null : controller.submitInput,
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
              ),
            )),
        ]),
      ]),
    );
    });
  }

  Future<void> _editChat(BuildContext context, ChatConversation chat, {required bool deleting}) async {
    var title = chat.title;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => CupertinoAlertDialog(
      title: Text(deleting ? 'Delete chat?'.tr : 'Rename chat'.tr, style: const TextStyle(fontSize: 14)),
      content: deleting
        ? Text('This conversation and its draft will be deleted. This cannot be undone.'.tr, style: TextStyle(fontSize: 12))
        : CupertinoTextFormFieldRow(
            padding: const EdgeInsets.only(top: 12),
            style: TextStyle(fontSize: 12, color: AppColor.text),
            initialValue: title,
            autofocus: true,
            maxLength: 100,
            placeholder: 'Chat title'.tr,
            onChanged: (value) => title = value,
            validator: (value) => value == null || value.trim().isEmpty ? 'Enter a title'.tr : null,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onFieldSubmitted: (_) {
              if (title.trim().isNotEmpty) Navigator.pop(context, true);
            },
          ),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(context, false), child: Text('Cancel'.tr, style: TextStyle(fontSize: 13))),
        CupertinoDialogAction(isDestructiveAction: deleting, onPressed: () {
          if (deleting || title.trim().isNotEmpty) Navigator.pop(context, true);
        }, child: Text(deleting ? 'Delete'.tr : 'Save'.tr, style: const TextStyle(fontSize: 13))),
      ],
    ));
    if (confirmed != true) return;
    if (deleting) {
      await controller.deleteChat(chat);
    } else {
      await controller.renameChat(chat, title);
    }
  }

  Future<void> _deleteAllChats(BuildContext context) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => CupertinoAlertDialog(
      title: Text('Delete all chats?'.tr, style: TextStyle(fontSize: 14)),
      content: Text('All conversations, messages, and drafts will be deleted. This cannot be undone.'.tr, style: TextStyle(fontSize: 12)),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(context, false), child: Text('Cancel'.tr, style: TextStyle(fontSize: 13))),
        CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: Text('Delete all'.tr, style: TextStyle(fontSize: 13))),
      ],
    ));
    if (confirmed == true) await controller.deleteAllChats();
  }
}

class _ChatActivityPanel extends StatefulWidget {
  const _ChatActivityPanel({super.key, required this.steps, required this.active, required this.status, required this.elapsedMs});
  final List<String> steps;
  final bool active;
  final String status;
  final int elapsedMs;

  @override
  State<_ChatActivityPanel> createState() => _ChatActivityPanelState();
}

class _ChatActivityPanelState extends State<_ChatActivityPanel> {
  late bool expanded = widget.active;

  @override
  void didUpdateWidget(covariant _ChatActivityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) expanded = widget.active;
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.active ? (widget.status == 'pending' ? 'Thinking...'.tr : 'Responding...'.tr)
        : widget.status == 'completed' ? 'Activity · @{toStringAsFixed}s'.trNamed({'toStringAsFixed': '${(widget.elapsedMs / 1000).toStringAsFixed(1)}'}) : 'Activity · interrupted'.tr;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(border: Border.all(color: AppColor.border), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Semantics(expanded: expanded, child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => expanded = !expanded),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.active) const CupertinoActivityIndicator(radius: 6)
            else Icon(widget.status == 'completed' ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded, size: 14, color: AppColor.muted),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 12, color: AppColor.muted)),
            const SizedBox(width: 12),
            Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 17, color: AppColor.muted),
          ])),
        )),
        if (expanded) Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final step in widget.steps.isEmpty ? ['Preparing your request'.tr] : widget.steps)
              Padding(padding: const EdgeInsets.only(bottom: 5), child: Text('• ${step.tr}', style: TextStyle(fontSize: 12, height: 1.4, color: AppColor.muted))),
          ]),
        ),
      ]),
    );
  }
}

class _ChatTable extends StatefulWidget {
  const _ChatTable({required this.table, this.databasePaged = false});
  final Table table;
  final bool databasePaged;

  @override
  State<_ChatTable> createState() => _ChatTableState();
}

class _ChatTableState extends State<_ChatTable> {
  int page = 0;

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final count = table.children.length - 1;
    final pages = (count / 25).ceil();
    final current = page.clamp(0, pages - 1);
    final start = current * 25;
    final end = (start + 25).clamp(0, count);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(key: ValueKey(current),
          scrollDirection: Axis.horizontal,
          child: Table(
            columnWidths: table.columnWidths, defaultColumnWidth: table.defaultColumnWidth,
            textDirection: table.textDirection, border: table.border,
            defaultVerticalAlignment: table.defaultVerticalAlignment, textBaseline: table.textBaseline,
            children: [table.children.first, ...table.children.skip(start + 1).take(end - start)],
          ),
      ),
      if (!widget.databasePaged) Row(mainAxisSize: MainAxisSize.min, children: [
        Text('@{start}–@{end} of @{count} · Page @{current}/@{pages}'.trNamed({'start': '${start + 1}', 'end': '$end', 'count': '$count', 'current': '${current + 1}', 'pages': '$pages'}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
        IconButton(tooltip: 'Previous results'.tr, visualDensity: VisualDensity.compact,
          onPressed: current == 0 ? null : () => setState(() => page = current - 1),
          icon: const Icon(Icons.chevron_left_rounded, size: 18)),
        IconButton(tooltip: 'Next results'.tr, visualDensity: VisualDensity.compact,
          onPressed: current == pages - 1 ? null : () => setState(() => page = current + 1),
          icon: const Icon(Icons.chevron_right_rounded, size: 18)),
      ]),
    ]);
  }
}
