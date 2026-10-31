import 'dart:io';

import 'package:flutter/services.dart';

/// Shows or hides Android's on-screen navigation bar; the status bar is not
/// affected. While hidden, a swipe from the bottom edge reveals it briefly.
abstract final class SystemNavigation {
  static const _channel = MethodChannel('streak/app_icon');

  static Future<void> setHidden(bool hidden) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setNavigationHidden', {
        'hidden': hidden,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
