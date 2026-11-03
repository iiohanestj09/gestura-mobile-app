import 'package:flutter/material.dart';
import '../../core/gestura_theme.dart';
import '../../data/sample_data.dart';
import '../../data/firebase_service.dart';
import '../../data/gesture_api_service.dart';
import '../../widgets/gestura_widgets.dart';
import '../details/detail_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.onLogout, super.key});
  final Future<void> Function() onLogout;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
      body: IndexedStack(index: index, children: [
        HomeTab(onOpen: open),
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
                label: 'Beranda'),
            NavigationDestination(
                icon: Icon(Icons.front_hand_outlined),
                selectedIcon: Icon(Icons.front_hand_rounded),
                label: 'Latihan'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Akun')
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Selamat pagi,',
                        style: TextStyle(color: GesturaTheme.muted)),
                    const SizedBox(height: 3),
                    StreamBuilder<Map<String, dynamic>?>(
                      stream: FirebaseService.watchProfile(),
                      builder: (context, snapshot) {
                        final profileName =
                            snapshot.data?['displayName'] as String?;
                        final name = profileName?.trim().isNotEmpty == true
                            ? profileName!.trim()
                            : FirebaseService.currentUser?.displayName
                                    ?.trim() ??
                                '';
                        final firstName = name.isEmpty
                            ? 'teman'
                            : name.split(RegExp(r'\s+')).first;
                        return Text('$firstName 👋',
                            style: Theme.of(context).textTheme.headlineSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis);
                      },
                    ),
                  ],
                ),
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

  Widget _continueLearning(BuildContext context) => StreamBuilder<bool>(
        stream: FirebaseService.watchLessonCompleted('Salam dan sapaan'),
        builder: (context, snapshot) {
          final progress = snapshot.data == true ? 1.0 : 0.0;
          final percent = (progress * 100).round();
          return Container(
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
                Text(
                    snapshot.hasError
                        ? 'Progres tidak dapat dimuat'
                        : snapshot.data == true
                            ? 'Materi selesai'
                            : 'Kosakata BISINDO • Materi',
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 17),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 7,
                          backgroundColor: Colors.white24,
                          color: GesturaTheme.yellow,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('$percent%',
                        style: const TextStyle(
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
        },
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
                          ? '9 angka'
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

class PracticeTab extends StatefulWidget {
  const PracticeTab({required this.onOpen, super.key});
  final void Function(String) onOpen;

  @override
  State<PracticeTab> createState() => _PracticeTabState();
}

class _PracticeTabState extends State<PracticeTab> {
  GestureCategory? selectedCategory;

  void _openTarget(GestureCategory category, String target) {
    widget.onOpen('Kamera praktik|${category.apiValue}|$target');
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            if (selectedCategory == null) ...[
              const PageHeading(
                'Pilih latihan',
                subtitle: 'Pilih kategori yang ingin kamu latih.',
              ),
              _categoryCard(
                context,
                category: GestureCategory.alphabet,
                icon: Icons.back_hand_rounded,
                subtitle: 'Latihan huruf A sampai Z',
                color: GesturaTheme.mint,
              ),
              const SizedBox(height: 12),
              _categoryCard(
                context,
                category: GestureCategory.vocabulary,
                icon: Icons.chat_bubble_rounded,
                subtitle: '32 kosakata BISINDO',
                color: const Color(0xFFFFF1D2),
              ),
              const SizedBox(height: 12),
              _categoryCard(
                context,
                category: GestureCategory.digit,
                icon: Icons.pin_rounded,
                subtitle: 'Latihan angka 1 sampai 9',
                color: const Color(0xFFEDE7FF),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () => widget.onOpen('Riwayat latihan'),
                icon: const Icon(Icons.history_rounded),
                label: const Text('Lihat riwayat latihan'),
              ),
            ] else ...[
              TextButton.icon(
                onPressed: () => setState(() => selectedCategory = null),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Semua kategori'),
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              ),
              PageHeading(
                selectedCategory!.displayName,
                subtitle: 'Pilih target untuk memulai latihan.',
              ),
              if (selectedCategory == GestureCategory.alphabet)
                _alphabetTargets()
              else if (selectedCategory == GestureCategory.digit)
                _digitTargets()
              else
                _vocabularyTargets(),
            ],
          ],
        ),
      );

  Widget _categoryCard(
    BuildContext context, {
    required GestureCategory category,
    required IconData icon,
    required String subtitle,
    required Color color,
  }) =>
      SoftCard(
        color: color,
        onTap: () => setState(() => selectedCategory = category),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .8),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(icon, color: GesturaTheme.tealDark, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(color: GesturaTheme.muted)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: GesturaTheme.tealDark),
          ],
        ),
      );

  Widget _alphabetTargets() => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: GestureCategory.alphabet.labels.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.15,
        ),
        itemBuilder: (context, index) {
          final label = GestureCategory.alphabet.labels[index];
          return SoftCard(
            color: Colors.white,
            padding: EdgeInsets.zero,
            onTap: () => _openTarget(GestureCategory.alphabet, label),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: GesturaTheme.tealDark,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );
        },
      );

  Widget _digitTargets() => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: GestureCategory.digit.labels.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
        ),
        itemBuilder: (context, index) {
          final label = GestureCategory.digit.labels[index];
          return SoftCard(
            color: const Color(0xFFEDE7FF),
            padding: EdgeInsets.zero,
            onTap: () => _openTarget(GestureCategory.digit, label),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: GesturaTheme.tealDark,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );
        },
      );

  Widget _vocabularyTargets() => Column(
        children: GestureCategory.vocabulary.labels
            .map(
              (label) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LessonTile(
                  item: {
                    'title': label,
                    'category': 'Kosakata BISINDO',
                    'duration': 'Latihan gerakan',
                    'icon': '💬',
                  },
                  onTap: () => _openTarget(GestureCategory.vocabulary, label),
                ),
              ),
            )
            .toList(growable: false),
      );
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({required this.onOpen, super.key});
  final void Function(String) onOpen;
  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, dynamic>?>(
      stream: FirebaseService.watchProfile(),
      builder: (context, profileSnapshot) {
        final user = FirebaseService.currentUser;
        final savedName = profileSnapshot.data?['displayName'] as String?;
        final name = savedName?.trim().isNotEmpty == true
            ? savedName!.trim()
            : user?.displayName?.trim().isNotEmpty == true
                ? user!.displayName!.trim()
                : 'Pengguna Gestura';
        final email =
            profileSnapshot.data?['email'] as String? ?? user?.email ?? '';
        return StreamBuilder<List<Map<String, dynamic>>>(
            stream: FirebaseService.watchProgress(),
            builder: (context, snapshot) {
              final progressItems = snapshot.data ?? const [];
              final completedLessons =
                  progressItems.where((item) => item['kind'] != 'quiz').length;
              final completedQuizzes =
                  progressItems.where((item) => item['kind'] == 'quiz').length;
              return SafeArea(
                  child: ListView(padding: const EdgeInsets.all(20), children: [
                const PageHeading('Akun saya'),
                SoftCard(
                    child: Row(children: [
                  CircleAvatar(
                      radius: 32,
                      backgroundColor: GesturaTheme.mint,
                      child: Text(_initials(name),
                          style: const TextStyle(
                              color: GesturaTheme.teal,
                              fontWeight: FontWeight.w900,
                              fontSize: 20))),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: GesturaTheme.ink)),
                        Text(email,
                            style: const TextStyle(
                                color: GesturaTheme.muted, fontSize: 13))
                      ])),
                  IconButton(
                      onPressed: () => onOpen('Edit profil'),
                      icon: const Icon(Icons.edit_outlined))
                ])),
                const SizedBox(height: 14),
                SoftCard(
                    color: const Color(0xFFFFF1D2),
                    child: Row(children: [
                      const Icon(Icons.auto_stories_rounded,
                          color: GesturaTheme.teal),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(
                              snapshot.hasError
                                  ? 'Progres gagal dimuat.\n${snapshot.error}'
                                  : snapshot.connectionState ==
                                          ConnectionState.waiting
                                      ? 'Memuat progres belajar...'
                                      : '$completedLessons materi selesai • '
                                          '$completedQuizzes kuis selesai\n'
                                          'Progres belajarmu tersimpan di Firestore.',
                              style: const TextStyle(
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
            });
      });
}

String _initials(String name) {
  final parts = name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}
