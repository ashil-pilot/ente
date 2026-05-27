import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";

class EntePopupMenuItem<T> extends PopupMenuItem<T> {
  final String label;
  final IconData? icon;
  final List<List<dynamic>>? hugeIcon;
  final Widget? iconWidget;
  final Color? iconColor;
  final Color? labelColor;

  EntePopupMenuItem(
    this.label, {
    required T super.value,
    this.icon,
    this.hugeIcon,
    this.iconWidget,
    this.iconColor,
    this.labelColor,
    super.key,
  }) : assert(
         icon != null || hugeIcon != null || iconWidget != null,
         'Either icon, hugeIcon or iconWidget must be provided.',
       ),
       assert(
         [icon, hugeIcon, iconWidget].where((item) => item != null).length == 1,
         'Only one of icon, hugeIcon or iconWidget can be provided.',
       ),
       super(
         child: Row(
           children: [
             if (iconWidget != null)
               iconWidget
             else if (hugeIcon != null)
               HugeIcon(icon: hugeIcon, color: iconColor)
             else if (icon != null)
               Icon(icon, color: iconColor),
             const Padding(padding: EdgeInsets.all(8)),
             Text(label, style: TextStyle(color: labelColor)),
           ],
         ), // Initially empty, will be populated in build
       );
}
