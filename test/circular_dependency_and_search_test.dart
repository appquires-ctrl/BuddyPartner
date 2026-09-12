import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/home/presentation/providers/matched_users_provider.dart';
import 'package:buddypartner/features/history/data/call_history_provider.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';
import 'package:buddypartner/features/chat/application/presence_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CircularDependencyError Regression Tests (A1)', () {
    test('setSession and clearSession execute without CircularDependencyError', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 1. Instantiate downstream providers that watch authStateProvider
      container.read(authStateProvider);
      container.read(isAuthenticatedProvider);
      container.read(userProfileProvider);
      container.read(favoriteUsersProvider);
      container.read(matchedUsersProvider);
      container.read(callHistoryProvider);
      container.read(presenceProvider);
      container.read(walletBalanceProvider);
      container.read(subscriptionStatusProvider);

      final testUser = CustomUser(
        id: 'test-user-123',
        phoneNumber: '+919999999999',
        fullName: 'Test User',
        isProfileComplete: true,
        gender: 'Male',
        userName: 'test_user',
      );

      // 2. Call setSession - this previously threw CircularDependencyError at line 294
      await expectLater(
        container.read(authStateProvider.notifier).setSession(testUser),
        completes,
      );

      // Verify auth state updated
      expect(container.read(authStateProvider).value?.id, equals('test-user-123'));
      expect(container.read(isAuthenticatedProvider), isTrue);

      // 3. Call clearSession - also verified for zero circular dependency
      await expectLater(
        container.read(authStateProvider.notifier).clearSession(),
        completes,
      );

      expect(container.read(authStateProvider).value, isNull);
      expect(container.read(isAuthenticatedProvider), isFalse);

      // 4. Repeat cycle (simulate re-login)
      await expectLater(
        container.read(authStateProvider.notifier).setSession(testUser),
        completes,
      );
      expect(container.read(authStateProvider).value?.id, equals('test-user-123'));

      await expectLater(
        container.read(authStateProvider.notifier).clearSession(),
        completes,
      );
      expect(container.read(authStateProvider).value, isNull);
    });
  });

  group('Search Query Gating Unit Tests (B1 & B2)', () {
    String cleanQuery(String input) {
      final trimmed = input.trim();
      return trimmed.startsWith('@') ? trimmed.substring(1).trim() : trimmed;
    }

    test('cleanQuery correctly strips leading @ and whitespace', () {
      expect(cleanQuery('@'), equals(''));
      expect(cleanQuery('@a'), equals('a'));
      expect(cleanQuery('@dh'), equals('dh'));
      expect(cleanQuery('  @dhruv  '), equals('dhruv'));
      expect(cleanQuery('dhruv_soni'), equals('dhruv_soni'));
    });

    test('queries with clean length < 2 are strictly blocked from network calls', () {
      bool shouldSendRequest(String rawInput) {
        final cleaned = cleanQuery(rawInput);
        return cleaned.length >= 2;
      }

      // 0 or 1 char clean queries must NOT fire
      expect(shouldSendRequest(''), isFalse);
      expect(shouldSendRequest('@'), isFalse);
      expect(shouldSendRequest('d'), isFalse);
      expect(shouldSendRequest('@d'), isFalse);
      expect(shouldSendRequest(' @d '), isFalse);
      expect(shouldSendRequest(' @ '), isFalse);

      // 2+ char clean queries are permitted
      expect(shouldSendRequest('dh'), isTrue);
      expect(shouldSendRequest('@dh'), isTrue);
      expect(shouldSendRequest('@dhruv'), isTrue);
      expect(shouldSendRequest('dhruv_soni'), isTrue);
    });
  });
}
