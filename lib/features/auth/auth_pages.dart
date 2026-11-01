import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/gestura_theme.dart';
import '../../data/firebase_service.dart';
import '../../widgets/gestura_widgets.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      BrandMark(),
                      SizedBox(width: 10),
                      Text('gestura',
                          style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              color: GesturaTheme.tealDark))
                    ]),
                    const Spacer(),
                    Center(
                        child: Container(
                            width: 250,
                            height: 250,
                            decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFF0E9FF),
                                      Color(0xFFD9CCFF)
                                    ]),
                                boxShadow: [
                                  BoxShadow(
                                      color: GesturaTheme.tealDark
                                          .withValues(alpha: .12),
                                      blurRadius: 28,
                                      offset: const Offset(0, 14))
                                ],
                                borderRadius: BorderRadius.circular(100)),
                            child: const Center(
                                child: Text('👋',
                                    style: TextStyle(fontSize: 100))))),
                    const SizedBox(height: 36),
                    Text('Bahasa yang\nmenghubungkan kita.',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    const Text(
                        'Mulai belajar BISINDO dengan video peraga, materi bertahap, dan latihan yang menyenangkan.',
                        style:
                            TextStyle(color: GesturaTheme.muted, height: 1.5)),
                    const Spacer(),
                    PrimaryButton('Mulai belajar',
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const AuthPage(mode: 'Daftar')))),
                    const SizedBox(height: 12),
                    Center(
                        child: TextButton(
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const AuthPage(mode: 'Masuk'))),
                            child: const Text('Sudah punya akun? Masuk')))
                  ]))));
}

class AuthPage extends StatefulWidget {
  const AuthPage({required this.mode, super.key});
  final String mode;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  bool showPassword = false;
  bool loading = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  String get mode => widget.mode;

  Future<void> submit() async {
    if (!(form.currentState?.validate() ?? false)) return;
    setState(() => loading = true);
    try {
      if (mode == 'Lupa password') {
        await FirebaseService.sendPasswordReset(email.text);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => InfoPage(
              title: 'Cek email kamu',
              subtitle:
                  'Tautan untuk mengatur ulang password telah dikirim ke ${email.text.trim()}.',
              icon: Icons.mark_email_read_rounded,
            ),
          ),
        );
        return;
      }

      if (mode == 'Daftar') {
        await FirebaseService.signUp(
          name: name.text,
          email: email.text,
          password: password.text,
        );
      } else {
        await FirebaseService.signIn(
          email: email.text,
          password: password.text,
        );
      }
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseException catch (error) {
      if (!mounted) return;
      _showError(_firebaseErrorMessage(error));
    } on GoogleSignInException catch (error) {
      if (!mounted || error.code == GoogleSignInExceptionCode.canceled) return;
      _showError(error.code ==
              GoogleSignInExceptionCode.clientConfigurationError
          ? 'Konfigurasi Google belum lengkap. Perbarui google-services.json dan periksa SHA-1 Firebase.'
          : error.description ?? 'Google Sign-In gagal (${error.code.name}).');
    } on StateError catch (error) {
      if (mounted) _showError(error.message.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() => loading = true);
    try {
      await FirebaseService.signInWithGoogle();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseException catch (error) {
      if (mounted) _showError(_firebaseErrorMessage(error));
    } on GoogleSignInException catch (error) {
      if (!mounted || error.code == GoogleSignInExceptionCode.canceled) return;
      _showError(error.code ==
              GoogleSignInExceptionCode.clientConfigurationError
          ? 'Konfigurasi Google belum lengkap. Perbarui google-services.json dan periksa SHA-1 Firebase.'
          : error.description ?? 'Google Sign-In gagal (${error.code.name}).');
    } on StateError catch (error) {
      if (mounted) _showError(error.message.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = mode == 'Daftar';
    final hasPassword = mode != 'Lupa password';
    final showGoogle = mode == 'Daftar' || mode == 'Masuk';
    return Scaffold(
        appBar: AppBar(),
        body: SafeArea(
            child: Form(
                key: form,
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    children: [
                      Text(mode,
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      Text(_authSubtitle(mode),
                          style: const TextStyle(color: GesturaTheme.muted)),
                      const SizedBox(height: 28),
                      if (isSignUp) ...[
                        const Text('Nama lengkap'),
                        const SizedBox(height: 8),
                        TextFormField(
                            controller: name,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                                hintText: 'Nama kamu',
                                prefixIcon: Icon(Icons.person_outline)),
                            validator: (v) => (v == null || v.trim().length < 2)
                                ? 'Masukkan nama minimal 2 karakter'
                                : null),
                        const SizedBox(height: 18)
                      ],
                      const Text('Email'),
                      const SizedBox(height: 8),
                      TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                              hintText: 'nama@email.com',
                              prefixIcon: Icon(Icons.mail_outline)),
                          validator: (v) => (v == null ||
                                  !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                      .hasMatch(v))
                              ? 'Masukkan alamat email yang valid'
                              : null),
                      if (hasPassword) ...[
                        const SizedBox(height: 18),
                        const Text('Password'),
                        const SizedBox(height: 8),
                        TextFormField(
                            controller: password,
                            obscureText: !showPassword,
                            decoration: InputDecoration(
                                hintText: 'Minimal 8 karakter',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                    onPressed: () => setState(
                                        () => showPassword = !showPassword),
                                    icon: Icon(showPassword
                                        ? Icons.visibility_off
                                        : Icons.visibility))),
                            validator: (v) => (v == null || v.length < 8)
                                ? 'Password harus minimal 8 karakter'
                                : null)
                      ],
                      if (mode == 'Masuk')
                        Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const AuthPage(
                                            mode: 'Lupa password'))),
                                child: const Text('Lupa password?'))),
                      const SizedBox(height: 22),
                      PrimaryButton(loading ? 'Memproses…' : _authAction(mode),
                          onPressed: loading ? null : submit,
                          icon: loading
                              ? Icons.hourglass_top_rounded
                              : Icons.arrow_forward_rounded),
                      if (showGoogle) ...[
                        const SizedBox(height: 18),
                        const Row(children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('atau'),
                          ),
                          Expanded(child: Divider()),
                        ]),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: loading ? null : signInWithGoogle,
                          icon:
                              const Icon(Icons.g_mobiledata_rounded, size: 30),
                          label: const Text('Lanjutkan dengan Google'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Center(
                          child: TextButton(
                              onPressed: () {
                                final next =
                                    mode == 'Masuk' ? 'Daftar' : 'Masuk';
                                Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => AuthPage(mode: next)));
                              },
                              child: Text(mode == 'Masuk'
                                  ? 'Belum punya akun? Daftar'
                                  : 'Sudah punya akun? Masuk')))
                    ]))));
  }
}

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({required this.email, super.key});

  final String email;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  bool loading = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => loading = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_firebaseErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mark_email_unread_outlined,
                      size: 72, color: GesturaTheme.teal),
                  const SizedBox(height: 24),
                  Text('Verifikasi email',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(
                    'Kami mengirim tautan verifikasi ke ${widget.email}. Buka tautan itu, lalu kembali ke aplikasi.',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: GesturaTheme.muted, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(
                    loading ? 'Memeriksa…' : 'Saya sudah verifikasi',
                    onPressed: loading
                        ? null
                        : () => _run(
                              FirebaseService.reloadCurrentUser,
                              'Status akun diperbarui. Jika sudah terverifikasi, aplikasi akan terbuka.',
                            ),
                    icon: Icons.verified_outlined,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => _run(
                              FirebaseService.resendEmailVerification,
                              'Tautan verifikasi baru telah dikirim.',
                            ),
                    child: const Text('Kirim ulang email verifikasi'),
                  ),
                  TextButton(
                    onPressed: loading ? null : FirebaseService.signOut,
                    child: const Text('Keluar dan kembali ke login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

String _firebaseErrorMessage(FirebaseException error) => switch (error.code) {
      'email-already-in-use' => 'Email ini sudah terdaftar.',
      'invalid-email' => 'Format email tidak valid.',
      'weak-password' => 'Password terlalu mudah ditebak.',
      'invalid-credential' ||
      'user-not-found' ||
      'wrong-password' =>
        'Email atau password tidak sesuai.',
      'network-request-failed' =>
        'Tidak dapat terhubung. Periksa koneksi internetmu.',
      'too-many-requests' => 'Terlalu banyak percobaan. Coba lagi nanti.',
      'account-exists-with-different-credential' =>
        'Email sudah terdaftar dengan metode login lain.',
      _ => error.message ?? 'Terjadi kesalahan Firebase (${error.code}).',
    };

String _authSubtitle(String mode) => switch (mode) {
      'Masuk' => 'Senang bertemu kamu lagi. Lanjutkan perjalanan belajarmu.',
      'Daftar' => 'Buat akun untuk menyimpan progres belajarmu.',
      'Lupa password' =>
        'Masukkan email dan kami bantu kamu mengatur ulang password.',
      _ => 'Mulai belajar BISINDO dengan gestura.'
    };
String _authAction(String mode) => switch (mode) {
      'Masuk' => 'Masuk ke gestura',
      'Daftar' => 'Buat akun',
      'Lupa password' => 'Kirim tautan reset',
      _ => 'Lanjutkan'
    };

class InfoPage extends StatelessWidget {
  const InfoPage(
      {required this.title,
      required this.subtitle,
      required this.icon,
      super.key});
  final String title, subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(),
      body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 72, color: GesturaTheme.teal),
            const SizedBox(height: 24),
            Text(title,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: GesturaTheme.muted)),
            const SizedBox(height: 30),
            PrimaryButton('Kembali masuk',
                onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AuthPage(mode: 'Masuk')),
                    (_) => false))
          ])));
}
