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
    if (actionUri == null) {
      return false;
    }
    final mode = actionUri.queryParameters['mode'];
    if (mode != 'verifyEmail' && mode != 'verifyAndChangeEmail') return false;

    final actionCode = actionUri.queryParameters['oobCode'];
    if (actionCode == null || actionCode.isEmpty) {
      throw const FormatException('Kode verifikasi tidak ditemukan di tautan.');
    }

    final actionInfo = await auth.checkActionCode(actionCode);
    final expectedOperation = mode == 'verifyEmail'
        ? ActionCodeInfoOperation.verifyEmail
        : ActionCodeInfoOperation.verifyAndChangeEmail;
    if (actionInfo.operation != expectedOperation) {
      throw const FormatException('Tautan ini bukan tautan email yang sesuai.');
    }

    await auth.applyActionCode(actionCode);
    await currentUser?.reload();
    if (mode == 'verifyAndChangeEmail' && currentUser != null) {
      await syncProfile(currentUser!);
    }
    return true;
  }

  static Future<void> sendPasswordReset(String email) =>
      auth.sendPasswordResetEmail(email: email.trim());

  static Future<void> updateDisplayName(String name) async {
    final user = currentUser;
    if (user == null) throw StateError('Tidak ada akun yang sedang masuk.');
    final normalizedName = name.trim();
    if (normalizedName.length < 2 || normalizedName.length > 50) {
      throw ArgumentError('Nama harus terdiri dari 2 sampai 50 karakter.');
    }
    await user.updateDisplayName(normalizedName);
    await firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'displayName': normalizedName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await user.reload();
  }

  static Future<void> sendEmailChangeVerification(
    String newEmail, {
    String? password,
  }) async {
    final user = currentUser;
    if (user == null) throw StateError('Tidak ada akun yang sedang masuk.');
    final normalizedEmail = newEmail.trim();
    if (normalizedEmail.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
      throw ArgumentError('Masukkan alamat email yang valid.');
    }
    if (normalizedEmail.toLowerCase() == user.email?.toLowerCase()) {
      throw ArgumentError('Email baru harus berbeda dari email saat ini.');
    }
    await _reauthenticate(user, password: password);
    await user.verifyBeforeUpdateEmail(
      normalizedEmail,
      ActionCodeSettings(
        url: 'https://gestura-b095.firebaseapp.com/continue',
        androidPackageName: 'com.example.gestura',
        handleCodeInApp: true,
      ),
    );
  }

  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = currentUser;
    if (user == null) throw StateError('Tidak ada akun yang sedang masuk.');
    if (!user.providerData
        .any((provider) => provider.providerId == 'password')) {
      throw StateError(
        'Password akun ini dikelola oleh penyedia login, bukan Gestura.',
      );
    }
    if (newPassword.length < 8) {
      throw ArgumentError('Password baru minimal 8 karakter.');
    }
    await _reauthenticate(user, password: currentPassword);
    await user.updatePassword(newPassword);
  }

  static Stream<Map<String, dynamic>?> watchProfile() {
    final user = currentUser;
    if (user == null) throw StateError('Tidak ada akun yang sedang masuk.');
    return firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  static Future<void> submitFeedback(String message) async {
    final user = currentUser;
    if (user == null) throw StateError('Tidak ada akun yang sedang masuk.');
    final content = message.trim();
    if (content.length < 5 || content.length > 2000) {
      throw ArgumentError('Masukan harus terdiri dari 5 sampai 2000 karakter.');
    }
    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('feedback')
        .add({
      'message': content,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> signOut() async {
    await auth.signOut();
    final initialization = _googleSignInInitialization;
    if (initialization != null) {
      await initialization;
      await GoogleSignIn.instance.signOut();
    }
  }

  static Future<void> deleteAccount({String? password}) async {
    final user = currentUser;
    if (user == null) {
      throw StateError('Tidak ada akun yang sedang masuk.');
    }

    await _reauthenticate(user, password: password);

    final userDocument = firestore.collection('users').doc(user.uid);
    for (final collection in [
      'progress',
      'feedback',
      'practiceSessions',
      'practicePredictions',
    ]) {
      final documents = userDocument.collection(collection);
      while (true) {
        final snapshot = await documents.limit(450).get();
        if (snapshot.docs.isEmpty) break;
        final batch = firestore.batch();
        for (final document in snapshot.docs) {
          batch.delete(document.reference);
        }
        await batch.commit();
      }
    }

    await userDocument.delete();
    await user.delete();
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
      'kind': 'lesson',
      'completedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> recordQuizResult({
    required int correctAnswers,
    required int totalQuestions,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw StateError('Kamu harus masuk untuk menyimpan hasil kuis.');
    }
    if (totalQuestions <= 0 ||
        correctAnswers < 0 ||
        correctAnswers > totalQuestions) {
      throw ArgumentError('Hasil kuis tidak valid.');
    }
    const title = 'Kuis salam dan sapaan';
    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('progress')
        .doc(_lessonId(title))
        .set({
      'lessonId': _lessonId(title),
      'title': title,
      'completed': true,
      'kind': 'quiz',
      'correctAnswers': correctAnswers,
      'totalQuestions': totalQuestions,
      'completedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> recordGesturePrediction({
    required String category,
    required String targetLabel,
    required String predictionLabel,
    required double confidence,
    required int stableMilliseconds,
    required bool matchedTarget,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw StateError('Kamu harus masuk untuk menyimpan prediksi.');
    }
    if (category != 'alphabet' &&
        category != 'digit' &&
        category != 'vocabulary') {
      throw ArgumentError('Kategori prediksi tidak dikenal.');
    }
    if (targetLabel.isEmpty ||
        predictionLabel.isEmpty ||
        confidence < 0 ||
        confidence > 1 ||
        stableMilliseconds < 0) {
      throw ArgumentError('Data prediksi gerakan tidak valid.');
    }
    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('practicePredictions')
        .add({
      'category': category,
      'targetLabel': targetLabel,
      'predictionLabel': predictionLabel,
      'confidence': confidence,
      'stableMilliseconds': stableMilliseconds,
      'matchedTarget': matchedTarget,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> recordPracticeSession(
    int durationSeconds, {
    required String category,
    required String targetLabel,
    required String predictionLabel,
    required double confidence,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw StateError('Kamu harus masuk untuk menyimpan sesi latihan.');
    }
    if (durationSeconds < 1) {
      throw ArgumentError('Sesi latihan harus berlangsung minimal 1 detik.');
    }
    if (category != 'alphabet' &&
        category != 'digit' &&
        category != 'vocabulary') {
      throw ArgumentError('Kategori latihan tidak dikenal.');
    }
    if (targetLabel.isEmpty ||
        predictionLabel != targetLabel ||
        confidence < 0 ||
        confidence > 1) {
      throw ArgumentError('Hasil sesi latihan tidak valid.');
    }
    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('practiceSessions')
        .add({
      'durationSeconds': durationSeconds,
      'category': category,
      'targetLabel': targetLabel,
      'predictionLabel': predictionLabel,
      'confidence': confidence,
      'outcome': 'correct',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<List<Map<String, dynamic>>> watchPracticeSessions() {
    final user = currentUser;
    if (user == null) {
      throw StateError('Kamu harus masuk untuk melihat sesi latihan.');
    }
    return firestore
        .collection('users')
        .doc(user.uid)
        .collection('practiceSessions')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((document) => document.data())
            .toList(growable: false));
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
    final existingName = existing.data()?['displayName'] as String?;
    final resolvedName = existingName?.trim().isNotEmpty == true
        ? existingName!.trim()
        : name.trim();
    final data = <String, Object?>{
      'uid': user.uid,
      'email': user.email,
      'displayName': resolvedName,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!existing.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    await profile.set(data, SetOptions(merge: true));
  }

  static Future<void> syncProfile(User user) async {
    await firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> _reauthenticate(
    User user, {
    String? password,
  }) async {
    final providers = user.providerData.map((provider) => provider.providerId);
    if (providers.contains('password')) {
      final email = user.email;
      if (email == null || password == null || password.isEmpty) {
        throw StateError('Masukkan password aplikasi untuk melanjutkan.');
      }
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      return;
    }
    if (providers.contains('google.com')) {
      await (_googleSignInInitialization ??=
          GoogleSignIn.instance.initialize());
      final googleUser = await GoogleSignIn.instance.authenticate();
      final idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        throw StateError(
          'Token Google tidak tersedia. Perbarui konfigurasi Firebase Android.',
        );
      }
      await user.reauthenticateWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      return;
    }
    throw StateError(
      'Metode masuk akun ini belum didukung untuk operasi ini.',
    );
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
