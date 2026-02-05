import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/cmyke_chrome.dart';

class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.blurSigma,
    this.tint,
    this.border,
    this.shadows,
    this.highlight = true,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final double? blurSigma;
  final Color? tint;
  final Border? border;
  final List<BoxShadow>? shadows;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final chrome = context.chrome;
    final radius = borderRadius ?? BorderRadius.circular(chrome.radiusXL);
    final sigma = blurSigma ?? chrome.blurSigma;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint ?? chrome.frostedTint,
            border: border ?? Border.all(color: chrome.frostedBorder),
            borderRadius: radius,
            boxShadow: shadows ?? chrome.elevationShadow,
          ),
          child: Stack(
            children: [
              if (highlight)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [chrome.frostedHighlight, Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(padding: padding ?? EdgeInsets.zero, child: child),
            ],
          ),
        ),
      ),
    );
  }
}
