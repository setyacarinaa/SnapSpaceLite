import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:snapspace/features/admin_photobooth/screens/admin_booths_screen.dart';
import 'package:snapspace/features/admin_photobooth/screens/admin_bookings_screen.dart';
import 'package:snapspace/features/admin_system/screens/admin_users_screen.dart';

class AdminDashboard extends StatefulWidget {
  final String role;
  const AdminDashboard({super.key, this.role = 'system_admin'});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _index = 0;
  late final List<_Tab> pages;

  String? _userName;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();

    pages = widget.role == 'photobooth_admin'
        ? const [
            _Tab(title: 'Booths', child: AdminBoothsScreen()),
            _Tab(title: 'Bookings', child: AdminBookingsScreen()),
          ]
        : const [
            _Tab(title: 'Booths', child: AdminBoothsScreen()),
            _Tab(title: 'Bookings', child: AdminBookingsScreen()),
            _Tab(title: 'Users', child: AdminUsersScreen()),
          ];

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _startUserListener(user.uid, user.displayName);
    } else {
      _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
        if (u != null) _startUserListener(u.uid, u.displayName);
      });
    }
  }

  void _startUserListener(String uid, String? fallbackName) {
    _userSub?.cancel();
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
          if (!mounted) return;
          setState(() {
            _userName = (doc.data()?['name'] as String?) ?? fallbackName ?? '';
          });
        });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = pages[_index];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4981CF),
        title: _index == 0
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _userName != null && _userName!.isNotEmpty
                        ? 'Hi, $_userName'
                        : 'SnapSpace Admin',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  Text(
                    'Admin • ${tab.title}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            : Text(
                'Admin • ${tab.title}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
      body: tab.child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index.clamp(0, pages.length - 1),
        selectedItemColor: const Color(0xFF4981CF),
        onTap: (i) => setState(() => _index = i),
        items: pages.map((p) {
          // Map page title to appropriate icon
          final title = p.title.toLowerCase();
          IconData icon = Icons.folder_open;
          if (title.contains('booth')) icon = Icons.photo_camera_front_outlined;
          if (title.contains('book')) icon = Icons.event_note_outlined;
          if (title.contains('user')) icon = Icons.people_outline;
          return BottomNavigationBarItem(icon: Icon(icon), label: p.title);
        }).toList(),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                title: const Text(
                  'SnapSpace Admin',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Panel kontrol'),
              ),
              const Divider(),
              if (widget.role == 'system_admin')
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
                  await FirebaseAuth.instance.signOut();
                  if (!mounted) return;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    Navigator.of(context).pop();
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/splash', (route) => false);
                  });
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
