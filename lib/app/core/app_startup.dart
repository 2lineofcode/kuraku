import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../modules/widgets/widget_dependency_guide.dart';
import '../modules/widgets/widget_style.dart';
import 'app_dependencies.dart';
import 'app_logging.dart';
import 'app_scroll_behavior.dart';
import 'app_translations.dart';

class AppStartup extends StatefulWidget {
  const AppStartup({super.key, required this.initialize, required this.child});

  final Future<void> Function() initialize;
  final Widget child;

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    setState(() => _error = null);
    try {
      await widget.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      AppLog.logE('Application startup failed: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    return MaterialApp(
      scrollBehavior: appScrollBehavior,
      debugShowCheckedModeBanner: false,
      theme: AppStyle.theme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _error == null
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Opening KuraKu, Please wait...'.tr),
                  ])
                : _error is DependencyException
                    ? DependencyGuide(
                        issues: (_error as DependencyException).issues,
                        check: () async => [AppDependencies.shared.playback()],
                        onReady: _initialize,
                      )
                    : SelectableText('Could not start KuraKu. Please restart the app.\n\n@{error}'.trNamed({'error': '$_error'})),
          ),
        ),
      ),
    );
  }
}
