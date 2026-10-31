import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Cached network image with a subtle dark placeholder while loading and a
/// short fade on arrival — posters never pop in or stay blank.
/// [errorFallback] is shown when the load fails.
class GaImage extends StatelessWidget {
  const GaImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorFallback,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? errorFallback;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      fadeInDuration: const Duration(milliseconds: 250),
      fadeOutDuration: const Duration(milliseconds: 100),
      placeholder: (context, _) => Container(
        width: width,
        height: height,
        color: Colors.grey.shade900,
      ),
      errorWidget: (context, url, error) =>
          errorFallback ?? Container(color: Colors.grey.shade800),
    );
  }
}
