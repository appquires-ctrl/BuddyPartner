import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class CallkitService {
  static CallkitService? _instance;
  static CallkitService get instance => _instance ??= CallkitService._();
  CallkitService._();

  /// Show the incoming call UI on screen (lock screen & heads up notification)
  static Future<void> showIncomingCall({
    required String callRequestId,
    required String callerId,
    required String callerName,
    String? callerAvatar,
  }) async {
    try {
      final params = CallKitParams(
        id: callRequestId,
        nameCaller: callerName,
        appName: 'BuddyPartner',
        avatar: callerAvatar,
        handle: 'Voice Call',
        type: 0, // 0 for audio call
        duration: 30000,
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: false,
          subtitle: 'Missed Call',
          callbackText: 'Call back',
        ),
        extra: <String, dynamic>{
          'callRequestId': callRequestId,
          'callerId': callerId,
          'callerName': callerName,
        },
        android: const AndroidParams(
          isCustomNotification: false,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0F0C22',
          actionColor: '#6B4EFF',
          textColor: '#FFFFFF',
          incomingCallNotificationChannelName: 'Incoming Calls',
          missedCallNotificationChannelName: 'Missed Calls',
          isShowCallID: false,
          textAccept: 'Accept',
          textDecline: 'Decline',
        ),
        ios: const IOSParams(
          iconName: 'AppIcon',
          handleType: 'generic',
          supportsVideo: false,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'voiceChat',
          audioSessionActive: true,
          ringtonePath: 'system_ringtone_default',
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(params);
      debugPrint('📲 [CallKit] Incoming call presented: $callRequestId ($callerName)');
    } catch (e) {
      debugPrint('❌ [CallKit] Error showing incoming call: $e');
    }
  }

  /// Initialize listener for user actions (Accept, Decline, Timeout)
  static void initializeListeners({
    required Function(String callRequestId, String callerId, String callerName) onAccept,
    required Function(String callRequestId) onDecline,
  }) {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;
      debugPrint('📲 [CallKit Event] ${event.eventName}');

      if (event is CallEventActionCallAccept) {
        final params = event.callKitParams;
        final callRequestId = params.id;
        final extra = params.extra ?? {};
        final callerId = (extra['callerId'] ?? '').toString();
        final callerName = (params.nameCaller ?? extra['callerName'] ?? 'User').toString();
        debugPrint('✅ [CallKit] User accepted call $callRequestId');
        onAccept(callRequestId, callerId, callerName);
      } else if (event is CallEventActionCallDecline) {
        final params = event.callKitParams;
        debugPrint('❌ [CallKit] User declined call ${params.id}');
        onDecline(params.id);
      } else if (event is CallEventActionCallEnded) {
        debugPrint('📲 [CallKit] Call ended: ${event.callKitParams.id}');
      } else if (event is CallEventActionCallTimeout) {
        debugPrint('⏱️ [CallKit] Call timed out: ${event.id}');
      }
    });
  }

  /// Dismiss all ringing calls
  static Future<void> endAllCalls() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
      debugPrint('📲 [CallKit] Dismissed all calls');
    } catch (e) {
      debugPrint('❌ [CallKit] Error ending calls: $e');
    }
  }

  /// Dismiss a specific call
  static Future<void> endCall(String callRequestId) async {
    try {
      await FlutterCallkitIncoming.endCall(callRequestId);
      debugPrint('📲 [CallKit] Dismissed call: $callRequestId');
    } catch (e) {
      debugPrint('❌ [CallKit] Error ending call $callRequestId: $e');
    }
  }
}
