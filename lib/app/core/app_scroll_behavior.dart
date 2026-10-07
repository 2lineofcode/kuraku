import 'package:flutter/material.dart';

final appScrollBehavior = const MaterialScrollBehavior().copyWith(
  physics: const ClampingScrollPhysics(),
  overscroll: false,
);
