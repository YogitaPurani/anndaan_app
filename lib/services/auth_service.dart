import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// AuthService compatible with google_sign_in ^7.x
/// - Uses GoogleSignIn.instance
/// - Calls initialize() before any other calls (required)
/// - Uses authenticate() for interactive sign-ins
/// - Uses idToken (accessToken / authorization separate in v7)
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  // ====== IMPORTANT: paste your Web OAuth Client ID here ======
  // This is the "Web client ID" / serverClientId created in Google Cloud Console.
  static const String _webClientId =
      "258522159669-lkc2gp6sc1r6akkh97g7ul0si63enuie.apps.googleusercontent.com";
  // ===========================================================

  bool _initialized = false;
  bool _initializing = false;

  AuthService() {
    _ensureInitialized();
  }

  /// Ensure the google_sign_in instance has been initialized exactly once.
  Future<void> _ensureInitialized() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    try {
      if (kIsWeb) {
        await _googleSignIn.initialize();
      } else {
        await _googleSignIn.initialize(serverClientId: _webClientId);
      }
      _initialized = true;
    } catch (e) {
      print('GoogleSignIn initialize failed: $e');
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  Stream<User?> get userChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signUpWithEmail(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);

  Future<UserCredential> signInWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  /// Sign in with Google (mobile & web friendly).
  Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      try {
        final provider = GoogleAuthProvider();
        final result = await _auth.signInWithPopup(provider);
        return result;
      } catch (e) {
        print('Web Google sign-in failed: $e');
        rethrow;
      }
    }

    await _ensureInitialized();

    try {
      try {
        await _googleSignIn.attemptLightweightAuthentication();
      } catch (_) {}

      GoogleSignInAccount? account;
      try {
        account = await _googleSignIn.authenticate();
      } on GoogleSignInException catch (e) {
        print('GoogleSignIn exception during authenticate: ${e.code} ${e.description}');
        if (e.code == GoogleSignInExceptionCode.canceled ||
            e.code.name == 'user_cancelled' ||
            e.code.name == 'cancelled') {
          return null;
        }
        rethrow;
      }

      final authTokens = await account.authentication;
      final idToken = authTokens.idToken;
      if (idToken == null) {
        throw FirebaseAuthException(
          code: 'MISSING_ID_TOKEN',
          message: 'Google sign-in did not return an idToken. '
              'Make sure serverClientId is configured in Google Cloud and passed to initialize().',
        );
      }

      final firebaseCred = GoogleAuthProvider.credential(idToken: idToken);
      return await _auth.signInWithCredential(firebaseCred);
    } on FirebaseAuthException catch (e) {
      print('FirebaseAuthException signing in with Google: ${e.code} ${e.message}');
      rethrow;
    } catch (e) {
      print('Unexpected error in signInWithGoogle: $e');
      rethrow;
    }
  }
  

  /// Sign out from both Firebase and Google.
  Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        await _googleSignIn.disconnect().catchError((_) => _googleSignIn.signOut());
      }
    } catch (e) {
      print('Google Sign-Out error: $e');
    }
    await _auth.signOut();
  }
}