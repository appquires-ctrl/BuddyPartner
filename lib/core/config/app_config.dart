/// Centralized app configuration for backend URLs and Agora settings.
/// Values are read from compile-time environment variables (--dart-define).
class AppConfig {
  AppConfig._();

  /// Backend server URL (Socket.io + REST).
  /// Pass via: --dart-define=BACKEND_URL=http://your-server:3000
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://buddypartner.onrender.com',
  );

  /// Agora App ID (safe to embed client-side — used for RTC engine init).
  /// The App Certificate stays server-side only.
  static const String agoraAppId = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: 'c1ad9e31c3ea4fb094ce515add9fe61b',
  );

  /// Apptrove MMP SDK Key.
  /// Pass via: --dart-define=APPTROVE_SDK_KEY=your_key
  static const String apptroveSdkKey = String.fromEnvironment(
    'APPTROVE_SDK_KEY',
    defaultValue: 'cba8eac4-c835-40bd-a16f-2cf6a21470eb',
  );

  /// Apptrove Environment ('development', 'production', or 'testing').
  /// Pass via: --dart-define=APPTROVE_ENV=development
  static const String apptroveEnv = String.fromEnvironment(
    'APPTROVE_ENV',
    defaultValue: '',
  );
}

