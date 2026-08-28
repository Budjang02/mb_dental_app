import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/theme_controller.dart';
import 'home_tab.dart';
import '../appointments/appointments_screen.dart';
import '../records/dental_records_screen.dart';
import '../wallet/wallet_screen.dart';
import '../profile/profile_screen.dart';

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

    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
        // Content runs underneath the bar so the translucent glass reads as a
        // floating pill instead of a solid docked footer. Each tab's scroll
        // view leaves room at the bottom so nothing hides behind it.
        extendBody: true,
        body: tabs[_selectedIndex],
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: DecoratedBox(
            // The shadow sits outside the clip so ClipRRect does not cut it off.
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // Kept well under half opacity so the content sliding
                    // beneath stays visible through the glass.
                    color: AppColors.surface.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.surface.withOpacity(0.55)),
                  ),
                  child: BottomNavigationBar(
                    currentIndex: _selectedIndex,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    selectedItemColor: AppColors.primary,
                    unselectedItemColor: AppColors.textSecondary,
                    type: BottomNavigationBarType.fixed,
                    selectedFontSize: 11,
                    unselectedFontSize: 10,
                    iconSize: 22,
                    onTap: _navigateToTab,
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(CupertinoIcons.house),
                        activeIcon: Icon(CupertinoIcons.house_fill),
                        label: 'Home',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(CupertinoIcons.calendar),
                        activeIcon: Icon(CupertinoIcons.calendar_today),
                        label: 'Schedule',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(CupertinoIcons.creditcard),
                        activeIcon: Icon(CupertinoIcons.creditcard_fill),
                        label: 'Wallet',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(CupertinoIcons.folder),
                        activeIcon: Icon(CupertinoIcons.folder_fill),
                        label: 'Records',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(CupertinoIcons.person),
                        activeIcon: Icon(CupertinoIcons.person_fill),
                        label: 'Profile',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
