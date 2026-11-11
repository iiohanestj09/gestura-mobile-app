import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/gestura_theme.dart';
import '../../data/sample_data.dart';
import '../../data/firebase_service.dart';
import '../../data/gesture_api_service.dart';
import '../auth/auth_pages.dart';
import 'camera_practice_page.dart';
import '../../widgets/gestura_widgets.dart';
import '../../widgets/simulation_video_player.dart';

class DetailPage extends StatefulWidget {
  const DetailPage(
      {required this.title,
      required this.onOpen,
      required this.onLogout,
      super.key});
  final String title;
  final void Function(String) onOpen;
  final Future<void> Function() onLogout;
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  bool deletingAccount = false;
  bool savingForm = false;
  final search = TextEditingController();
  final formController = TextEditingController();
  final profileNameController = TextEditingController();
  final emailController = TextEditingController();
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final feedbackController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final user = FirebaseService.currentUser;
    profileNameController.text = user?.displayName ?? '';
    emailController.text = user?.email ?? '';
  }

  @override
  void dispose() {
    search.dispose();
    formController.dispose();
    profileNameController.dispose();
    emailController.dispose();
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    feedbackController.dispose();
    super.dispose();
  }

  void go(String page) => widget.onOpen(page);

  GestureCategory? _categoryForLesson(String title) {
    if (title.startsWith('Huruf ')) return GestureCategory.alphabet;
    if (title.startsWith('Angka ')) return GestureCategory.digit;
    if (GestureCategory.vocabulary.labels.contains(title)) {
      return GestureCategory.vocabulary;
    }
    return null;
  }

  String? _targetForLesson(String title, GestureCategory category) {
    if (category == GestureCategory.alphabet && title.startsWith('Huruf ')) {
      return title.substring('Huruf '.length);
    }
    if (category == GestureCategory.digit && title.startsWith('Angka ')) {
      return title.substring('Angka '.length);
    }
    if (category == GestureCategory.vocabulary &&
        category.labels.contains(title)) {
      return title;
    }
    return null;
  }

  GestureCategory? _categoryFromRoute(String route) {
    for (final category in GestureCategory.values) {
      if (category.apiValue == route) return category;
    }
    return null;
  }

  Future<void> _completeLesson(String title) async {
    try {
      await FirebaseService.completeLesson(title);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Progres materi berhasil disimpan.')));
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              error.message ?? 'Progres gagal disimpan (${error.code}).')));
    }
  }

  Widget _lessonCompletionButton(String title) => StreamBuilder<bool>(
        stream: FirebaseService.watchLessonCompleted(title),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text('Status progres gagal dimuat: ${snapshot.error}');
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LinearProgressIndicator();
          }
          final completed = snapshot.data == true;
          return PrimaryButton(
            completed ? 'Materi sudah selesai' : 'Tandai materi selesai',
            onPressed: completed ? null : () => _completeLesson(title),
            icon: completed ? Icons.check_circle : Icons.check_circle_outline,
          );
        },
      );

  Future<void> _logout(BuildContext context) async {
    try {
      await widget.onLogout();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.message ?? 'Gagal keluar (${error.code}).')));
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    setState(() => deletingAccount = true);
    try {
      await FirebaseService.deleteAccount(
        password: formController.text,
      );
      if (!context.mounted) return;
      final navigator = Navigator.of(context);
      navigator.popUntil((route) => route.isFirst);
      navigator.push(
        MaterialPageRoute(builder: (_) => const AuthPage(mode: 'Masuk')),
      );
    } on FirebaseAuthException catch (error) {
      if (!context.mounted) return;
      final message =
          error.code == 'wrong-password' || error.code == 'invalid-credential'
              ? 'Password aplikasi atau akun Google tidak cocok.'
              : error.message ?? 'Penghapusan akun gagal (${error.code}).';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(error.message ?? 'Penghapusan gagal (${error.code}).')));
    } on GoogleSignInException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Login Google gagal: $error')));
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => deletingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    return Scaffold(
        appBar: AppBar(
            title: Text(title.split('|').first,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            actions: title == 'Cari materi'
                ? null
                : [
                    IconButton(
                        onPressed: () => go('Cari materi'),
                        icon: const Icon(Icons.search_rounded))
                  ]),
        body: _content(context, title));
  }

  Widget _content(BuildContext context, String title) {
    if (title == 'Cari materi') {
      return _search(context);
    }
    if (title == 'Notifikasi') {
      return _notifications(context);
    }
    if (title == 'Konfirmasi logout' || title == 'Konfirmasi hapus akun') {
      return _confirm(context, title);
    }
    if (title.startsWith('Instruksi praktik|')) {
      final parts = title.split('|');
      return _practiceInstructions(
        context,
        category: parts.length > 1 ? _categoryFromRoute(parts[1]) : null,
        target: parts.length > 2 ? parts[2] : null,
      );
    }
    if (title == 'Instruksi praktik') {
      return _practiceInstructions(context);
    }
    if (title.startsWith('Kamera praktik|')) {
      final parts = title.split('|');
      return _camera(
        context,
        category: parts.length > 1 ? _categoryFromRoute(parts[1]) : null,
        target: parts.length > 2 ? parts[2] : null,
      );
    }
    if (title == 'Kamera praktik') {
      return _camera(context);
    }
    if (title == 'Hasil pengenalan gerakan' ||
        title == 'Feedback latihan' ||
        title == 'Hasil latihan') {
      return _result(context, title);
    }
    if (title == 'Kuis materi') {
      return _quiz(context);
    }
    if (title == 'Hasil kuis') {
      return _quizResult(context);
    }
    if (title == 'Video demonstrasi bahasa isyarat') {
      return _video(context);
    }
    if (title == 'Skenario percakapan' ||
        title == 'Detail skenario percakapan') {
      return _conversation(context);
    }
    if (title == 'Pengaturan notifikasi' ||
        title == 'Pengaturan tampilan' ||
        title == 'Pengaturan kamera dan izin') {
      return _settings(context, title);
    }
    if (title == 'Edit profil' ||
        title == 'Pengaturan akun' ||
        title == 'Ubah password' ||
        title == 'Ubah email' ||
        title == 'Kirim masukan') {
      return _formPage(context, title);
    }
    if (title == 'Bantuan dan FAQ' || title == 'Tentang Gestura') {
      return _info(context, title);
    }
    if (title == 'Riwayat belajar') {
      return _history(context);
    }
    if (title == 'Riwayat latihan') {
      return _practiceHistory(context);
    }
    if (title == 'Kategori pembelajaran' ||
        SampleData.categories.any((e) => e['name'] == title)) {
      return _category(context, title);
    }
    if (title.contains('Dasar BISINDO') ||
        title.contains('Kosakata sehari') ||
        title.contains('Kalimat sederhana') ||
        title == 'Daftar course' ||
        title == 'Detail course') {
      return _course(context, title);
    }
    if (title == 'Pembelajaran alfabet') {
      return _alphabet(context);
    }
    if (title.startsWith('Huruf ') || title.startsWith('Angka ')) {
      return _lesson(context, title);
    }
    if (title == 'Pembelajaran kalimat') {
      return _sentences(context);
    }
    if (title == 'Pembelajaran kosakata' ||
        GestureCategory.vocabulary.labels.contains(title)) {
      return _vocabulary(context, title);
    }
    if (title == 'Daftar materi' || title == 'Daftar lesson') {
      return _lessons(context);
    }
    return _lesson(context, title);
  }

  Widget _wrap(Widget child) => SafeArea(
      child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [child]));
  Widget _search(BuildContext context) => SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
            controller: search,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                hintText: 'Cari alfabet, kata, atau kalimat',
                prefixIcon: Icon(Icons.search))),
        const SizedBox(height: 22),
        const PageHeading('Materi populer'),
        ...SampleData.lessons
            .where((e) =>
                search.text.isEmpty ||
                e['title']!.toLowerCase().contains(search.text.toLowerCase()))
            .map((e) => LessonTile(item: e, onTap: () => go(e['title']!))),
        const PageHeading('Kosakata'),
        ...GestureCategory.vocabulary.labels
            .where((e) =>
                search.text.isEmpty ||
                e.toLowerCase().contains(search.text.toLowerCase()))
            .map((e) => LessonTile(item: {
                  'title': e,
                  'category': 'Kosakata BISINDO',
                  'duration': 'Materi',
                  'icon': '💬'
                }, onTap: () => go(e)))
      ]));
  Widget _category(BuildContext context, String title) {
    final list = SampleData.categories
        .where((e) => title == 'Kategori pembelajaran' || e['name'] == title)
        .toList();
    return _wrap(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeading(title == 'Kategori pembelajaran' ? 'Semua kategori' : title,
          subtitle:
              'Belajar BISINDO secara bertahap dengan contoh yang jelas.'),
      ...list.map((c) => LessonTile(item: {
            'title': c['name'] as String,
            'category': 'Materi BISINDO',
            'duration': c['name'] == 'Angka' ? '9 angka' : c['count'] as String,
            'icon': c['name'] == 'Angka' ? '123' : c['icon'] as String
          }, onTap: () => go(c['name'] as String))),
      if (title != 'Kategori pembelajaran') ...[
        const SizedBox(height: 14),
        const PageHeading('Materi dalam kategori'),
        ...SampleData.lessons
            .where((e) => e['category'] == title || title == 'Alfabet')
            .map((e) => LessonTile(item: e, onTap: () => go(e['title']!))),
        if (title == 'Angka')
          ...List.generate(
            9,
            (index) {
              final number = index + 1;
              return LessonTile(
                item: {
                  'title': 'Angka $number',
                  'category': 'Angka BISINDO',
                  'duration': 'Materi',
                  'icon': '$number',
                },
                onTap: () => go('Angka $number'),
              );
            },
          ),
        if (title == 'Kosakata')
          ...GestureCategory.vocabulary.labels.map((w) => LessonTile(item: {
                'title': w,
                'category': 'BISINDO',
                'duration': 'Materi',
                'icon': '💬'
              }, onTap: () => go(w)))
      ]
    ]));
  }

  Widget _course(BuildContext context, String title) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeading(
            title == 'Daftar course' || title == 'Detail course'
                ? 'Belajar dari dasar'
                : title,
            subtitle: 'Jelajahi daftar materi belajar yang tersedia.'),
        ...SampleData.courses.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SoftCard(
                onTap: () => go(e),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const LabelChip('COURSE BISINDO'),
                      const SizedBox(height: 12),
                      Text(e, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      const Text(
                          'Topik pembelajaran tersedia. Video peraga untuk materi ini belum disediakan.')
                    ])))),
        const SizedBox(height: 8),
        PrimaryButton('Lihat daftar lesson',
            onPressed: () => go('Daftar lesson')),
        TextButton(
            onPressed: () => go('Daftar materi'),
            child: const Text('Jelajahi semua materi'))
      ]));
  Widget _lessons(BuildContext context) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeading('Daftar lesson',
            subtitle: 'Ikuti urutan atau buka materi yang kamu butuhkan.'),
        ...SampleData.lessons
            .map((e) => LessonTile(item: e, onTap: () => go(e['title']!))),
        ...GestureCategory.vocabulary.labels.take(4).map((e) => LessonTile(
                item: {
                  'title': e,
                  'category': 'Kosakata',
                  'duration': 'Materi',
                  'icon': '💬'
                },
                onTap: () => go(e))),
        const SizedBox(height: 8),
        PrimaryButton('Mulai kuis materi', onPressed: () => go('Kuis materi'))
      ]));
  Widget _lesson(BuildContext context, String title) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LabelChip(title.startsWith('Huruf ')
            ? 'ALFABET BISINDO'
            : title.startsWith('Angka ')
                ? 'ANGKA BISINDO'
                : 'MATERI BISINDO'),
        const SizedBox(height: 14),
        PageHeading(title,
            subtitle: 'Buka materi dan gunakan latihan mandiri jika tersedia.'),
        VideoPlaceholder(title: title),
        TextButton.icon(
            onPressed: () => go('Video demonstrasi bahasa isyarat'),
            icon: const Icon(Icons.ondemand_video_rounded),
            label: const Text('Buka halaman video')),
        const SizedBox(height: 12),
        const PageHeading('Yang akan kamu pelajari'),
        const SoftCard(
            child: Text(
                'Video contoh dan uraian gerakan terverifikasi untuk materi ini belum tersedia. Jangan jadikan daftar kata ini sebagai panduan bentuk isyarat.')),
        const SizedBox(height: 20),
        PrimaryButton('Latih gerakan ini', onPressed: () {
          final category = _categoryForLesson(title);
          final target =
              category == null ? null : _targetForLesson(title, category);
          go(category == null || target == null
              ? 'Instruksi praktik'
              : 'Instruksi praktik|${category.apiValue}|$target');
        }, icon: Icons.front_hand_rounded),
        TextButton(
            onPressed: () => go('Kuis materi'),
            child: const Text('Coba kuis materi')),
        const SizedBox(height: 8),
        _lessonCompletionButton(title)
      ]));
  Widget _video(BuildContext context) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeading('Video demonstrasi',
            subtitle: 'Belum ada video peraga yang dapat diputar.'),
        const VideoPlaceholder(title: 'Materi BISINDO'),
        const SizedBox(height: 18),
        const Text(
            'Folder assets/videos masih kosong. Materi video BISINDO perlu ditambahkan dari sumber terverifikasi yang memiliki izin penggunaan.'),
        const SizedBox(height: 22),
        PrimaryButton('Praktikkan gerakan',
            onPressed: () => go('Instruksi praktik'))
      ]));
  Widget _alphabet(BuildContext context) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeading('Belajar alfabet BISINDO',
            subtitle: 'Pilih huruf untuk membuka halaman materinya.'),
        GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: List.generate(
                26,
                (i) => SoftCard(
                    color: i == 0 ? GesturaTheme.mint : Colors.white,
                    padding: EdgeInsets.zero,
                    onTap: () => go('Huruf ${String.fromCharCode(65 + i)}'),
                    child: Center(
                        child: Text(String.fromCharCode(65 + i),
                            style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                color: GesturaTheme.teal)))))),
        const SizedBox(height: 18),
        const Text(
            'Materi gerakan huruf akan menggunakan video peraga BISINDO yang terverifikasi.')
      ]));
  Widget _vocabulary(BuildContext context, String title) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeading(
            title == 'Pembelajaran kosakata' ? 'Kosakata sehari-hari' : title,
            subtitle: 'Daftar kata untuk latihan kosakata.'),
        if (title == 'Pembelajaran kosakata')
          ...GestureCategory.vocabulary.labels.map((e) => LessonTile(item: {
                'title': e,
                'category': 'BISINDO',
                'duration': 'Materi',
                'icon': '💬'
              }, onTap: () => go(e)))
        else ...[
          VideoPlaceholder(title: title),
          const SizedBox(height: 18),
          const LabelChip('KOSAKATA BISINDO'),
          const SizedBox(height: 14),
          const Text(
              'Video dan panduan bentuk isyarat untuk kata ini belum tersedia.'),
          const SizedBox(height: 22),
          PrimaryButton('Latihan kata ini',
              onPressed: () => go(
                  'Instruksi praktik|${GestureCategory.vocabulary.apiValue}|$title'))
        ]
      ]));
  Widget _sentences(BuildContext context) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeading('Kalimat sederhana',
            subtitle: 'Rangkai kosakata menjadi pesan yang mudah dipahami.'),
        ...[
          'Perkenalkan, nama saya ...',
          'Apa kabar?',
          'Saya ingin belajar',
          'Terima kasih banyak'
        ].map((e) => LessonTile(item: {
              'title': e,
              'category': 'Kalimat BISINDO',
              'duration': 'Materi',
              'icon': '📝'
            }, onTap: () => go(e))),
        PrimaryButton('Lihat skenario percakapan',
            onPressed: () => go('Skenario percakapan'))
      ]));
  Widget _conversation(BuildContext context) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeading('Skenario: di kafe',
            subtitle:
                'Konteks percakapan lisan, bukan panduan isyarat BISINDO.'),
        const VideoPlaceholder(title: 'Memesan minuman'),
        const SizedBox(height: 18),
        const SoftCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Situasi',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: GesturaTheme.ink)),
          SizedBox(height: 6),
          Text(
              'Contoh urutan dialog: menyapa barista, menyampaikan pesanan, lalu mengucapkan terima kasih. Contoh frasa BISINDO belum tersedia.')
        ])),
        const SizedBox(height: 20),
        PrimaryButton('Lihat topik materi',
            onPressed: () => go('Daftar lesson'))
      ]));
  Widget _practiceInstructions(
    BuildContext context, {
    GestureCategory? category,
    String? target,
  }) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeading(
          category == null || target == null
              ? 'Contoh gerakan'
              : 'Contoh isyarat $target',
          subtitle: 'Tekan tombol play untuk melihat simulasi gerakan.',
        ),
        if (category != null && target != null)
          SimulationVideoPlayer(category: category, target: target)
        else
          const SoftCard(
            child: Text(
              'Pilih kategori dan target dari tab Latihan untuk melihat video simulasi.',
            ),
          ),
        const SizedBox(height: 22),
        PrimaryButton('Mulai latihan',
            onPressed: () => go(category == null || target == null
                ? 'Kamera praktik'
                : 'Kamera praktik|${category.apiValue}|$target'),
            icon: Icons.camera_alt_rounded),
        const SizedBox(height: 8),
        const Center(
            child: Text(
                'Prediksi model masih bersifat percobaan dan bukan pengganti koreksi pengajar BISINDO.',
                textAlign: TextAlign.center,
                style: TextStyle(color: GesturaTheme.muted, fontSize: 12)))
      ]));
  Widget _camera(
    BuildContext context, {
    GestureCategory? category,
    String? target,
  }) =>
      CameraPracticePage(initialCategory: category, initialTarget: target);
  Widget _result(BuildContext context, String title) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeading('Hasil pengenalan gerakan',
            subtitle:
                'Hasil prediksi ditampilkan pada halaman kamera latihan.'),
        const SoftCard(
            child: Text(
                'Model yang tersedia masih baseline. Prediksi dapat keliru, khususnya pada variasi signer, kondisi kamera, atau isyarat di luar data latih.')),
        const SizedBox(height: 20),
        PrimaryButton('Kembali ke kamera',
            onPressed: () => go('Kamera praktik'),
            icon: Icons.camera_alt_rounded),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kembali ke materi'))
      ]));
  Widget _notifications(BuildContext context) => _wrap(const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading('Notifikasi', subtitle: 'Belum ada notifikasi baru.'),
          SoftCard(
              child: Text(
                  'Notifikasi push belum diaktifkan di aplikasi ini. Pengingat dan pembaruan tidak akan dikirim ke perangkat.'))
        ],
      ));

  Widget _quiz(BuildContext context) => const QuizFlow();
  Widget _quizResult(BuildContext context) => _wrap(const Column(children: [
        PageHeading('Hasil kuis',
            subtitle: 'Selesaikan semua pertanyaan untuk melihat nilaimu.'),
      ]));
  Widget _confirm(BuildContext context, String title) {
    final isLogout = title.contains('logout');
    final providers =
        FirebaseService.currentUser?.providerData.map((p) => p.providerId) ??
            const <String>[];
    final requiresPassword = providers.contains('password');
    final supportsGoogle = providers.contains('google.com');

    return _wrap(Column(children: [
      const SizedBox(height: 38),
      CircleAvatar(
          radius: 38,
          backgroundColor: const Color(0xFFFFF1D2),
          child: Icon(isLogout ? Icons.logout : Icons.delete_outline,
              color: GesturaTheme.teal, size: 34)),
      const SizedBox(height: 20),
      PageHeading(title,
          subtitle: isLogout
              ? 'Kamu bisa masuk kembali untuk melanjutkan progres belajarmu.'
              : 'Akun dan seluruh progres belajar akan dihapus permanen. Tindakan ini tidak dapat dibatalkan.'),
      if (!isLogout && requiresPassword) ...[
        const SizedBox(height: 18),
        TextField(
          controller: formController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password aplikasi',
            hintText: 'Masukkan password akun Gestura',
          ),
        ),
      ] else if (!isLogout && supportsGoogle) ...[
        const SizedBox(height: 12),
        const Text('Kamu akan diminta masuk kembali dengan akun Google.'),
      ] else if (!isLogout) ...[
        const SizedBox(height: 12),
        const Text('Metode masuk akun ini belum didukung untuk penghapusan.'),
      ],
      const SizedBox(height: 20),
      PrimaryButton(
        isLogout
            ? 'Keluar dari akun'
            : deletingAccount
                ? 'Menghapus akun…'
                : 'Hapus akun permanen',
        onPressed: deletingAccount ||
                (!isLogout && !requiresPassword && !supportsGoogle)
            ? null
            : () {
                if (isLogout) {
                  _logout(context);
                } else if (requiresPassword || supportsGoogle) {
                  _deleteAccount(context);
                }
              },
      ),
      TextButton(
          onPressed: deletingAccount ? null : () => Navigator.pop(context),
          child: const Text('Batal'))
    ]));
  }

  Widget _settings(BuildContext context, String title) {
    if (title == 'Pengaturan kamera dan izin') {
      return _wrap(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(title,
              subtitle:
                  'Izin kamera diminta oleh Android saat fitur digunakan.'),
          const SoftCard(
              child: Text(
                  'Kamera merekam video pendek untuk dianalisis backend. Rekaman dihapus setelah pemrosesan; hasil pengenalan tidak disimpan sebagai media.')),
          const SizedBox(height: 12),
          PrimaryButton('Buka preview kamera',
              onPressed: () => go('Kamera praktik'),
              icon: Icons.camera_alt_rounded),
        ],
      ));
    }

    final featureName = title == 'Pengaturan notifikasi'
        ? 'Notifikasi push'
        : 'Pengaturan tampilan';
    final explanation = title == 'Pengaturan notifikasi'
        ? 'Pengiriman notifikasi push, pengingat belajar, dan pembaruan akun belum diaktifkan.'
        : 'Pengaturan ukuran teks, kontras, dan animasi belum tersedia. Aplikasi menggunakan tampilan standar.';
    return _wrap(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(title, subtitle: '$featureName belum tersedia.'),
        SoftCard(child: Text(explanation)),
      ],
    ));
  }

  Future<void> _saveForm(BuildContext context, String title) async {
    setState(() => savingForm = true);
    try {
      switch (title) {
        case 'Edit profil':
          await FirebaseService.updateDisplayName(profileNameController.text);
          break;
        case 'Ubah email':
          await FirebaseService.sendEmailChangeVerification(
            emailController.text,
            password: formController.text,
          );
          break;
        case 'Ubah password':
          if (newPasswordController.text != confirmPasswordController.text) {
            throw ArgumentError('Konfirmasi password baru tidak cocok.');
          }
          await FirebaseService.changePassword(
            currentPassword: currentPasswordController.text,
            newPassword: newPasswordController.text,
          );
          break;
        case 'Kirim masukan':
          await FirebaseService.submitFeedback(feedbackController.text);
          break;
        default:
          return;
      }

      if (!context.mounted) return;
      final message = switch (title) {
        'Edit profil' => 'Nama profil berhasil diperbarui.',
        'Ubah email' =>
          'Tautan verifikasi perubahan email telah dikirim ke alamat baru.',
        'Ubah password' => 'Password berhasil diperbarui.',
        _ => 'Masukan berhasil dikirim.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      Navigator.pop(context);
    } on FirebaseAuthException catch (error) {
      if (!context.mounted) return;
      final message = switch (error.code) {
        'wrong-password' ||
        'invalid-credential' =>
          'Password saat ini tidak cocok.',
        'requires-recent-login' =>
          'Silakan masuk kembali, lalu ulangi perubahan ini.',
        'email-already-in-use' => 'Email tersebut sudah digunakan.',
        _ => error.message ?? 'Perubahan gagal (${error.code}).',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Penyimpanan gagal (${error.code}).'),
        ),
      );
    } on ArgumentError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message.toString())));
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } on GoogleSignInException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login Google gagal: $error')),
      );
    } finally {
      if (mounted) setState(() => savingForm = false);
    }
  }

  Widget _formPage(BuildContext context, String title) {
    final providers =
        FirebaseService.currentUser?.providerData.map((p) => p.providerId) ??
            const <String>[];
    final usesPasswordProvider = providers.contains('password');
    final usesGoogleProvider = providers.contains('google.com');
    final isEditableForm = title == 'Edit profil' ||
        title == 'Ubah email' ||
        title == 'Ubah password' ||
        title == 'Kirim masukan';

    return _wrap(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeading(
        title,
        subtitle: switch (title) {
          'Edit profil' => 'Nama ini akan diperbarui di akun dan Firestore.',
          'Ubah email' => 'Email baru aktif setelah tautan verifikasi dibuka.',
          'Ubah password' =>
            'Perubahan dilakukan melalui Firebase Authentication.',
          'Kirim masukan' =>
            'Masukan disimpan agar pengelola project dapat meninjau.',
          _ => 'Kelola pengaturan akun Gestura.',
        },
      ),
      if (title == 'Edit profil') ...[
        const Text('Nama lengkap'),
        const SizedBox(height: 8),
        TextFormField(
            controller: profileNameController,
            textCapitalization: TextCapitalization.words,
            maxLength: 50,
            decoration:
                const InputDecoration(prefixIcon: Icon(Icons.person_outline))),
        const SizedBox(height: 16),
        const Text('Email'),
        const SizedBox(height: 8),
        TextFormField(
            controller: emailController,
            readOnly: true,
            decoration:
                const InputDecoration(prefixIcon: Icon(Icons.mail_outline)))
      ],
      if (title == 'Ubah email') ...[
        const Text('Email baru'),
        const SizedBox(height: 8),
        TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
                hintText: 'email@contoh.com',
                prefixIcon: Icon(Icons.mail_outline))),
        if (usesPasswordProvider) ...[
          const SizedBox(height: 16),
          const Text('Password saat ini'),
          const SizedBox(height: 8),
          TextField(
              controller: formController,
              obscureText: true,
              decoration: const InputDecoration(
                  hintText: 'Konfirmasi password aplikasi'))
        ] else if (usesGoogleProvider) ...[
          const SizedBox(height: 12),
          const Text('Kamu akan diminta masuk kembali dengan Google.')
        ]
      ],
      if (title == 'Ubah password') ...[
        if (usesPasswordProvider) ...[
          const Text('Password saat ini'),
          const SizedBox(height: 8),
          TextField(
              controller: currentPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                  hintText: 'Masukkan password saat ini')),
          const SizedBox(height: 14),
          const Text('Password baru'),
          const SizedBox(height: 8),
          TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration:
                  const InputDecoration(hintText: 'Minimal 8 karakter')),
          const SizedBox(height: 14),
          const Text('Ulangi password baru'),
          const SizedBox(height: 8),
          TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration:
                  const InputDecoration(hintText: 'Ketik ulang password baru')),
        ] else ...[
          const SoftCard(
              child: Text(
                  'Akun ini menggunakan Google. Password dikelola melalui akun Google dan tidak dapat diubah dari Gestura.'))
        ]
      ],
      if (title == 'Pengaturan akun')
        ...['Ubah password', 'Ubah email', 'Konfirmasi hapus akun']
            .map((e) => SettingsMenuRow(e, onTap: () => go(e))),
      if (title == 'Kirim masukan') ...[
        const Text('Ceritakan pengalamanmu'),
        const SizedBox(height: 8),
        TextField(
            controller: feedbackController,
            maxLines: 5,
            maxLength: 2000,
            decoration:
                const InputDecoration(hintText: 'Tulis masukan di sini...'))
      ],
      const SizedBox(height: 22),
      if (isEditableForm)
        PrimaryButton(
          savingForm ? 'Menyimpan…' : 'Simpan perubahan',
          onPressed:
              savingForm || (title == 'Ubah password' && !usesPasswordProvider)
                  ? null
                  : () => _saveForm(context, title),
        )
    ]));
  }

  Widget _info(BuildContext context, String title) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
            title == 'Tentang Gestura'
                ? Icons.waving_hand_rounded
                : Icons.help_outline_rounded,
            size: 48,
            color: GesturaTheme.teal),
        const SizedBox(height: 16),
        PageHeading(title,
            subtitle: title == 'Tentang Gestura'
                ? 'Gestura membantu pemula belajar BISINDO melalui materi visual yang bertahap.'
                : 'Temukan jawaban untuk pertanyaan umum.'),
        if (title == 'Tentang Gestura')
          const SoftCard(
              child: Text(
                  'Gestura membantu mengelola progres belajar dan menyediakan prediksi gerakan berbasis model baseline. Video peraga BISINDO terverifikasi belum tersedia.'))
        else
          ...[
            (
              question: 'Apa itu BISINDO?',
              answer:
                  'BISINDO adalah Bahasa Isyarat Indonesia yang digunakan oleh komunitas Tuli di Indonesia. Bahasa isyarat memiliki tata bahasa dan variasi penggunaan sendiri.'
            ),
            (
              question: 'Apakah pengenalan kamera sudah aktif?',
              answer:
                  'Ya. Pilih kategori di halaman kamera, rekam video singkat, dan backend akan memberikan prediksi. Hasilnya masih baseline dan dapat keliru.'
            ),
            (
              question: 'Bagaimana cara memulai belajar?',
              answer:
                  'Pilih topik dari tab Belajar. Tandai materi selesai untuk menyimpan progres, atau buka tab Latihan untuk mencoba pengenalan melalui kamera.'
            ),
          ].map((faq) => ExpansionTile(title: Text(faq.question), children: [
                Padding(
                    padding: const EdgeInsets.all(16), child: Text(faq.answer))
              ]))
      ]));
  Widget _history(BuildContext context) =>
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirebaseService.watchProgress(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _wrap(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const PageHeading('Riwayat belajar'),
              Text('Riwayat gagal dimuat: ${snapshot.error}')
            ]));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _wrap(const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeading('Riwayat belajar',
                      subtitle: 'Memuat progres belajarmu...'),
                  LinearProgressIndicator()
                ]));
          }

          final progress = snapshot.data ?? [];
          return _wrap(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const PageHeading('Riwayat belajar',
                subtitle: 'Materi dan kuis yang sudah kamu selesaikan.'),
            if (progress.isEmpty)
              const SoftCard(
                  color: GesturaTheme.mint,
                  child: Text(
                      'Belum ada materi selesai. Buka materi dan tekan "Tandai materi selesai" untuk menyimpan progres.'))
            else ...[
              ...progress.map((item) {
                final title = item['title'] as String? ?? 'Materi BISINDO';
                final isQuiz = item['kind'] == 'quiz';
                return LessonTile(item: {
                  'title': title,
                  'category': isQuiz ? 'Kuis selesai' : 'Materi selesai',
                  'duration': 'Progres tersimpan',
                  'icon': '✓'
                }, onTap: () => go(title));
              }),
              SoftCard(
                  color: GesturaTheme.mint,
                  child: Text(
                      '${progress.length} item belajar selesai • Progres tersimpan di Firestore.',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: GesturaTheme.tealDark)))
            ]
          ]));
        },
      );

  Widget _practiceHistory(BuildContext context) =>
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirebaseService.watchPracticeSessions(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _wrap(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PageHeading('Riwayat latihan'),
                Text('Riwayat gagal dimuat: ${snapshot.error}'),
              ],
            ));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _wrap(const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeading('Riwayat latihan',
                    subtitle: 'Memuat sesi latihan...'),
                LinearProgressIndicator(),
              ],
            ));
          }
          final sessions = snapshot.data ?? [];
          return _wrap(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeading('Riwayat latihan',
                  subtitle: 'Durasi sesi yang kamu selesaikan.'),
              if (sessions.isEmpty)
                const SoftCard(
                    child: Text('Belum ada sesi latihan yang diselesaikan.'))
              else
                ...List.generate(sessions.length, (index) {
                  final session = sessions[index];
                  final seconds = session['durationSeconds'] as int? ?? 0;
                  final category = switch (session['category']) {
                    'alphabet' => 'Alfabet',
                    'digit' => 'Angka',
                    'vocabulary' => 'Kosakata',
                    _ => 'Latihan',
                  };
                  final target = session['targetLabel'] as String? ?? '—';
                  final confidence =
                      (session['confidence'] as num?)?.toDouble() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SoftCard(
                      child: Row(
                        children: [
                          const Icon(Icons.front_hand_rounded,
                              color: GesturaTheme.teal),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$category • target $target',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                Text(
                                  'Prediksi cocok • confidence '
                                  '${(confidence * 100).toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    color: GesturaTheme.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(_formatPracticeDuration(seconds)),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ));
        },
      );
}

String _formatPracticeDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  return '$minutes menit $remainingSeconds detik';
}

class QuizFlow extends StatefulWidget {
  const QuizFlow({super.key});

  @override
  State<QuizFlow> createState() => _QuizFlowState();
}

class _QuizFlowState extends State<QuizFlow> {
  static const questions = [
    (
      question: 'Saat mempelajari gerakan baru, apa yang sebaiknya diamati?',
      choices: [
        'Bentuk tangan dan arah gerak secara utuh',
        'Hanya warna pakaian peraga',
        'Menebak gerakan tanpa memperhatikan'
      ],
      answer: 0,
    ),
    (
      question: 'Apa yang membantu saat berlatih mandiri menggunakan kamera?',
      choices: [
        'Pencahayaan cukup dan tangan terlihat jelas',
        'Merekam orang lain tanpa izin',
        'Berlatih di tempat yang gelap'
      ],
      answer: 0,
    ),
    (
      question:
          'Jika belum yakin dengan suatu gerakan BISINDO, apa langkah terbaik?',
      choices: [
        'Memastikan kembali kepada pengajar atau komunitas BISINDO',
        'Menganggap semua bahasa isyarat sama',
        'Menyebarkan tebakan sebagai jawaban pasti'
      ],
      answer: 0,
    ),
  ];

  int questionIndex = 0;
  int? selectedAnswer;
  int correctAnswers = 0;
  bool answerChecked = false;
  bool savingResult = false;
  bool finished = false;
  String? saveError;

  Future<void> _advance() async {
    if (!answerChecked || selectedAnswer == null) return;
    if (questionIndex < questions.length - 1) {
      setState(() {
        questionIndex++;
        selectedAnswer = null;
        answerChecked = false;
      });
      return;
    }

    setState(() => savingResult = true);
    try {
      await FirebaseService.recordQuizResult(
        correctAnswers: correctAnswers,
        totalQuestions: questions.length,
      );
    } on FirebaseException catch (error) {
      saveError = error.message ?? 'Hasil gagal disimpan (${error.code}).';
    } on StateError catch (error) {
      saveError = error.message;
    } finally {
      if (mounted) {
        setState(() {
          savingResult = false;
          finished = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (finished) {
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            const Icon(Icons.task_alt_rounded,
                size: 70, color: GesturaTheme.teal),
            const SizedBox(height: 14),
            PageHeading(
              'Kuis selesai',
              subtitle:
                  'Jawaban benar: $correctAnswers dari ${questions.length}.',
            ),
            if (saveError != null)
              SoftCard(child: Text('Hasil belum tersimpan: $saveError'))
            else
              const SoftCard(
                  child:
                      Text('Hasil kuis sudah tersimpan di riwayat belajar.')),
            const SizedBox(height: 20),
            PrimaryButton(
              'Ulangi kuis',
              onPressed: () => setState(() {
                questionIndex = 0;
                selectedAnswer = null;
                correctAnswers = 0;
                answerChecked = false;
                finished = false;
                saveError = null;
              }),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kembali ke materi'),
            ),
          ],
        ),
      );
    }

    final question = questions[questionIndex];
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          const PageHeading('Kuis: salam dan sapaan',
              subtitle: 'Pilih jawaban yang paling sesuai.'),
          LabelChip('PERTANYAAN ${questionIndex + 1} DARI ${questions.length}'),
          const SizedBox(height: 16),
          Text(question.question,
              style: const TextStyle(
                  fontSize: 19,
                  color: GesturaTheme.ink,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          ...List.generate(question.choices.length, (index) {
            final isSelected = selectedAnswer == index;
            final isCorrect = index == question.answer;
            final color = answerChecked && isCorrect
                ? GesturaTheme.mint
                : answerChecked && isSelected
                    ? const Color(0xFFFFE6E3)
                    : Colors.white;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SoftCard(
                color: color,
                onTap: answerChecked
                    ? null
                    : () => setState(() => selectedAnswer = index),
                child: Row(children: [
                  Icon(
                    answerChecked && isCorrect
                        ? Icons.check_circle
                        : answerChecked && isSelected
                            ? Icons.cancel
                            : isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                    color: answerChecked && !isCorrect && isSelected
                        ? Colors.red
                        : GesturaTheme.teal,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(question.choices[index],
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: GesturaTheme.ink))),
                ]),
              ),
            );
          }),
          if (answerChecked) ...[
            const SizedBox(height: 6),
            Text(
              selectedAnswer == question.answer
                  ? 'Benar.'
                  : 'Belum tepat. Jawaban yang benar ditandai di atas.',
              style: const TextStyle(
                  color: GesturaTheme.tealDark, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            savingResult
                ? 'Menyimpan hasil…'
                : answerChecked
                    ? questionIndex == questions.length - 1
                        ? 'Lihat hasil'
                        : 'Pertanyaan berikutnya'
                    : 'Periksa jawaban',
            onPressed: savingResult || selectedAnswer == null
                ? null
                : () {
                    if (!answerChecked) {
                      setState(() {
                        answerChecked = true;
                        if (selectedAnswer == question.answer) {
                          correctAnswers++;
                        }
                      });
                    } else {
                      _advance();
                    }
                  },
          ),
        ],
      ),
    );
  }
}
