/// Centralized app configuration for backend URLs and Agora settings.
/// Values are read from compile-time environment variables (--dart-define).
class AppConfig {
  AppConfig._();

  /// Backend server URL (Socket.io + REST).
  /// Pass via: --dart-define=BACKEND_URL=http://your-server:3000
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// Agora App ID (safe to embed client-side — used for RTC engine init).
  /// The App Certificate stays server-side only.ike 
  static const String agoraAppId = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: '',
  );
}
