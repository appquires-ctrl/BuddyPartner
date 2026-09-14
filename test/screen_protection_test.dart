import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/screen_protection_service.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> channelCalls = [];

  setUp(() {
    channelCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('screen_protector'),
      (MethodCall methodCall) async {
        channelCalls.add(methodCall.method);
        return true;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('screen_protector'),
      null,
    );
  });

  group('ScreenProtectionService Dynamic Toggling Tests', () {
    test('Initial call protection is inactive', () async {
      await ScreenProtectionService.disableCallProtection();
      expect(ScreenProtectionService.isCallProtectionActive, isFalse);
    });

    test('enableCallProtection sets flag and invokes preventScreenshotOn', () async {
      await ScreenProtectionService.disableCallProtection();
      channelCalls.clear();

      await ScreenProtectionService.enableCallProtection();
      expect(ScreenProtectionService.isCallProtectionActive, isTrue);
      expect(channelCalls, contains('preventScreenshotOn'));
    });

    test('disableCallProtection clears flag and invokes preventScreenshotOff', () async {
      await ScreenProtectionService.enableCallProtection();
      channelCalls.clear();

      await ScreenProtectionService.disableCallProtection();
      expect(ScreenProtectionService.isCallProtectionActive, isFalse);
      expect(channelCalls, contains('preventScreenshotOff'));
    });

    test('Idempotent calls do not duplicate preventScreenshotOn', () async {
      await ScreenProtectionService.enableCallProtection();
      channelCalls.clear();

      await ScreenProtectionService.enableCallProtection();
      expect(channelCalls, isEmpty);
      expect(ScreenProtectionService.isCallProtectionActive, isTrue);
    });

    test('Call protection reacts to MatchmakingState transitions', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await ScreenProtectionService.disableCallProtection();
      channelCalls.clear();

      // Read service to trigger init
      final service = container.read(screenProtectionServiceProvider);
      expect(service, isNotNull);

      // Verify that idle phase keeps protection off
      expect(ScreenProtectionService.isCallProtectionActive, isFalse);

      // Simulate entering inCall phase
      final mmNotifier = container.read(matchmakingControllerProvider.notifier);
      mmNotifier.state = const MatchmakingState(phase: MatchmakingPhase.inCall);

      // Protection should be enabled
      expect(ScreenProtectionService.isCallProtectionActive, isTrue);

      // Simulate minimizing call - protection should turn off so user can screenshot UI
      mmNotifier.state = const MatchmakingState(phase: MatchmakingPhase.inCall, isCallMinimized: true);
      expect(ScreenProtectionService.isCallProtectionActive, isFalse);

      // Simulate restoring call - protection should turn back on
      mmNotifier.state = const MatchmakingState(phase: MatchmakingPhase.inCall, isCallMinimized: false);
      expect(ScreenProtectionService.isCallProtectionActive, isTrue);

      // Simulate call ending - protection should turn off
      mmNotifier.state = const MatchmakingState(phase: MatchmakingPhase.ended);
      expect(ScreenProtectionService.isCallProtectionActive, isFalse);
    });

    test('Call protection reacts to InstantConnectState transitions', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await ScreenProtectionService.disableCallProtection();

      container.read(screenProtectionServiceProvider);

      final instantNotifier = container.read(instantConnectControllerProvider.notifier);
      instantNotifier.state = const InstantConnectState(phase: InstantPhase.inCall);

      expect(ScreenProtectionService.isCallProtectionActive, isTrue);

      instantNotifier.state = const InstantConnectState(phase: InstantPhase.ended);
      expect(ScreenProtectionService.isCallProtectionActive, isFalse);
    });
  });
}
