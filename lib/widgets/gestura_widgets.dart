import 'package:flutter/material.dart';
import '../core/gestura_theme.dart';

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {this.subtitle, super.key});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium)
        ]
      ]));
}

class SoftCard extends StatelessWidget {
  const SoftCard(
      {required this.child,
      this.color = Colors.white,
      this.padding = const EdgeInsets.all(16),
      this.onTap,
      super.key});
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, Color.lerp(color, Colors.white, .32)!],
          ),
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: .82)),
          boxShadow: [
            BoxShadow(
              color: GesturaTheme.tealDark.withValues(alpha: .07),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.label,
      {required this.onPressed, this.icon, super.key});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.arrow_forward_rounded),
      label: Text(label));
}

class VideoPlaceholder extends StatelessWidget {
  const VideoPlaceholder({required this.title, super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Container(
        height: 190,
        decoration: BoxDecoration(
            color: GesturaTheme.tealDark,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: GesturaTheme.tealDark.withValues(alpha: .22),
                  blurRadius: 22,
                  offset: const Offset(0, 12))
            ]),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.video_library_outlined,
                  size: 42, color: Colors.white70),
              const SizedBox(height: 12),
              const Text('VIDEO PERAGA BELUM TERSEDIA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
        ),
      );
}

class LabelChip extends StatelessWidget {
  const LabelChip(this.label, {this.color = GesturaTheme.mint, super.key});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: const TextStyle(
              color: GesturaTheme.tealDark,
              fontSize: 11,
              fontWeight: FontWeight.w800)));
}

class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 46, super.key});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: GesturaTheme.yellow,
          borderRadius: BorderRadius.circular(size * .34)),
      child: Icon(Icons.waving_hand_rounded,
          size: size * .58, color: GesturaTheme.tealDark));
}

class LessonTile extends StatelessWidget {
  const LessonTile({required this.item, required this.onTap, super.key});
  final Map<String, String> item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
          onTap: onTap,
          child: Row(children: [
            Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: GesturaTheme.mint,
                    borderRadius: BorderRadius.circular(16)),
                child: Text(item['icon'] ?? '✋',
                    style: const TextStyle(fontSize: 23))),
            const SizedBox(width: 13),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(item['title']!,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text('${item['category']} • ${item['duration']}',
                      style: Theme.of(context).textTheme.bodyMedium)
                ])),
            const Icon(Icons.chevron_right_rounded, color: GesturaTheme.muted)
          ])));
}

class SettingsMenuRow extends StatelessWidget {
  const SettingsMenuRow(this.title,
      {required this.onTap,
      this.icon = Icons.chevron_right_rounded,
      super.key});
  final String title;
  final VoidCallback onTap;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(_settingsMenuIcon(title), color: GesturaTheme.teal),
      title: Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.w600, color: GesturaTheme.ink)),
      trailing: Icon(icon, size: 19, color: GesturaTheme.muted),
      onTap: onTap);
}

IconData _settingsMenuIcon(String title) => switch (title) {
      'Edit profil' => Icons.person_outline,
      'Pengaturan akun' => Icons.manage_accounts_outlined,
      'Ubah password' => Icons.lock_outline,
      'Ubah email' => Icons.mail_outline,
      'Pengaturan notifikasi' => Icons.notifications_none,
      'Pengaturan tampilan' => Icons.palette_outlined,
      'Pengaturan kamera dan izin' => Icons.camera_alt_outlined,
      'Bantuan dan FAQ' => Icons.help_outline,
      'Kirim masukan' => Icons.chat_bubble_outline,
      'Tentang Gestura' => Icons.info_outline,
      'Riwayat belajar' => Icons.history,
      _ => Icons.chevron_right
    };
