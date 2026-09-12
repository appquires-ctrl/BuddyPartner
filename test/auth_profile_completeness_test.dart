import 'package:flutter_test/flutter_test.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';

void main() {
  group('CustomUser & Auth Profile Completeness Regression Tests (B3)', () {
    final testDob = DateTime.parse('2000-05-15T00:00:00.000Z');

    final sampleBackendUserPayload = <String, dynamic>{
      'id': 'user_uuid_12345',
      'countryCode': '91',
      'mobile': '9876543210',
      'phoneNumber': '+919876543210',
      'fullName': 'Priya Sharma',
      'dob': '2000-05-15T00:00:00.000Z',
      'gender': 'Female',
      'language': 'Hindi',
      'avatarSeed': 'priya_avatar',
      'avatarStyle': 'avataaars',
      'isTelecaller': true,
      'hasClaimedIntroOffer': true,
      'country': 'India',
      'state': 'Maharashtra',
      'city': 'Mumbai',
      'latitude': 19.0760,
      'longitude': 72.8777,
      'balance': 500,
    };

    test('CustomUser.fromBackendUserMap populates the full field set without dropping any field', () {
      final user = CustomUser.fromBackendUserMap(
        sampleBackendUserPayload,
        isProfileComplete: true,
      );

      expect(user.id, equals('user_uuid_12345'));
      expect(user.phoneNumber, equals('+919876543210'));
      expect(user.isProfileComplete, isTrue);
      expect(user.fullName, equals('Priya Sharma'));
      expect(user.gender, equals('Female'));
      expect(user.isFemale, isTrue);
      expect(user.isMale, isFalse);
      expect(user.isTelecaller, isTrue);
      expect(user.isTelecallerActive, isTrue);
      expect(user.hasClaimedIntroOffer, isTrue);

      // Assert completeness of profile & location fields (B3 regression check)
      expect(user.dob, equals(testDob));
      expect(user.language, equals('Hindi'));
      expect(user.country, equals('India'));
      expect(user.state, equals('Maharashtra'));
      expect(user.city, equals('Mumbai'));
      expect(user.latitude, equals(19.0760));
      expect(user.longitude, equals(72.8777));
      expect(user.avatarSeed, equals('priya_avatar'));
      expect(user.avatarStyle, equals('avataaars'));
    });

    test('CustomUser.fromBackendUserMap respects fallbacks when fields are missing from payload', () {
      final minimalPayload = <String, dynamic>{
        'id': 'user_uuid_min',
      };

      final fallbackDob = DateTime.parse('1998-10-20T00:00:00.000Z');
      final user = CustomUser.fromBackendUserMap(
        minimalPayload,
        isProfileComplete: false,
        fallbackPhone: '+919999999999',
        fallbackFullName: 'Fallback Name',
        fallbackGender: 'Male',
        fallbackDob: fallbackDob,
        fallbackLanguage: 'English',
        fallbackAvatarSeed: 'seed_abc',
        fallbackAvatarStyle: 'bottts',
        fallbackIsTelecaller: false,
      );

      expect(user.id, equals('user_uuid_min'));
      expect(user.phoneNumber, equals('+919999999999'));
      expect(user.isProfileComplete, isFalse);
      expect(user.fullName, equals('Fallback Name'));
      expect(user.gender, equals('Male'));
      expect(user.isMale, isTrue);
      expect(user.dob, equals(fallbackDob));
      expect(user.language, equals('English'));
      expect(user.avatarSeed, equals('seed_abc'));
      expect(user.avatarStyle, equals('bottts'));
      expect(user.isTelecaller, isFalse);
      expect(user.country, isNull);
      expect(user.state, isNull);
      expect(user.city, isNull);
      expect(user.latitude, isNull);
      expect(user.longitude, isNull);
      expect(user.hasClaimedIntroOffer, isFalse);
    });

    test('CustomUser roundtrip (toJson -> fromJson) preserves full profile & location fields', () {
      final originalUser = CustomUser(
        id: 'roundtrip_user_1',
        phoneNumber: '+919123456789',
        isProfileComplete: true,
        gender: 'Female',
        fullName: 'Ananya Verma',
        avatarSeed: 'ananya_seed',
        avatarStyle: 'avataaars',
        isTelecaller: true,
        hasClaimedIntroOffer: true,
        dob: testDob,
        language: 'Bengali',
        country: 'India',
        state: 'West Bengal',
        city: 'Kolkata',
        latitude: 22.5726,
        longitude: 88.3639,
      );

      final jsonMap = originalUser.toJson();
      final reconstructedUser = CustomUser.fromJson(jsonMap);

      expect(reconstructedUser.id, equals(originalUser.id));
      expect(reconstructedUser.phoneNumber, equals(originalUser.phoneNumber));
      expect(reconstructedUser.isProfileComplete, equals(originalUser.isProfileComplete));
      expect(reconstructedUser.gender, equals(originalUser.gender));
      expect(reconstructedUser.fullName, equals(originalUser.fullName));
      expect(reconstructedUser.avatarSeed, equals(originalUser.avatarSeed));
      expect(reconstructedUser.avatarStyle, equals(originalUser.avatarStyle));
      expect(reconstructedUser.isTelecaller, equals(originalUser.isTelecaller));
      expect(reconstructedUser.hasClaimedIntroOffer, equals(originalUser.hasClaimedIntroOffer));
      expect(reconstructedUser.dob, equals(originalUser.dob));
      expect(reconstructedUser.language, equals(originalUser.language));
      expect(reconstructedUser.country, equals(originalUser.country));
      expect(reconstructedUser.state, equals(originalUser.state));
      expect(reconstructedUser.city, equals(originalUser.city));
      expect(reconstructedUser.latitude, equals(originalUser.latitude));
      expect(reconstructedUser.longitude, equals(originalUser.longitude));
    });

    test('CustomUser.copyWith preserves all existing profile fields when updating specific fields', () {
      final originalUser = CustomUser(
        id: 'user_copy_test',
        phoneNumber: '+919876500000',
        isProfileComplete: true,
        gender: 'Male',
        fullName: 'Rahul Roy',
        dob: testDob,
        language: 'Hindi',
        country: 'India',
        state: 'Delhi',
        city: 'New Delhi',
        latitude: 28.6139,
        longitude: 77.2090,
        hasClaimedIntroOffer: true,
      );

      final updatedUser = originalUser.copyWith(
        city: 'Gurugram',
        state: 'Haryana',
        latitude: 28.4595,
        longitude: 77.0266,
      );

      // Verify targeted fields changed
      expect(updatedUser.city, equals('Gurugram'));
      expect(updatedUser.state, equals('Haryana'));
      expect(updatedUser.latitude, equals(28.4595));
      expect(updatedUser.longitude, equals(77.0266));

      // Verify untargeted fields remained intact
      expect(updatedUser.id, equals(originalUser.id));
      expect(updatedUser.fullName, equals('Rahul Roy'));
      expect(updatedUser.dob, equals(testDob));
      expect(updatedUser.language, equals('Hindi'));
      expect(updatedUser.country, equals('India'));
      expect(updatedUser.hasClaimedIntroOffer, isTrue);
    });
  });
}
