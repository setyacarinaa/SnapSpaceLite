import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/admin_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
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
        ? [
            _Tab(title: 'Booths', child: AdminBoothsScreen()),
            _Tab(title: 'Bookings', child: AdminBookingsScreen()),
          ]
        : [
            _Tab(title: 'Booths', child: AdminBoothsScreen()),
            _Tab(title: 'Bookings', child: AdminBookingsScreen()),
            _Tab(
              title: 'Users',
              child: AdminUsersScreen(role: widget.role),
            ),
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
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              final rootNav = Navigator.of(context, rootNavigator: true);
              try {
                await FirebaseAuth.instance.signOut();
              } catch (_) {}
              if (!mounted) return;
              try {
                Fluttertoast.showToast(msg: 'Berhasil logout');
              } catch (_) {}
              rootNav.pushNamedAndRemoveUntil('/splash', (route) => false);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // If the current signed-in user is the special system admin
            // and they're viewing the dashboard as another role, show
            // a small banner so the operator knows they're in act-as mode.
            if (FirebaseAuth.instance.currentUser?.email ==
                    AdminConfig.systemAdminEmail &&
                widget.role != 'system_admin')
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 8.0,
                ),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.yellow.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.yellow.shade700),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.visibility,
                        color: Colors.black54,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Anda sedang melihat sebagai "${widget.role}" (act-as mode)',
                          style: const TextStyle(color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (widget.role == 'system_admin' && tab.title != 'Users')
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FutureBuilder<List<int>>(
                          future: Future.wait<int>([
                            // approved photobooth
                            FirebaseFirestore.instance
                                .collection('users')
                                .where('role', isEqualTo: 'photobooth_admin')
                                .where('verified', isEqualTo: true)
                                .get()
                                .then((q) => q.docs.length),
                            // pending photobooth
                            FirebaseFirestore.instance
                                .collection('users')
                                .where('role', isEqualTo: 'photobooth_admin')
                                .where('verified', isEqualTo: false)
                                .get()
                                .then((q) => q.docs.length),
                            // customers total
                            FirebaseFirestore.instance
                                .collection('users')
                                .where('role', isEqualTo: 'user')
                                .get()
                                .then((q) => q.docs.length),
                          ]),
                          builder: (context, snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final vals = snap.data ?? [0, 0, 0];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _statItem(
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Icon(
                                              Icons.verified,
                                              size: 20,
                                              color: Colors.black54,
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'Approved',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                        vals[0].toString(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _statItem(
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Icon(
                                              Icons.pending_actions,
                                              size: 20,
                                              color: Colors.black54,
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'Pending',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                        vals[1].toString(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _statItem(
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Icon(
                                              Icons.people,
                                              size: 20,
                                              color: Colors.black54,
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'Customers',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                        vals[2].toString(),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        // Hide the verification link when viewing the Users tab
                        if (tab.title != 'Users')
                          Align(
                            alignment: Alignment.center,
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/admin/verify'),
                              child: const Text('Lihat Verifikasi'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(child: tab.child),
          ],
        ),
      ),
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
      // Drawer removed — actions moved to AppBar (verification + logout)
    );
  }
}

Widget _statItem(Widget labelWidget, String value) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      Center(child: labelWidget),
    ],
  );
}

class _Tab extends StatelessWidget {
  final String title;
  final Widget child;
  const _Tab({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
