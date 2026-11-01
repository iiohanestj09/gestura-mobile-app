import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'app/gestura_app.dart';
import 'firebase_options.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? firebaseError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (error) {
    firebaseError = '${error.code}: ${error.message ?? 'Firebase belum siap.'}';
  } on StateError catch (error) {
    firebaseError = error.message.toString();
  } on UnsupportedError catch (error) {
    firebaseError = error.message ?? 'Platform Firebase belum dikonfigurasi.';
  } on PlatformException catch (error) {
    firebaseError = '${error.code}: ${error.message ?? 'Firebase belum siap.'}';
  }
  runApp(GesturaApp(firebaseError: firebaseError));
}
