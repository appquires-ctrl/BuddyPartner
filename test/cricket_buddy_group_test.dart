import 'package:flutter_test/flutter_test.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';

void main() {
  group('Cricket Buddy 11-Member Group Unit Tests', () {
    test('BuddyType.cricket is properly marked as a multi-user group activity with 11 max members', () {
      final cricket = BuddyType.cricket;
      expect(cricket.isGroup, isTrue);
      expect(cricket.maxGroupMembers, equals(11));
      expect(cricket.coinCost, equals(199));
      expect(cricket.title, equals('Cricket Buddy'));
      expect(cricket.stickerAsset, contains('cricket_buddy.png'));

      // Verify Garba remains 6 members
      final garba = BuddyType.garba;
      expect(garba.isGroup, isTrue);
      expect(garba.maxGroupMembers, equals(6));
      expect(garba.coinCost, equals(501));

      // Verify standard 1-on-1 activities are NOT group activities
      expect(BuddyType.movie.isGroup, isFalse);
      expect(BuddyType.pizza.isGroup, isFalse);
      expect(BuddyType.coffee.isGroup, isFalse);
      expect(BuddyType.hangout.isGroup, isFalse);
      expect(BuddyType.nightOut.isGroup, isFalse);
    });

    test('BuddyGroup model parses and identifies Cricket groups with 11 capacity', () {
      final json = {
        'id': 'cricket-group-123',
        'initiator_id': 'host-uuid-456',
        'title': 'Sunday Morning Box Cricket',
        'buddy_type': 'cricket',
        'city': 'Ahmedabad',
        'target_gender': 'all',
        'host_coin_cost': 199,
        'max_members': 11,
        'member_count': 5,
        'status': 'open',
        'host_name': 'Dhruv',
        'created_at': DateTime.now().toIso8601String(),
      };

      final group = BuddyGroup.fromJson(json);

      expect(group.id, equals('cricket-group-123'));
      expect(group.isCricket, isTrue);
      expect(group.isGarba, isFalse);
      expect(group.maxMembers, equals(11));
      expect(group.memberCount, equals(5));
      expect(group.availableSlots, equals(6));
      expect(group.isFull, isFalse);
      expect(group.stickerAsset, contains('cricket_buddy.png'));
    });

    test('BuddyGroup isFull triggers accurately when 11 players join', () {
      final fullCricketGroup = BuddyGroup(
        id: 'full-cricket-group',
        initiatorId: 'host-1',
        title: 'Playing XI Cricket Match',
        buddyType: 'cricket',
        city: 'Mumbai',
        maxMembers: 11,
        memberCount: 11,
        createdAt: DateTime.now(),
      );

      expect(fullCricketGroup.isCricket, isTrue);
      expect(fullCricketGroup.maxMembers, equals(11));
      expect(fullCricketGroup.memberCount, equals(11));
      expect(fullCricketGroup.availableSlots, equals(0));
      expect(fullCricketGroup.isFull, isTrue);
    });

    test('BuddyGroup distinguishes Garba groups (6 max members) from Cricket groups (11 max members)', () {
      final garbaGroup = BuddyGroup(
        id: 'garba-group-1',
        initiatorId: 'host-2',
        title: 'Navratri Garba Squad',
        buddyType: 'garba',
        city: 'Surat',
        maxMembers: 6,
        memberCount: 6,
        createdAt: DateTime.now(),
      );

      expect(garbaGroup.isGarba, isTrue);
      expect(garbaGroup.isCricket, isFalse);
      expect(garbaGroup.maxMembers, equals(6));
      expect(garbaGroup.isFull, isTrue);
      expect(garbaGroup.stickerAsset, contains('garba_buddy.png'));
    });

    test('Clean title parser for Cricket groups formats properly', () {
      String parseTitle(String title) {
        String displayTitle = title.trim();
        if (displayTitle.toLowerCase().contains('dandiya') || displayTitle.toLowerCase().contains('garba')) {
          displayTitle = displayTitle
              .replaceAll(RegExp(r'(dandiya|garba)(\s+buddy)?(\s+group)?', caseSensitive: false), 'Dandiya')
              .trim();
          if (displayTitle.isEmpty) displayTitle = 'Dandiya';
        } else if (displayTitle.toLowerCase().contains('cricket')) {
          displayTitle = displayTitle
              .replaceAll(RegExp(r'cricket(\s+buddy)?(\s+group)?', caseSensitive: false), 'Cricket')
              .trim();
          if (displayTitle.isEmpty) displayTitle = 'Cricket';
        } else if (displayTitle.length > 9) {
          displayTitle = displayTitle.split(' ').first;
        }
        return displayTitle;
      }

      expect(parseTitle('Cricket Buddy Group'), equals('Cricket'));
      expect(parseTitle('Dandiya Buddy Group'), equals('Dandiya'));
      expect(parseTitle('Garba Buddy Group'), equals('Dandiya'));
      expect(parseTitle('Weekend Cricket Match'), equals('Weekend Cricket Match'));
      expect(parseTitle('Falguni Garba Night'), equals('Falguni Dandiya Night'));
    });

    test('Capacity error message dynamically references Cricket vs Dandiya', () {
      String getFullErrorMessage(BuddyGroup group) {
        return 'Sorry, this ${group.isCricket ? "Cricket" : "Dandiya"} group is already full (${group.maxMembers}/${group.maxMembers} members)!';
      }

      final cricketGroup = BuddyGroup(
        id: 'c1',
        initiatorId: 'h1',
        title: 'Cricket Group',
        buddyType: 'cricket',
        city: 'Delhi',
        maxMembers: 11,
        memberCount: 11,
        createdAt: DateTime.now(),
      );

      final garbaGroup = BuddyGroup(
        id: 'g1',
        initiatorId: 'h2',
        title: 'Dandiya Group',
        buddyType: 'garba',
        city: 'Ahmedabad',
        maxMembers: 6,
        memberCount: 6,
        createdAt: DateTime.now(),
      );

      expect(getFullErrorMessage(cricketGroup), equals('Sorry, this Cricket group is already full (11/11 members)!'));
      expect(getFullErrorMessage(garbaGroup), equals('Sorry, this Dandiya group is already full (6/6 members)!'));
    });
  });
}
