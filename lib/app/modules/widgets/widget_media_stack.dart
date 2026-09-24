import 'package:flutter/material.dart';

class MediaStack extends StatelessWidget {
  const MediaStack(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: const TextStyle(color: Colors.white),
    child: IconTheme.merge(data: const IconThemeData(color: Colors.white), child: Stack(clipBehavior: Clip.none, children: children)),
  );
}
