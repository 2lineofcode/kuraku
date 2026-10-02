import 'package:flutter/material.dart';

class SearchSuggestionsOverlay extends StatefulWidget {
  const SearchSuggestionsOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<SearchSuggestionsOverlay> createState() => _SearchSuggestionsOverlayState();
}

class _SearchSuggestionsOverlayState extends State<SearchSuggestionsOverlay> {
  final _overlay = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _overlay.show();
  }

  @override
  Widget build(BuildContext context) {
    // Covered routes must not retain an overlay with stale layout constraints.
    if (ModalRoute.isCurrentOf(context) == false || !TickerMode.valuesOf(context).enabled) {
      return const SizedBox(width: double.infinity);
    }
    if (!_overlay.isShowing) _overlay.show();
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlay,
      overlayChildBuilder: (context, info) {
        final anchor = MatrixUtils.transformRect(info.childPaintTransform, Offset.zero & info.childSize);
        return Positioned(
          left: anchor.left,
          top: anchor.bottom,
          width: anchor.width,
          child: TextFieldTapRegion(child: widget.child),
        );
      },
      child: const SizedBox(width: double.infinity),
    );
  }
}
