import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';

import '../modules/widgets/widget_controls.dart';
import '../modules/widgets/widget_surfaces.dart';
import 'app_pref.dart';
import 'app_scroll_behavior.dart';
import 'app_shortcut.dart';
import 'app_translations.dart';

class AppPinGate extends StatefulWidget {
  const AppPinGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppPinGate> createState() => _AppPinGateState();
}

class _AppPinGateState extends State<AppPinGate> {
  late bool _unlocked;
  bool _dialogOpen = false;
  int _counter = 0;

  @override
  void initState() {
    super.initState();
    _unlocked = !AppPref.getAppPinEnabled();
    Get.addTranslations(AppTranslations().keys);
    Get.locale = Locale(AppPref.getAppLanguage());
    Get.fallbackLocale = AppTranslations.fallbackLocale;
  }

  Future<void> _showPin(BuildContext context) async {
    if (_dialogOpen || _unlocked) return;
    _dialogOpen = true;
    try {
      final unlocked = await showAdaptiveDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AppPinForm(
          unlock: true,
          onSuccess: () => Navigator.of(context).pop(true),
        ),
      );
      if (unlocked == true && mounted) setState(() => _unlocked = true);
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return MaterialApp(
      scrollBehavior: appScrollBehavior,
      debugShowCheckedModeBanner: false,
      locale: Get.locale,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: AppTranslations.languages.keys.map((code) => Locale(code)).toList(),
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: Builder(builder: (context) => CallbackShortcuts(
        bindings: {const AppShortcut(LogicalKeyboardKey.keyX, alt: true): () => _showPin(context)},
        child: Focus(autofocus: true, child: Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            title: const Text('Flutter Demo Home Page'),
          ),
          body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('You have pushed the button this many times:'),
            Text('$_counter', style: Theme.of(context).textTheme.headlineMedium),
          ])),
          floatingActionButton: FloatingActionButton(
            onPressed: () => setState(() => _counter++),
            tooltip: 'Increment',
            child: const Icon(Icons.add),
          ),
        )),
      )),
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
      placeholder: label,
      onSubmitted: last ? (_) => _submit() : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final title = Text(widget.unlock ? 'Unlock'.tr : widget.disable ? 'Disable PIN lock'.tr
        : _needsCurrent ? 'Change PIN'.tr : 'Set PIN'.tr);
    final content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
    ]);
    return CallbackShortcuts(
      bindings: {
        if (widget.unlock) const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_busy) Navigator.of(context).pop(false);
        },
      },
      child: PopScope(
        canPop: !_busy,
        child: AppConfirmDialog(
          title: title,
          content: content,
          actions: [
            AppDialogAction(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text('Cancel'.tr),
            ),
            AppDialogAction(
              isDefaultAction: true,
              isDestructiveAction: widget.disable,
              onPressed: _busy ? null : _submit,
              child: Text(widget.unlock ? 'Unlock'.tr : widget.disable ? 'Disable'.tr : 'Save'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
