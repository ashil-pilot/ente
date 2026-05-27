import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/theme/ente_theme.dart";

class MapButton extends StatelessWidget {
  final String heroTag;
  final IconData? icon;
  final List<List<dynamic>>? hugeIcon;
  final VoidCallback onPressed;

  const MapButton({
    super.key,
    this.icon,
    this.hugeIcon,
    required this.onPressed,
    required this.heroTag,
  }) : assert(icon != null || hugeIcon != null);

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return FloatingActionButton(
      elevation: 2,
      heroTag: heroTag,
      highlightElevation: 3,
      backgroundColor: colorScheme.backgroundElevated,
      mini: true,
      onPressed: onPressed,
      splashColor: Colors.transparent,
      child: hugeIcon != null
          ? HugeIcon(icon: hugeIcon!, color: colorScheme.textBase)
          : Icon(icon, color: colorScheme.textBase),
    );
  }
}
