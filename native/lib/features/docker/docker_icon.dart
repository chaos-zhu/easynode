import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class DockerIcon extends StatelessWidget {
  const DockerIcon({super.key, this.size, this.visualScale = 0.82});

  final double? size;
  final double visualScale;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final iconSize = size ?? iconTheme.size ?? 24;
    final imageSize = iconSize * visualScale;
    return SizedBox.square(
      dimension: iconSize,
      child: Center(
        child: SvgPicture.asset(
          'assets/docker.svg',
          width: imageSize,
          height: imageSize,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(
            iconTheme.color ?? Theme.of(context).colorScheme.onSurface,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
