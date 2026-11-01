import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseService {
  static final FirebaseAuth auth = FirebaseAuth.instance;
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;

  static User? get currentUser => auth.currentUser;

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

  static Future<void> sendPasswordReset(String email) =>
      auth.sendPasswordResetEmail(email: email.trim());

  static Future<void> signOut() => auth.signOut();

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
}
