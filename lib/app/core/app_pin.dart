import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';

import '../modules/standalone_player/standalone_player_controller.dart';
import '../modules/standalone_player/standalone_player_translations.dart';
import '../modules/standalone_player/standalone_player_view.dart';
import '../modules/widgets/widget_controls.dart';
import '../modules/widgets/widget_style.dart';
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

class _AppPinGateState extends State<AppPinGate> with WindowListener {
  late bool _unlocked;
  bool _dialogOpen = false;
  bool _closing = false;
  StandalonePlayerController? _player;
  AppLifecycleListener? _lifecycle;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _unlocked = !AppPref.getAppPinEnabled();
    if (!_unlocked) {
      _player = Get.put<StandalonePlayerController>(StandalonePlayerController(), permanent: true);
      windowManager.addListener(this);
      _lifecycle = AppLifecycleListener(onExitRequested: () async {
        if (!_unlocked) {
          _closing = true;
          await _releasePlayer();
        }
        return AppExitResponse.exit;
      });
    }
    Get.addTranslations(AppTranslations().keys);
    Get.locale = Locale(AppPref.getAppLanguage());
    Get.fallbackLocale = AppTranslations.fallbackLocale;
  }

  Future<void> _showPin(BuildContext context) async {
    if (_dialogOpen || _unlocked || _closing) return;
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
      if (unlocked == true && mounted && !_closing) {
        await Overlayment.dismissAll();
        if (!mounted || _closing) return;
        await _player?.exitFullscreen();
        if (!mounted || _closing || _player?.isFullScreen.value == true) return;
        await _releasePlayer();
        if (mounted && !_closing) {
          _lifecycle?.dispose();
          _lifecycle = null;
          windowManager.removeListener(this);
          setState(() => _unlocked = true);
        }
      }
    } finally {
      _dialogOpen = false;
    }
  }

  Future<void> _releasePlayer() async {
    final player = _player;
    if (player == null) return;
    _player = null;
    if (Get.isRegistered<StandalonePlayerController>() && identical(Get.find<StandalonePlayerController>(), player)) {
      unawaited(Get.delete<StandalonePlayerController>(force: true));
    }
    await player.shutdown();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    windowManager.removeListener(this);
    unawaited(_releasePlayer());
    super.dispose();
  }

  @override
  void onWindowClose([int? windowId]) async {
    if (_unlocked || _closing) return;
    _closing = true;
    await _releasePlayer();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowEnterFullScreen([int? windowId]) => _refreshFullscreen();

  @override
  void onWindowLeaveFullScreen([int? windowId]) => _refreshFullscreen();

  void _refreshFullscreen() {
    if (_unlocked || _closing || _player == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_unlocked && !_closing && _player != null) Get.forceAppUpdate();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    final player = _player;
    if (player == null) return const ColoredBox(color: Colors.black);
    return ToastificationWrapper(child: GetMaterialApp(
      navigatorKey: _navigatorKey,
      scrollBehavior: appScrollBehavior,
      debugShowCheckedModeBanner: false,
      title: 'Player',
      translations: StandalonePlayerTranslations(),
      locale: Get.locale,
      fallbackLocale: AppTranslations.fallbackLocale,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: AppTranslations.languages.keys.map((code) => Locale(code)).toList(),
      theme: AppStyle.theme(Brightness.light),
      darkTheme: AppStyle.theme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) => CallbackShortcuts(
        bindings: {
          const AppShortcut(LogicalKeyboardKey.keyX, alt: true): () => _showPin(_navigatorKey.currentContext!),
          const AppShortcut(LogicalKeyboardKey.keyO): () => _player?.pickVideos(),
        },
        child: Focus(autofocus: true, child: StandalonePlayerDropTarget(controller: player, child: child!)),
      ),
      home: StandalonePlayerView(controller: player),
    ));
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
