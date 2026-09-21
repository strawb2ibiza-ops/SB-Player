import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowControls extends StatelessWidget {
  const DesktopWindowControls({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();

    final size = compact ? 18.0 : 20.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Minimize',
          visualDensity: VisualDensity.compact,
          onPressed: windowManager.minimize,
          icon: Icon(Icons.remove, size: size),
        ),
        IconButton(
          tooltip: 'Maximize / restore',
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
          icon: Icon(Icons.crop_square_rounded, size: size - 2),
        ),
        IconButton(
          tooltip: 'Close',
          visualDensity: VisualDensity.compact,
          onPressed: windowManager.close,
          icon: Icon(Icons.close, size: size),
        ),
      ],
    );
  }
}
