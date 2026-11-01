import 'package:flutter/material.dart';
import '../../core/gestura_theme.dart';
import '../../data/sample_data.dart';
import '../../widgets/gestura_widgets.dart';

class DetailPage extends StatefulWidget {
  const DetailPage(
      {required this.title,
      required this.onOpen,
      required this.onLogout,
      super.key});
  final String title;
  final void Function(String) onOpen;
  final VoidCallback onLogout;
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  bool playing = false;
  final Map<String, bool> settingsValues = {};
  final search = TextEditingController();
  final formController = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    formController.dispose();
    super.dispose();
  }

  void go(String page) => widget.onOpen(page);
  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    return Scaffold(
        appBar: AppBar(
            title: Text(title,
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
    if (title == 'Konfirmasi logout' || title == 'Konfirmasi hapus akun') {
      return _confirm(context, title);
    }
    if (title == 'Instruksi praktik') {
      return _practiceInstructions(context);
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
    if (title == 'Simulasi percakapan' ||
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
    if (title == 'Pembelajaran kosakata' || SampleData.words.contains(title)) {
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
        ...SampleData.words
            .where((e) =>
                search.text.isEmpty ||
                e.toLowerCase().contains(search.text.toLowerCase()))
            .map((e) => LessonTile(item: {
                  'title': e,
                  'category': 'Kosakata BISINDO',
                  'duration': 'Materi video',
                  'icon': '💬'
                }, onTap: () => go(e)))
      ]));
  Widget _category(BuildContext context, String title) {
    final list = SampleData.categories.take(3)
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
            'duration': c['name'] == 'Angka' ? '10 angka' : c['count'] as String,
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
            10,
            (number) => LessonTile(
              item: {
                'title': 'Angka $number',
                'category': 'Angka BISINDO',
                'duration': 'Video peraga',
                'icon': '$number',
              },
              onTap: () => go('Angka $number'),
            ),
          ),
        if (title == 'Kosakata')
          ...SampleData.words.map((w) => LessonTile(item: {
                'title': w,
                'category': 'BISINDO',
                'duration': 'Video demonstrasi',
                'icon': '💬'
              }, onTap: () => go(w)))
      ]
    ]));
  }

  Widget _course(BuildContext context, String title) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeading('Belajar dari dasar',
            subtitle:
                'Materi tersusun dari pengenalan gerakan hingga percakapan.'),
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
                      const Text('Materi video peraga dan latihan terarah.'),
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(
                          value: .32,
                          color: GesturaTheme.teal,
                          backgroundColor: GesturaTheme.mint),
                      const SizedBox(height: 12),
                      const Text('2 dari 6 lesson • progres belajar',
                          style: TextStyle(
                              color: GesturaTheme.muted, fontSize: 12))
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
        ...SampleData.words.take(4).map((e) => LessonTile(item: {
              'title': e,
              'category': 'Kosakata',
              'duration': '4 menit',
              'icon': '💬'
            }, onTap: () => go(e))),
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
            subtitle:
                'Amati gerakan peraga, lalu coba praktikkan dengan nyaman.'),
        VideoPlaceholder(title: title),
        TextButton.icon(
            onPressed: () => go('Video demonstrasi bahasa isyarat'),
            icon: const Icon(Icons.ondemand_video_rounded),
            label: const Text('Buka halaman video')),
        const SizedBox(height: 12),
        const PageHeading('Yang akan kamu pelajari'),
        const SoftCard(
            child: Text(
                'Perhatikan bentuk tangan dan arah gerak secara utuh. Setiap video pada demo ini adalah placeholder yang menunggu rekaman peraga autentik BISINDO.')),
        const SizedBox(height: 20),
        PrimaryButton('Latih gerakan ini',
            onPressed: () => go('Instruksi praktik'),
            icon: Icons.front_hand_rounded),
        TextButton(
            onPressed: () => go('Kuis materi'),
            child: const Text('Coba kuis materi'))
      ]));
  Widget _video(BuildContext context) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeading('Video demonstrasi',
            subtitle: 'Video peraga akan ditambahkan pada tahap berikutnya.'),
        const VideoPlaceholder(title: 'Materi BISINDO'),
        const SizedBox(height: 18),
        const LabelChip('PLACEHOLDER VIDEO'),
        const SizedBox(height: 12),
        const Text(
            'Belajar dengan mengamati gerakan peraga dari beberapa sudut. Belum ada rekaman autentik pada demo UI ini.'),
        const SizedBox(height: 22),
        PrimaryButton('Praktikkan gerakan',
            onPressed: () => go('Instruksi praktik'))
      ]));
  Widget _alphabet(BuildContext context) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeading('Belajar alfabet BISINDO',
            subtitle: 'Pilih huruf untuk melihat materi dan video peraga.'),
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
            subtitle: 'Kumpulan kata BISINDO untuk kebutuhan sehari-hari.'),
        if (title == 'Pembelajaran kosakata')
          ...SampleData.words.map((e) => LessonTile(item: {
                'title': e,
                'category': 'BISINDO',
                'duration': 'Video peraga',
                'icon': '💬'
              }, onTap: () => go(e)))
        else ...[
          VideoPlaceholder(title: title),
          const SizedBox(height: 18),
          const LabelChip('KOSAKATA BISINDO'),
          const SizedBox(height: 14),
          const Text(
              'Amati bentuk dan gerakan tangan dari video peraga. Gunakan latihan untuk mencoba gerakan ini.'),
          const SizedBox(height: 22),
          PrimaryButton('Latihan kata ini',
              onPressed: () => go('Instruksi praktik'))
        ]
      ]));
  Widget _sentences(BuildContext context) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeading('Kalimat sederhana',
            subtitle: 'Rangkai kosakata menjadi pesan yang mudah dipahami.'),
        ...[
          'Nama saya Yohanes',
          'Apa kabar?',
          'Saya ingin belajar',
          'Terima kasih banyak'
        ].map((e) => LessonTile(item: {
              'title': e,
              'category': 'Kalimat BISINDO',
              'duration': '6 menit',
              'icon': '📝'
            }, onTap: () => go(e))),
        PrimaryButton('Simulasi percakapan',
            onPressed: () => go('Simulasi percakapan'))
      ]));
  Widget _conversation(BuildContext context) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeading('Skenario: di kafe',
            subtitle: 'Amati percakapan terarah dengan video peraga.'),
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
              'Kamu ingin memesan minuman dan menyampaikan pilihan kepada barista. Pelajari frasa yang digunakan satu per satu.')
        ])),
        const SizedBox(height: 20),
        PrimaryButton('Pelajari frasa percakapan',
            onPressed: () => go('Daftar lesson')),
        TextButton(
            onPressed: () => go('Detail skenario percakapan'),
            child: const Text('Lihat detail skenario'))
      ]));
  Widget _practiceInstructions(BuildContext context) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const LabelChip('LATIHAN DEMO'),
        const SizedBox(height: 14),
        const PageHeading('Siapkan latihanmu',
            subtitle: 'Pilih gerakan yang baru saja kamu pelajari.'),
        const SoftCard(
            color: GesturaTheme.mint,
            child: Row(children: [
              Text('👋', style: TextStyle(fontSize: 34)),
              SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Gerakan: Halo',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: GesturaTheme.ink)),
                    Text('Berdiri nyaman dan pastikan tangan terlihat jelas.')
                  ]))
            ])),
        const SizedBox(height: 18),
        const Text('Tips sebelum mulai',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 10),
        const Text(
            '• Cari tempat dengan cahaya cukup\n• Letakkan tangan di dalam area kamera\n• Ikuti gerakan dari materi video'),
        const SizedBox(height: 22),
        PrimaryButton('Buka kamera latihan',
            onPressed: () => go('Kamera praktik'),
            icon: Icons.camera_alt_rounded),
        const SizedBox(height: 8),
        const Center(
            child: Text('Hasil pengenalan adalah simulasi UI',
                style: TextStyle(color: GesturaTheme.muted, fontSize: 12)))
      ]));
  Widget _camera(BuildContext context) => _wrap(Column(children: [
        const PageHeading('Kamera latihan',
            subtitle: 'Arahkan tangan ke dalam area panduan.'),
        Container(
            height: 310,
            width: double.infinity,
            decoration: BoxDecoration(
                color: GesturaTheme.tealDark,
                borderRadius: BorderRadius.circular(24)),
            child: Stack(alignment: Alignment.center, children: [
              const Positioned(
                  top: 16,
                  left: 16,
                  child:
                      LabelChip('PREVIEW SIMULASI', color: Color(0xFFD8EFE3))),
              Container(
                  width: 190,
                  height: 220,
                  decoration: BoxDecoration(
                      border: Border.all(color: GesturaTheme.yellow, width: 2),
                      borderRadius: BorderRadius.circular(24)),
                  child: const Center(
                      child: Icon(Icons.front_hand_rounded,
                          size: 78, color: Colors.white38))),
              const Positioned(
                  bottom: 18,
                  child: Text('Preview kamera belum diaktifkan',
                      style: TextStyle(color: Colors.white70, fontSize: 12)))
            ])),
        const SizedBox(height: 16),
        const SoftCard(
            child: Row(children: [
          Icon(Icons.info_outline, color: GesturaTheme.teal),
          SizedBox(width: 10),
          Expanded(
              child: Text(
                  'Tidak ada gambar yang direkam. Tombol di bawah menjalankan hasil latihan demo.'))
        ])),
        const SizedBox(height: 18),
        PrimaryButton('Periksa gerakan',
            onPressed: () => go('Hasil pengenalan gerakan'),
            icon: Icons.center_focus_strong_rounded)
      ]));
  Widget _result(BuildContext context, String title) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Center(
            child: CircleAvatar(
                radius: 40,
                backgroundColor: GesturaTheme.mint,
                child: Icon(Icons.check_rounded,
                    size: 42, color: GesturaTheme.teal))),
        const SizedBox(height: 18),
        PageHeading(
            title == 'Hasil latihan' ? 'Latihan selesai' : 'Gerakan cocok!',
            subtitle: 'Simulasi pengenalan • bukan hasil Computer Vision'),
        SoftCard(
            color: const Color(0xFFE2F4EF),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const LabelChip('HASIL SIMULASI'),
              const SizedBox(height: 12),
              Text('Prediksi: Halo',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('Status gerakan: Cocok',
                  style: TextStyle(
                      color: GesturaTheme.tealDark,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const Text(
                  'Bagus! Tangan sudah berada di area yang terlihat. Terus amati video peraga untuk menyempurnakan gerakan.')
            ])),
        const SizedBox(height: 20),
        PrimaryButton('Ulangi latihan',
            onPressed: () => go('Kamera praktik'), icon: Icons.replay_rounded),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kembali ke materi'))
      ]));
  Widget _quiz(BuildContext context) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeading('Kuis: salam dan sapaan',
            subtitle: 'Pilih jawaban yang paling sesuai.'),
        const LabelChip('PERTANYAAN 1 DARI 3'),
        const SizedBox(height: 16),
        const Text(
            'Apa yang sebaiknya kamu lakukan sebelum menirukan gerakan dari video?',
            style: TextStyle(
                fontSize: 19,
                color: GesturaTheme.ink,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        ...[
          'Amati bentuk dan arah gerakan',
          'Menebak tanpa melihat',
          'Menutup tangan dari kamera'
        ].map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SoftCard(
                onTap: () => go('Hasil kuis'),
                child: Row(children: [
                  const Icon(Icons.radio_button_off, color: GesturaTheme.teal),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(e,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: GesturaTheme.ink)))
                ])))),
        const SizedBox(height: 12),
        PrimaryButton('Lihat hasil kuis', onPressed: () => go('Hasil kuis'))
      ]));
  Widget _quizResult(BuildContext context) => _wrap(Column(children: [
        const Icon(Icons.task_alt_rounded, size: 70, color: GesturaTheme.teal),
        const SizedBox(height: 14),
        const PageHeading('Kuis selesai', subtitle: 'Jawaban benar: 2 dari 3'),
        const SoftCard(
            child: Text(
                'Terus belajar dan ulangi materi yang masih ingin kamu kuasai. Progres belajar tidak menggunakan poin atau hadiah.')),
        const SizedBox(height: 20),
        PrimaryButton('Ulangi kuis', onPressed: () => go('Kuis materi')),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kembali ke materi'))
      ]));
  Widget _confirm(BuildContext context, String title) =>
      _wrap(Column(children: [
        const SizedBox(height: 38),
        CircleAvatar(
            radius: 38,
            backgroundColor: const Color(0xFFFFF1D2),
            child: Icon(
                title.contains('logout') ? Icons.logout : Icons.delete_outline,
                color: GesturaTheme.teal,
                size: 34)),
        const SizedBox(height: 20),
        PageHeading(title,
            subtitle: title.contains('logout')
                ? 'Kamu bisa masuk kembali untuk melanjutkan progres demo.'
                : 'Penghapusan akun hanya simulasi. Tidak ada data yang benar-benar dihapus.'),
        PrimaryButton(
            title.contains('logout')
                ? 'Keluar dari akun demo'
                : 'Saya mengerti', onPressed: () {
          if (title.contains('logout')) {
            widget.onLogout();
          } else {
            Navigator.pop(context);
          }
        }),
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Batal'))
      ]));
  Widget _settings(BuildContext context, String title) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeading(title,
            subtitle: 'Preferensi ini tersimpan sementara selama sesi demo.'),
        if (title == 'Pengaturan notifikasi') ...[
          _switch('Pengingat materi baru'),
          _switch('Pembaruan akun'),
          _switch('Tips belajar')
        ],
        if (title == 'Pengaturan tampilan') ...[
          _switch('Kurangi animasi'),
          _switch('Gunakan tampilan kontras tinggi'),
          ListTile(
              title: const Text('Ukuran teks'),
              subtitle: const Text('Standar'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ukuran teks: standar'))))
        ],
        if (title == 'Pengaturan kamera dan izin') ...[
          const SoftCard(
              child: Text(
                  'Status kamera\nKamera belum dihubungkan. Saat fitur diaktifkan, izin kamera akan diminta sebelum latihan.',
                  style: TextStyle(height: 1.5))),
          const SizedBox(height: 14),
          _switch('Izinkan kamera untuk latihan'),
          _switch('Tampilkan panduan area tangan')
        ]
      ]));
  Widget _switch(String label) => StatefulBuilder(
      builder: (context, setLocal) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: settingsValues[label] ?? true,
          activeThumbColor: GesturaTheme.teal,
          onChanged: (v) {
            settingsValues[label] = v;
            setLocal(() {});
          }));
  Widget _formPage(BuildContext context, String title) {
    return _wrap(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeading(title,
          subtitle: 'Perubahan disimulasikan dan tidak dikirim ke server.'),
      if (title == 'Edit profil') ...[
        const Text('Nama lengkap'),
        const SizedBox(height: 8),
        TextFormField(
            initialValue: 'Yohanes Putra',
            decoration:
                const InputDecoration(prefixIcon: Icon(Icons.person_outline))),
        const SizedBox(height: 16),
        const Text('Email'),
        const SizedBox(height: 8),
        TextFormField(
            initialValue: 'yohanes@email.com',
            decoration:
                const InputDecoration(prefixIcon: Icon(Icons.mail_outline)))
      ],
      if (title == 'Ubah email') ...[
        const Text('Email baru'),
        const SizedBox(height: 8),
        TextField(
            controller: formController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'email@contoh.com'))
      ],
      if (title == 'Ubah password') ...[
        for (final x in [
          'Password saat ini',
          'Password baru',
          'Ulangi password baru'
        ]) ...[
          Text(x),
          const SizedBox(height: 8),
          const TextField(
              obscureText: true,
              decoration: InputDecoration(hintText: 'Minimal 8 karakter')),
          const SizedBox(height: 14)
        ]
      ],
      if (title == 'Pengaturan akun')
        ...['Ubah password', 'Ubah email', 'Konfirmasi hapus akun']
            .map((e) => SettingsMenuRow(e, onTap: () => go(e))),
      if (title == 'Kirim masukan') ...[
        const Text('Ceritakan pengalamanmu'),
        const SizedBox(height: 8),
        const TextField(
            maxLines: 5,
            decoration: InputDecoration(hintText: 'Tulis masukan di sini...'))
      ],
      const SizedBox(height: 22),
      PrimaryButton('Simpan perubahan', onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Perubahan disimpan untuk demo ini.')));
        Navigator.pop(context);
      })
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
                  'Gestura • Versi demo UI 1.0\nDibuat sebagai media belajar BISINDO. Materi video peraga dan fitur pengenalan gerakan akan dikembangkan pada tahap berikutnya.'))
        else
          ...[
            'Apa itu BISINDO?',
            'Apakah pengenalan kamera sudah aktif?',
            'Bagaimana cara memulai belajar?'
          ].map((e) => ExpansionTile(title: Text(e), children: const [
                Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'Demo Gestura menyediakan pembelajaran visual secara bertahap. Fitur video dan pengenalan akan menggunakan materi autentik saat tersedia.'))
              ]))
      ]));
  Widget _history(BuildContext context) =>
      _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeading('Riwayat belajar',
            subtitle: 'Ringkasan materi yang pernah kamu buka.'),
        ...[...SampleData.lessons, ...SampleData.lessons.take(1)]
            .map((e) => LessonTile(item: e, onTap: () => go(e['title']!))),
        const SoftCard(
            color: GesturaTheme.mint,
            child: Text(
                '4 materi dipelajari • Riwayat ini menggunakan data demo.',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: GesturaTheme.tealDark)))
      ]));
}
