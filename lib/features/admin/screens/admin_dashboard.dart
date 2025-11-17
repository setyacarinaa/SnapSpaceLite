import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:snapspace/features/admin/screens/admin_booths_screen.dart';
import 'package:snapspace/features/admin/screens/admin_bookings_screen.dart';
import 'package:snapspace/features/admin/screens/admin_users_screen.dart';

class AdminDashboard extends StatefulWidget {
  final String role;
  const AdminDashboard({super.key, this.role = 'system_admin'});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _index = 0;
  late final List<_Tab> pages;

  @override
  void initState() {
    super.initState();
    if (widget.role == 'photobooth_admin') {
      pages = const [
        _Tab(title: 'Booths', child: AdminBoothsScreen()),
        _Tab(title: 'Bookings', child: AdminBookingsScreen()),
      ];
    } else {
      pages = const [
        _Tab(title: 'Booths', child: AdminBoothsScreen()),
        _Tab(title: 'Bookings', child: AdminBookingsScreen()),
        _Tab(title: 'Users', child: AdminUsersScreen()),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = pages[_index];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4981CF),
        title: Text(
          'Admin • ${tab.title}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: tab.child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        selectedItemColor: const Color(0xFF4981CF),
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_camera_front_outlined),
            label: 'Booths',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_note_outlined),
            label: 'Bookings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            label: 'Users',
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ListTile(
                title: Text(
                  'SnapSpace Admin',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Panel kontrol'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Kembali ke Aplikasi'),
                onTap: () => Navigator.popUntil(context, (r) => r.isFirst),
              ),
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: const Text('Verifikasi Admin Photobooth'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamed('/admin/verify');
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  try {
                    await FirebaseAuth.instance.signOut();
                  } finally {
                    if (!mounted) return;
                    // Close drawer first
                    Navigator.of(context).pop();
                    // Clear stack and go to Splash (which leads to Login)
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/splash', (route) => false);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String title;
  final Widget child;
  const _Tab({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
