import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/theme_controller.dart';
import 'home_tab.dart';
import '../appointments/appointments_screen.dart';
import '../records/dental_records_screen.dart';
import '../wallet/wallet_screen.dart';
import '../profile/profile_screen.dart';
import '../../widgets/app_icons.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  void _navigateToTab(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeTab(onNavigateToTab: _navigateToTab),
      const AppointmentsScreen(),
      const WalletScreen(),
      const DentalRecordsScreen(),
      const ProfileScreen(),
    ];

    // Read outside the Scaffold: a Scaffold rewrites the padding it hands to
    // its body, so asking in there would give the wrong gesture-bar inset.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.background,
        // The bar is laid over the page in a Stack rather than handed to
        // Scaffold's bottomNavigationBar slot. That slot reserves a strip of
        // its own across the full width of the screen, and whatever the strip
        // is painted with shows up as a band behind the pill — the pill stops
        // reading as floating. In a Stack there is nothing behind it but the
        // page itself, on all four sides.
        body: Stack(
          children: [
            // Each tab's scroll view already leaves room at the bottom, so
            // running the page full height hides nothing behind the pill.
            Positioned.fill(child: tabs[_selectedIndex]),
            Positioned(
              left: 18,
              right: 18,
              bottom: bottomInset + 14,
              child: _FloatingNavBar(
                currentIndex: _selectedIndex,
                onTap: _navigateToTab,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The floating navigation pill. Built by hand rather than from
/// [BottomNavigationBar] so it stays a single opaque surface with rounded
/// corners — no Material canvas, divider or elevation overlay behind it.
class _FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _FloatingNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        // One soft shadow, pulled in tight. A wide, heavy blur spills past the
        // pill's rounded ends and paints a dim slab right across the bottom of
        // the page — which is the thing that stops the pill reading as
        // floating. The negative spread keeps the falloff inside the pill's
        // own footprint so there is nothing behind it but the page.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: -6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: Row(
            // Outline, rounded glyphs throughout — the active tab is marked
            // by colour, not by swapping in a filled icon.
            children: [
              _navItem(0, AppIconGlyph.home, 'Home'),
              _navItem(1, AppIconGlyph.calendar, 'Schedule'),
              _navItem(2, AppIconGlyph.wallet, 'Wallet'),
              _navItem(3, AppIconGlyph.records, 'Records'),
              _navItem(4, AppIconGlyph.person, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, AppIconGlyph glyph, String label) {
    return Expanded(
      child: Builder(
        builder: (context) {
          final selected = currentIndex == index;
          final color = selected ? AppColors.primary : AppColors.textSecondary;
          return InkWell(
            onTap: () => onTap(index),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(
                  glyph: glyph,
                  color: color,
                  size: 22,
                  // The selected tab thickens rather than filling in,
                  // keeping every glyph a linear outline.
                  weight: selected ? 0.10 : 0.085,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
