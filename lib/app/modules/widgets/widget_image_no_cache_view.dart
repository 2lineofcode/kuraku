// ignore_for_file: depend_on_referenced_packages

import 'dart:typed_data';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/app_color.dart';

class ExImageNoCacheView extends StatelessWidget {
  const ExImageNoCacheView({
    required this.url,
    super.key,
    this.headers,
    this.height,
    this.width,
    this.size,
    this.borderColor,
    this.borderWidth,
    this.radius = 8,
    this.boxFit = BoxFit.cover,
    this.errorBuilder,
  });

  final String url;
  final Map<String, String>? headers;
  final double? height;
  final double? width;
  final double? size;
  final Color? borderColor;
  final double? borderWidth;
  final double radius;
  final BoxFit boxFit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  Future<Uint8List> getImageBytes() async {
    final response = await http.get(Uri.parse(url), headers: headers);
    return response.bodyBytes;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: getImageBytes(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Container(
            decoration: ExDecorator.box(borderRadius: radius, borderColor: borderColor, borderWidth: borderWidth),
            child: Image.memory(
              snapshot.data!,
              fit: boxFit,
              height: size ?? height,
              width: size ?? width,
              errorBuilder: errorBuilder,
            ).cornerRadius(radius),
          );
        }
        return SizedBox(
          width: size ?? width,
          height: size ?? height,
          child: Container(color: AppColor.neutral),
        ).shimmer(primaryColor: Vx.neutral600, secondaryColor: Vx.neutral700).cornerRadius(radius);
      },
    );
  }
}
