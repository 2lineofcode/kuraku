import 'dart:async';
import 'package:flutter/material.dart';

class DoubleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSingleTap;
  final VoidCallback? onDoubleTap;
  final int ms;

  const DoubleTap({
    super.key,
    required this.child,
    this.onSingleTap,
    this.onDoubleTap,
    this.ms = 160,
  });

  @override
  State<DoubleTap> createState() => _DoubleTapState();
}

class _DoubleTapState extends State<DoubleTap> {
  Timer? _timer;

  void _handleTap() {
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
      if (widget.onDoubleTap != null) widget.onDoubleTap!();
    } else {
      _timer = Timer(Duration(milliseconds: widget.ms), () {
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
    return InkWell(
      onTap: _handleTap,
      child: widget.child,
    );
  }
}
