import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DoubleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSingleTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onCommandTap;
  final int? ms;

  const DoubleTap({
    super.key,
    required this.child,
    this.onSingleTap,
    this.onDoubleTap,
    this.onCommandTap,
    this.ms,
  });

  @override
  State<DoubleTap> createState() => _DoubleTapState();
}

class _DoubleTapState extends State<DoubleTap> {
  Timer? _timer;
  bool _commandTap = false;

  void _handleTap() {
    if (_commandTap) {
      _commandTap = false;
      _timer?.cancel();
      widget.onCommandTap?.call();
      return;
    }
    if (widget.onDoubleTap == null) {
      widget.onSingleTap?.call();
      return;
    }
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
      if (widget.onDoubleTap != null) widget.onDoubleTap!();
    } else {
      _timer = Timer(widget.ms == null ? kDoubleTapTimeout : Duration(milliseconds: widget.ms!), () {
        if (widget.onSingleTap != null) widget.onSingleTap!();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = InkWell(
      onTap: _handleTap,
      child: widget.child,
    );
    if (widget.onCommandTap == null) return child;
    return Listener(
      onPointerDown: (_) => _commandTap = HardwareKeyboard.instance.isMetaPressed,
      child: child,
    );
  }
}
