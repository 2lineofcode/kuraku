import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/app_pref.dart';
import '../../../utils/chat_service.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_surfaces.dart';

class PageChatSettingsDialog extends StatefulWidget {
  const PageChatSettingsDialog({super.key});

  @override
  State<PageChatSettingsDialog> createState() => _PageChatSettingsDialogState();
}

class _PageChatSettingsDialogState extends State<PageChatSettingsDialog> {
  final fields = AppPref.getAiSettings().map((key, value) => MapEntry(key, TextEditingController(text: value)));
  bool saving = false;
  String? error;

  @override
  void dispose() {
    for (final field in fields.values) field.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final values = fields.map((key, field) => MapEntry(key, field.text.trim()));
    final api = ChatService(apiKey: values['apiKey'], provider: values['provider'], baseUrl: values['baseUrl'], model: values['model']);
    final invalid = api.configurationError;
    api.close();
    if (invalid != null) {
      setState(() => error = invalid);
      return;
    }
    setState(() { saving = true; error = null; });
    try {
      await AppPref.setAiSettings(values);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() { saving = false; error = 'Could not save AI settings. Please retry.'; });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: !saving, child: AppDialog(
    maxWidth: 440,
    title: Text('AI settings'.tr),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final field in const {'provider': 'Provider', 'baseUrl': 'Base URL', 'model': 'Model', 'apiKey': 'API key'}.entries)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: AppTextField(
          controller: fields[field.key],
          decoration: InputDecoration(labelText: field.value.tr),
          enabled: !saving,
          obscureText: field.key == 'apiKey',
          autocorrect: false,
          enableSuggestions: false,
        )),
      if (error != null) Text(error!.tr, style: const TextStyle(fontSize: 12, color: Colors.red)),
    ]),
    actions: [
      AppButton(onPressed: saving ? null : () => Navigator.pop(context), child: Text('Cancel'.tr)),
      AppButton(variant: AppButtonVariant.outlined, onPressed: saving ? null : save, child: Text('Save'.tr)),
    ],
  ));
}
