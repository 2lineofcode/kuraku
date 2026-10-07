import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';

import '../modules/widgets/widget_controls.dart';
import '../modules/widgets/widget_style.dart';
import 'app_pref.dart';
import 'app_translations.dart';

class AppPinGate extends StatefulWidget {
  const AppPinGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppPinGate> createState() => _AppPinGateState();
}

class _AppPinGateState extends State<AppPinGate> {
  late bool _unlocked;

  @override
  void initState() {
    super.initState();
    _unlocked = !AppPref.getAppPinEnabled();
    Get.addTranslations(AppTranslations().keys);
    Get.locale = Locale(AppPref.getAppLanguage());
    Get.fallbackLocale = AppTranslations.fallbackLocale;
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Get.locale,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: AppTranslations.languages.keys.map((code) => Locale(code)).toList(),
      themeMode: AppPref.getAppTheme().resolve(),
      theme: AppStyle.theme(Brightness.light),
      darkTheme: AppStyle.theme(Brightness.dark),
      home: Scaffold(body: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SizedBox(width: 320, child: AppPinForm(
          unlock: true,
          onSuccess: () => setState(() => _unlocked = true),
        )),
      ))),
    );
  }
}

class AppPinForm extends StatefulWidget {
  const AppPinForm({super.key, this.unlock = false, this.disable = false, required this.onSuccess});

  final bool unlock;
  final bool disable;
  final VoidCallback onSuccess;

  @override
  State<AppPinForm> createState() => _AppPinFormState();
}

class _AppPinFormState extends State<AppPinForm> {
  final _current = TextEditingController();
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _needsCurrent => widget.unlock || AppPref.getAppPinEnabled();
  bool get _needsNew => !widget.unlock && !widget.disable;

  @override
  void dispose() {
    _current.dispose();
    _pin.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_needsNew && !AppPref.isValidAppPin(_pin.text)) {
      setState(() => _error = 'Use 4–8 digits for your PIN.'.tr);
      return;
    }
    if (_needsNew && _pin.text != _confirmation.text) {
      setState(() => _error = 'PINs do not match.'.tr);
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final accepted = widget.unlock
          ? await AppPref.verifyAppPin(_current.text)
          : await AppPref.setAppPin(widget.disable ? null : _pin.text, currentPin: _current.text);
      if (!mounted) return;
      if (accepted) {
        widget.onSuccess();
      } else {
        setState(() => _error = AppPref.appPinCoolingDown
            ? 'Too many attempts. Please wait 30 seconds.'.tr : 'Incorrect PIN.'.tr);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not verify or save PIN. Please retry.'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String label, TextEditingController controller, {bool autofocus = false, bool last = false}) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: AppTextField(
      controller: controller,
      autofocus: autofocus,
      enabled: !_busy,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.number,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      onSubmitted: last ? (_) => _submit() : null,
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.unlock ? 'Unlock JavIt'.tr : widget.disable ? 'Disable PIN lock'.tr
          : _needsCurrent ? 'Change PIN'.tr : 'Set PIN'.tr, style: Theme.of(context).textTheme.titleMedium),
      if (widget.unlock) Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('Enter your PIN to continue.'.tr),
      ),
      if (_needsCurrent) _field(widget.unlock ? 'PIN'.tr : 'Current PIN'.tr, _current, autofocus: true, last: !_needsNew),
      if (_needsNew) ...[
        _field('New PIN (4–8 digits)'.tr, _pin, autofocus: !_needsCurrent),
        _field('Confirm PIN'.tr, _confirmation, last: true),
      ],
      if (_error != null) Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
      const SizedBox(height: 16),
      AppButton(variant: AppButtonVariant.filled,
        onPressed: _busy ? null : _submit,
        child: Text(widget.unlock ? 'Unlock'.tr : widget.disable ? 'Disable'.tr : 'Save'.tr),
      ),
      if (!widget.unlock) AppButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: Text('Cancel'.tr),
      ),
    ]),
  );
}
