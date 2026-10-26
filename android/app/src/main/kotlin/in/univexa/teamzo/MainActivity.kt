package `in`.univexa.teamzo

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth's Android implementation drives Android's BiometricPrompt through
// FragmentManager, which only a FragmentActivity exposes — a plain FlutterActivity makes
// every biometric authenticate() call fail (silently, from Dart's point of view, since
// AppLockNotifier.enableBiometric() catches and swallows the resulting PlatformException).
class MainActivity : FlutterFragmentActivity()
