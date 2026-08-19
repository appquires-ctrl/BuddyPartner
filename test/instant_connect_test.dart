import 'package:flutter_test/flutter_test.dart';
import 'package:buddypartner/features/call/domain/models/instant_connect_models.dart';

void main() {
  group('Instant Connect Domain Model Tests', () {
    test('InstantCallSession parses JSON correctly', () {
      final json = {
        'id': 'session_123',
        'male_user_id': 'male_1',
        'female_user_id': 'female_1',
        'bid_amount': 50,
        'status': 'in_call',
        'agora_channel_name': 'instant_chan_1',
        'started_at': '2026-08-19T10:00:00.000Z',
        'duration_seconds': 620,
        'scratch_card_unlocked': true,
      };

      final session = InstantCallSession.fromJson(json);
      expect(session.id, 'session_123');
      expect(session.maleUserId, 'male_1');
      expect(session.femaleUserId, 'female_1');
      expect(session.bidAmount, 50);
      expect(session.status, 'in_call');
      expect(session.agoraChannelName, 'instant_chan_1');
      expect(session.durationSeconds, 620);
      expect(session.scratchCardUnlocked, true);
    });

    test('ScratchCardModel parses JSON correctly', () {
      final json = {
        'id': 'card_abc',
        'sessionId': 'session_123',
        'coinReward': 25,
        'isScratched': false,
        'createdAt': '2026-08-19T10:10:00.000Z',
      };

      final card = ScratchCardModel.fromJson(json);
      expect(card.id, 'card_abc');
      expect(card.sessionId, 'session_123');
      expect(card.coinReward, 25);
      expect(card.isScratched, false);
      expect(card.scratchedAt, isNull);
    });

    test('FemaleInstantStatus parses and copies correctly', () {
      final json = {
        'incomingPaidCallsEnabled': true,
        'isSubscribed': true,
        'unscratchedCount': 3,
        'pendingCoins': 45,
        'totalScratchedCoins': 120,
        'totalScratchedCards': 5,
      };

      final status = FemaleInstantStatus.fromJson(json);
      expect(status.incomingPaidCallsEnabled, true);
      expect(status.isSubscribed, true);
      expect(status.unscratchedCount, 3);
      expect(status.pendingCoins, 45);
      expect(status.totalScratchedCoins, 120);
      expect(status.totalScratchedCards, 5);

      final toggledOff = status.copyWith(incomingPaidCallsEnabled: false);
      expect(toggledOff.incomingPaidCallsEnabled, false);
      expect(toggledOff.unscratchedCount, 3);
    });

    test('IncomingPaidCallRequest parses payload correctly', () {
      final json = {
        'callRequestId': 'req_999',
        'agoraChannelName': 'instant_chan_999',
        'agoraToken': 'token_xyz',
        'agoraUid': 12345,
        'timeoutSeconds': 7,
      };

      final req = IncomingPaidCallRequest.fromJson(json);
      expect(req.callRequestId, 'req_999');
      expect(req.agoraChannelName, 'instant_chan_999');
      expect(req.agoraToken, 'token_xyz');
      expect(req.agoraUid, 12345);
      expect(req.timeoutSeconds, 7);
    });
  });
}
