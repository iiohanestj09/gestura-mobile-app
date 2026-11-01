import 'package:flutter/material.dart';
import '../../core/gestura_theme.dart';
import '../../data/sample_data.dart';
import '../../widgets/gestura_widgets.dart';
import '../details/detail_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.onLogout, super.key});
  final VoidCallback onLogout;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
      body: IndexedStack(index: index, children: [
        HomeTab(onOpen: open),
        LearnTab(onOpen: open),
        PracticeTab(onOpen: open),
        ProfileTab(onOpen: open)
      ]),
      bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => index = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book_rounded),
                label: 'Belajar'),
            NavigationDestination(
                icon: Icon(Icons.front_hand_outlined),
                selectedIcon: Icon(Icons.front_hand_rounded),
                label: 'Latihan'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profil')
          ]));
  void open(String title) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => DetailPage(
              title: title, onOpen: open, onLogout: widget.onLogout)));
}

class HomeTab extends StatelessWidget {
  const HomeTab({required this.onOpen, super.key});

  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Selamat pagi,',
                      style: TextStyle(color: GesturaTheme.muted)),
                  const SizedBox(height: 3),
                  Text('Yohanes 👋',
                      style: Theme.of(context).textTheme.headlineSmall),
                ],
              ),
              IconButton.filledTonal(
                onPressed: () => onOpen('Notifikasi'),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _searchBar(),
          const SizedBox(height: 22),
          _continueLearning(context),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Jelajahi kategori',
                  style: Theme.of(context).textTheme.titleLarge),
              TextButton(
                onPressed: () => onOpen('Kategori pembelajaran'),
                child: const Text('Lihat semua'),
              ),
            ],
          ),
          _categoryGrid(context),
          const SizedBox(height: 22),
          Text('Untuk kamu', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...SampleData.lessons.take(2).map(
                (item) =>
                    LessonTile(item: item, onTap: () => onOpen(item['title']!)),
              ),
        ],
      ),
    );
  }

  Widget _searchBar() => InkWell(
        onTap: () => onOpen('Cari materi'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: GesturaTheme.border),
            boxShadow: [
              BoxShadow(
                  color: GesturaTheme.tealDark.withValues(alpha: .05),
                  blurRadius: 14,
                  offset: const Offset(0, 6))
            ],
          ),
          child: const Row(
            children: [
              Icon(Icons.search_rounded, color: GesturaTheme.muted),
              SizedBox(width: 10),
              Text('Cari materi BISINDO...',
                  style: TextStyle(color: GesturaTheme.muted)),
            ],
          ),
        ),
      );

  Widget _continueLearning(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF815CE4), Color(0xFF4B2B91)]),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                  color: GesturaTheme.tealDark.withValues(alpha: .25),
                  blurRadius: 24,
                  offset: const Offset(0, 12))
            ]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LabelChip('LANJUTKAN BELAJAR', color: Color(0xFFF0E9FF)),
            const SizedBox(height: 14),
            const Text('Salam dan sapaan',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            const Text('Kosakata • 5 menit',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 17),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: const LinearProgressIndicator(
                      value: .45,
                      minHeight: 7,
                      backgroundColor: Colors.white24,
                      color: GesturaTheme.yellow,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('45%',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => onOpen('Salam dan sapaan'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Lanjutkan materi  →'),
            ),
          ],
        ),
      );

  Widget _categoryGrid(BuildContext context) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: SampleData.categories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .82,
        ),
        itemBuilder: (context, index) {
          final category = SampleData.categories[index];
          return SoftCard(
            color: Color(category['color'] as int),
            onTap: () => onOpen(category['name'] as String),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (category['name'] == 'Alfabet')
                  const Icon(Icons.front_hand_rounded,
                      size: 28, color: GesturaTheme.tealDark)
                else if (category['name'] == 'Kosakata')
                  const Icon(Icons.chat_bubble_rounded,
                      size: 27, color: GesturaTheme.tealDark)
                else
                  const Text('123',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: GesturaTheme.tealDark)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(category['name'] as String,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontSize: 13)),
                    Text(
                      category['name'] == 'Angka'
                          ? '10 angka'
                          : category['count'] as String,
                      style: const TextStyle(
                          fontSize: 11, color: GesturaTheme.muted),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
}

class LearnTab extends StatelessWidget {
  const LearnTab({required this.onOpen, super.key});
  final void Function(String) onOpen;
  @override
  Widget build(BuildContext context) => SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        const PageHeading('Ruang belajar',
            subtitle: 'Pilih materi dan belajar dengan ritmemu.'),
        ...SampleData.courses.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SoftCard(
                onTap: () => onOpen(c),
                child: Row(children: [
                  Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                          color: GesturaTheme.mint,
                          borderRadius: BorderRadius.circular(17)),
                      child: const Icon(Icons.menu_book_rounded,
                          color: GesturaTheme.teal)),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(c, style: Theme.of(context).textTheme.titleMedium),
                        const Text('Kelas pemula • Materi bertahap')
                      ])),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 16)
                ])))),
        const SizedBox(height: 12),
        const PageHeading('Jalur belajar',
            subtitle: 'Alfabet → Kosakata → Angka BISINDO'),
        ...SampleData.categories.map((c) => LessonTile(item: {
              'title': c['name'] as String,
              'category': 'BISINDO',
              'duration':
                  c['name'] == 'Angka' ? '10 angka' : c['count'] as String,
              'icon': c['name'] == 'Angka' ? '123' : c['icon'] as String
            }, onTap: () => onOpen(c['name'] as String))),
        TextButton.icon(
            onPressed: () => onOpen('Riwayat belajar'),
            icon: const Icon(Icons.history),
            label: const Text('Lihat riwayat belajar'))
      ]));
}

class PracticeTab extends StatelessWidget {
  const PracticeTab({required this.onOpen, super.key});
  final void Function(String) onOpen;
  @override
  Widget build(BuildContext context) => SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        const PageHeading('Ruang latihan',
            subtitle: 'Latih gerakan dari materi yang sudah kamu pelajari.'),
        SoftCard(
            color: GesturaTheme.mint,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.front_hand_rounded,
                  color: GesturaTheme.teal, size: 34),
              const SizedBox(height: 13),
              Text('Siap mencoba?',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text(
                  'Pilih satu gerakan. Kamera dan pengenalan di sini masih simulasi.'),
              const SizedBox(height: 16),
              PrimaryButton('Mulai latihan',
                  onPressed: () => onOpen('Instruksi praktik'))
            ])),
        const SizedBox(height: 22),
        const PageHeading('Pilih materi latihan'),
        ...['Halo', 'Terima kasih', 'Huruf A'].map((e) => LessonTile(item: {
              'title': e,
              'category': 'Latihan BISINDO',
              'duration': 'Perlu 1 menit',
              'icon': '✋'
            }, onTap: () => onOpen(e))),
        const SizedBox(height: 10),
        TextButton.icon(
            onPressed: () => onOpen('Hasil latihan'),
            icon: const Icon(Icons.insights_rounded),
            label: const Text('Lihat ringkasan latihan terakhir'))
      ]));
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({required this.onOpen, super.key});
  final void Function(String) onOpen;
  @override
  Widget build(BuildContext context) => SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        const PageHeading('Profil saya'),
        SoftCard(
            child: Row(children: [
          const CircleAvatar(
              radius: 32,
              backgroundColor: GesturaTheme.mint,
              child: Text('YP',
                  style: TextStyle(
                      color: GesturaTheme.teal,
                      fontWeight: FontWeight.w900,
                      fontSize: 20))),
          const SizedBox(width: 14),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Yohanes Putra',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: GesturaTheme.ink)),
                Text('yohanes@email.com',
                    style: TextStyle(color: GesturaTheme.muted, fontSize: 13))
              ])),
          IconButton(
              onPressed: () => onOpen('Edit profil'),
              icon: const Icon(Icons.edit_outlined))
        ])),
        const SizedBox(height: 14),
        const SoftCard(
            color: Color(0xFFFFF1D2),
            child: Row(children: [
              Icon(Icons.auto_stories_rounded, color: GesturaTheme.teal),
              SizedBox(width: 12),
              Expanded(
                  child: Text(
                      '4 materi dipelajari\nProgres belajarmu tersimpan di perangkat ini.',
                      style: TextStyle(
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: GesturaTheme.ink)))
            ])),
        const SizedBox(height: 22),
        const PageHeading('Akun dan preferensi'),
        ...[
          'Edit profil',
          'Pengaturan akun',
          'Ubah password',
          'Ubah email',
          'Pengaturan notifikasi',
          'Pengaturan tampilan',
          'Pengaturan kamera dan izin',
          'Bantuan dan FAQ',
          'Kirim masukan',
          'Tentang Gestura',
          'Riwayat belajar'
        ].map((e) => SettingsMenuRow(e, onTap: () => onOpen(e))),
        const SizedBox(height: 10),
        SettingsMenuRow('Keluar',
            icon: Icons.logout_rounded,
            onTap: () => onOpen('Konfirmasi logout')),
        SettingsMenuRow('Hapus akun',
            icon: Icons.delete_outline_rounded,
            onTap: () => onOpen('Konfirmasi hapus akun'))
      ]));
}
