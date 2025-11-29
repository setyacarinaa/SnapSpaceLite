import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

import 'features/user/screens/splash_screen.dart';
import 'core/theme/app_theme.dart';
import 'features/user/screens/main_navigation.dart';
import 'features/admin_system/screens/admin_dashboard.dart';
import 'core/admin_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'features/admin_system/screens/admin_verification_screen.dart';

void main() {
  // Ensure widgets binding is ready and start app immediately; we'll
  // initialize Firebase inside the widget tree so we can show progress/errors.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SnapSpaceApp());
}

class SnapSpaceApp extends StatefulWidget {
  const SnapSpaceApp({super.key});

  @override
  State<SnapSpaceApp> createState() => _SnapSpaceAppState();
}

class _SnapSpaceAppState extends State<SnapSpaceApp> {
  late Future<FirebaseApp> _firebaseInit;

  @override
  void initState() {
    super.initState();
    _firebaseInit = _ensureFirebaseInitialized();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirebaseApp>(
      future: _firebaseInit,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Lightweight placeholder while Firebase initializes (prevents white screen)
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: Color(0xFFE8EBF2),
              body: Center(
                child: CircularProgressIndicator(color: Colors.blueAccent),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          // If a default app already exists, proceed instead of blocking on error
          if (Firebase.apps.isNotEmpty) {
            return _buildApp();
          }
          // Show a readable error screen if Firebase fails to init
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              appBar: AppBar(title: const Text('SnapSpace')),
              body: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gagal menginisialisasi Firebase',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('${snapshot.error}'),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => setState(() {
                        _firebaseInit = _ensureFirebaseInitialized();
                      }),
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Firebase ready: render the actual app
        return _buildApp();
      },
    );
  }

  Future<FirebaseApp> _ensureFirebaseInitialized() async {
    // If Firebase already initialized (e.g., hot reload or other lib), reuse it
    if (Firebase.apps.isNotEmpty) {
      return Firebase.app();
    }
    return Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  Widget _buildApp() {
    return MaterialApp(
      title: 'SnapSpace',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
      home: const SplashScreen(),
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/main': (context) => const MainNavigation(),
        '/admin': (context) => const _AdminGate(),
        // Admin 'act as' route - allows system admin to view dashboards as other roles
        '/admin/as': (context) {
          // Gate the act-as route: only the configured system admin email
          // may open this route. If an unauthorized user somehow navigates
          // here, show the not-authorized screen.
          final args =
              ModalRoute.of(context)?.settings.arguments
                  as Map<String, dynamic>?;
          final role = (args != null && args['role'] is String)
              ? args['role'] as String
              : 'system_admin';
          final user = FirebaseAuth.instance.currentUser;
          final email = user?.email?.toLowerCase();
          if (email == AdminConfig.systemAdminEmail.toLowerCase()) {
            return AdminDashboard(role: role);
          }
          return const _NotAuthorizedAdminScreen();
        },
        '/admin/verify': (context) => const AdminVerificationScreen(),
      },
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => const SplashScreen(),
        settings: const RouteSettings(name: '/'),
      ),
    );
  }
}

// =============== Admin Access Gate ===============
class _AdminGate extends StatelessWidget {
  const _AdminGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = authSnap.data;
        if (user == null) return const _NotAuthorizedAdminScreen();

        // Fetch user role from Firestore. Check both `users/{uid}` and the
        // new `photobooth_admins/{uid}` collection so role detection works
        // during/after migration.
        return FutureBuilder<List<DocumentSnapshot>>(
          future: Future.wait([
            FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
            FirebaseFirestore.instance
                .collection('photobooth_admins')
                .doc(user.uid)
                .get(),
          ]),
          builder: (context, snaps) {
            if (snaps.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final userDoc = snaps.data != null && snaps.data!.isNotEmpty
                ? snaps.data![0]
                : null;
            final photodoc = snaps.data != null && snaps.data!.length > 1
                ? snaps.data![1]
                : null;

            String? role;
            if (photodoc != null && photodoc.exists) {
              role =
                  (photodoc.data() as Map<String, dynamic>?)?['role']
                      as String?;
            }
            if (role == null && userDoc != null && userDoc.exists) {
              role =
                  (userDoc.data() as Map<String, dynamic>?)?['role'] as String?;
            }

            if (role == 'system_admin') {
              return const AdminDashboard(role: 'system_admin');
            }
            if (role == 'photobooth_admin') {
              return const AdminDashboard(role: 'photobooth_admin');
            }

            // not authorized
            return const _NotAuthorizedAdminScreen();
          },
        );
      },
    );
  }
}

class _NotAuthorizedAdminScreen extends StatelessWidget {
  const _NotAuthorizedAdminScreen();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isSignedIn = user != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        backgroundColor: const Color(0xFF4981CF),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Akses Ditolak',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              isSignedIn
                  ? 'Akun kamu tidak memiliki akses ke panel admin.'
                  : 'Kamu belum login. Silakan login menggunakan akun admin.',
            ),
            const SizedBox(height: 16),
            const Text('Hanya akun berikut yang dapat mengakses:'),
            const SizedBox(height: 8),
            SelectableText(
              'Email: ${AdminConfig.systemAdminEmail}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.popUntil(context, (r) => r.isFirst);
                    Navigator.pushReplacementNamed(context, '/main');
                  },
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Ke Beranda'),
                ),
                const SizedBox(width: 12),
                if (isSignedIn)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.popUntil(context, (r) => r.isFirst);
                        Navigator.pushReplacementNamed(context, '/splash');
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// (Admin badge overlay removed as requested)
