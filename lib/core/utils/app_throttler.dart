import 'package:flutter/foundation.dart';

/// AppThrottler prevents rapid multi-taps (button mashing) from triggering
/// duplicate API calls, duplicate navigation pushes, or duplicate transactions.
class AppThrottler {
  static final Map<String, DateTime> _actionTimestamps = {};
  static DateTime _globalLastClickTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Checks whether an action can execute or if it should be blocked due to rapid repeated clicking.
  /// [cooldownMs] defaults to 500ms.
  /// [actionId] optional key to throttle specific buttons/actions independently.
  static bool canProcess({int cooldownMs = 500, String? actionId}) {
    final now = DateTime.now();

    if (actionId != null) {
      final lastTime = _actionTimestamps[actionId];
      if (lastTime != null && now.difference(lastTime).inMilliseconds < cooldownMs) {
        return false;
      }
      _actionTimestamps[actionId] = now;
      // Clean up old action timestamps if map grows large
      if (_actionTimestamps.length > 100) {
        _actionTimestamps.removeWhere((_, time) => now.difference(time).inMilliseconds > 5000);
      }
      return true;
    }

    if (now.difference(_globalLastClickTime).inMilliseconds < cooldownMs) {
      return false;
    }
    _globalLastClickTime = now;
    return true;
  }

  /// Wraps a callback function with rapid-click throttling protection.
  static VoidCallback? wrap(VoidCallback? action, {int cooldownMs = 500, String? actionId}) {
    if (action == null) return null;
    return () {
      if (canProcess(cooldownMs: cooldownMs, actionId: actionId)) {
        action();
      }
    };
  }
}
