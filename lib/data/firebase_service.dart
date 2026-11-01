import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseService {
  static final FirebaseAuth auth = FirebaseAuth.instance;
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static Future<void>? _googleSignInInitialization;

  static User? get currentUser => auth.currentUser;

  static bool canAccessApp(User user) {
    final providers = user.providerData.map((provider) => provider.providerId);
    return user.emailVerified || providers.contains('google.com');
  }

  static Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw StateError('Firebase tidak mengembalikan akun yang dibuat.');
    }

    await user.updateDisplayName(name.trim());
    await user.sendEmailVerification(
      ActionCodeSettings(
        url: 'https://gestura-b095.firebaseapp.com/continue',
        androidPackageName: 'com.example.gestura',
        handleCodeInApp: true,
      ),
    );
    await _saveProfile(user, name.trim());
  }

  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      await _saveProfile(user, user.displayName ?? '');
    }
  }

  static Future<void> signInWithGoogle() async {
    await (_googleSignInInitialization ??= GoogleSignIn.instance.initialize());
    final googleUser = await GoogleSignIn.instance.authenticate();
    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      throw StateError(
        'Token Google tidak tersedia. Perbarui konfigurasi Firebase Android.',
      );
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final result = await auth.signInWithCredential(credential);
    final user = result.user;
    if (user != null) {
      await _saveProfile(user, user.displayName ?? '');
    }
  }

  static Future<void> resendEmailVerification() async {
    final user = currentUser;
    if (user == null) {
      throw StateError('Tidak ada akun yang sedang masuk.');
    }
    await user.sendEmailVerification();
  }

  static Future<void> reloadCurrentUser() async {
    await currentUser?.reload();
  }

  static Future<bool> handleEmailVerificationLink(Uri link) async {
    final actionUri = _findEmailActionUri(link);
    if (actionUri == null ||
        actionUri.queryParameters['mode'] != 'verifyEmail') {
      return false;
    }

    final actionCode = actionUri.queryParameters['oobCode'];
    if (actionCode == null || actionCode.isEmpty) {
      throw const FormatException('Kode verifikasi tidak ditemukan di tautan.');
    }

    final actionInfo = await auth.checkActionCode(actionCode);
    if (actionInfo.operation != ActionCodeInfoOperation.verifyEmail) {
      throw const FormatException('Tautan ini bukan tautan verifikasi email.');
    }

    await auth.applyActionCode(actionCode);
    await currentUser?.reload();
    return true;
  }

  static Future<void> sendPasswordReset(String email) =>
      auth.sendPasswordResetEmail(email: email.trim());

  static Future<void> signOut() async {
    await auth.signOut();
    final initialization = _googleSignInInitialization;
    if (initialization != null) {
      await initialization;
      await GoogleSignIn.instance.signOut();
    }
  }

  static Future<void> completeLesson(String title) async {
    final user = currentUser;
    if (user == null) {
      throw StateError('Kamu harus masuk untuk menyimpan progres.');
    }

    final id = _lessonId(title);
    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('progress')
        .doc(id)
        .set({
      'lessonId': id,
      'title': title,
      'completed': true,
      'completedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<bool> watchLessonCompleted(String title) {
    final user = currentUser;
    if (user == null) {
      throw StateError('Kamu harus masuk untuk melihat progres.');
    }

    return firestore
        .collection('users')
        .doc(user.uid)
        .collection('progress')
        .doc(_lessonId(title))
        .snapshots()
        .map((snapshot) => snapshot.data()?['completed'] == true);
  }

  static Stream<List<Map<String, dynamic>>> watchProgress() {
    final user = currentUser;
    if (user == null) {
      throw StateError('Kamu harus masuk untuk melihat progres.');
    }

    return firestore
        .collection('users')
        .doc(user.uid)
        .collection('progress')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((document) => document.data())
            .toList(growable: false));
  }

  static Future<void> _saveProfile(User user, String name) async {
    final profile = firestore.collection('users').doc(user.uid);
    final existing = await profile.get();
    final data = <String, Object?>{
      'uid': user.uid,
      'email': user.email,
      'displayName': name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!existing.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    await profile.set(data, SetOptions(merge: true));
  }

  static String _lessonId(String title) => Uri.encodeComponent(
        title.trim().toLowerCase(),
      );

  static Uri? _findEmailActionUri(Uri uri, [int depth = 0]) {
    if (depth > 3) return null;
    final query = uri.queryParameters;
    if (query.containsKey('oobCode') && query.containsKey('mode')) {
      return uri;
    }

    for (final key in ['link', 'deep_link_id', 'continueUrl']) {
      final nestedLink = query[key];
      if (nestedLink == null) continue;
      final nestedUri = Uri.tryParse(nestedLink);
      if (nestedUri == null) continue;
      final result = _findEmailActionUri(nestedUri, depth + 1);
      if (result != null) return result;
    }
    return null;
  }
}
