import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'register_popup.dart';
import 'forgot_password_popup.dart';
import 'waiting_verification.dart';
import '../../../core/admin_config.dart';

class LoginPopup extends StatefulWidget {
  const LoginPopup({super.key});

  @override
  State<LoginPopup> createState() => _LoginPopupState();
}

class _LoginPopupState extends State<LoginPopup> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  String _loginAs = 'user'; // 'user' or 'photobooth_admin'

  bool _isLoading = false;
  bool _obscurePassword = true;

  // Use centralized admin config for bootstrapping credentials.
  bool _isSystemAdminEmail(String? email) =>
      (email ?? '').toLowerCase().trim() ==
      AdminConfig.systemAdminEmail.toLowerCase().trim();

  Future<void> _loginUser() async {
    setState(() => _isLoading = true);
    try {
      final email = emailController.text.trim();
      final password = passwordController.text.trim();

      // System admin shortcut: attempt sign-in first. If the system admin
      // account doesn't exist, allow client-side creation only when the
      // entered password matches the configured system password (bootstrapping).
      if (_isSystemAdminEmail(email)) {
        try {
          await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
        } on FirebaseAuthException catch (e) {
          if (e.code == 'user-not-found') {
            // Bootstrapping: if the user entered the known system admin secret,
            // create the account locally so they can proceed.
            if (password == AdminConfig.systemAdminPassword) {
              try {
                await _auth.createUserWithEmailAndPassword(
                  email: email,
                  password: AdminConfig.systemAdminPassword,
                );
              } on FirebaseAuthException catch (createErr) {
                Fluttertoast.showToast(
                  msg: createErr.message ?? 'Gagal membuat akun admin.',
                );
                if (mounted) {
                  setState(() => _isLoading = false);
                }
                return;
              }
            } else {
              Fluttertoast.showToast(
                msg:
                    'Akun System Admin belum dibuat. Hubungi operator atau periksa kembali password.',
              );
              if (mounted) {
                setState(() => _isLoading = false);
              }
              return;
            }
          } else {
            rethrow;
          }
        }
      } else {
        await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      // Pastikan dokumen user di Firestore ada (buat jika belum ada)
      final user = _auth.currentUser;
      if (user != null) {
        // If this is the system admin email, create/update in system_admins collection
        if (_isSystemAdminEmail(user.email)) {
          final systemAdminRef = FirebaseFirestore.instance
              .collection('system_admins')
              .doc(user.uid);
          await systemAdminRef.set({
            'uid': user.uid,
            'name': user.displayName ?? (user.email?.split('@').first ?? ''),
            'email': user.email ?? '',
            'photoUrl': user.photoURL ?? '',
            'role': 'system_admin',
            'created_at': FieldValue.serverTimestamp(),
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          // For non-system admin, check both collections
          final customerDoc = await FirebaseFirestore.instance
              .collection('customers')
              .doc(user.uid)
              .get();
          final photoboothDoc = await FirebaseFirestore.instance
              .collection('photobooth_admins')
              .doc(user.uid)
              .get();

          // If user doesn't exist in either collection, create in customers
          if (!customerDoc.exists && !photoboothDoc.exists) {
            await FirebaseFirestore.instance
                .collection('customers')
                .doc(user.uid)
                .set({
                  'uid': user.uid,
                  'name':
                      user.displayName ?? (user.email?.split('@').first ?? ''),
                  'email': user.email ?? '',
                  'photoUrl': user.photoURL ?? '',
                  'role': 'customer',
                  'created_at': FieldValue.serverTimestamp(),
                });
          }

          // If logging in as photobooth admin, validate role
          if (_loginAs == 'photobooth_admin') {
            final data = photoboothDoc.exists
                ? photoboothDoc.data()
                : customerDoc.exists
                ? customerDoc.data()
                : null;
            final role = data?['role'] as String? ?? 'customer';
            if (role != 'photobooth_admin' && role != 'system_admin') {
              Fluttertoast.showToast(
                msg:
                    'Akun ini bukan Admin Photobooth. Silakan login sebagai User/Customer.',
              );
              await _auth.signOut();
              if (mounted) {
                setState(() => _isLoading = false);
              }
              return;
            }
            // If photobooth_admin but not verified, route to waiting screen
            final verified = data?['verified'] as bool? ?? false;
            if (!verified && role == 'photobooth_admin') {
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WaitingForVerificationScreen(
                      collectionName: 'photobooth_admins',
                    ),
                  ),
                );
              }
              return;
            }
          } else {
            // If logging in as user/customer, validate they are NOT photobooth admin
            final data = photoboothDoc.exists
                ? photoboothDoc.data()
                : customerDoc.exists
                ? customerDoc.data()
                : null;
            final role = data?['role'] as String? ?? 'customer';
            if (role == 'photobooth_admin') {
              Fluttertoast.showToast(
                msg:
                    'Akun ini adalah Admin Photobooth. Silakan login sebagai Admin Photobooth.',
              );
              await _auth.signOut();
              if (mounted) {
                setState(() => _isLoading = false);
              }
              return;
            }
          }
        }
      }

      // Fetch the latest user doc to show debug info (email, uid, role)
      String debugRole = 'unknown';
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        try {
          final systemAdminSnap = await FirebaseFirestore.instance
              .collection('system_admins')
              .doc(currentUser.uid)
              .get();
          final customerSnap = await FirebaseFirestore.instance
              .collection('customers')
              .doc(currentUser.uid)
              .get();
          final photoboothSnap = await FirebaseFirestore.instance
              .collection('photobooth_admins')
              .doc(currentUser.uid)
              .get();
          final debugData = systemAdminSnap.exists
              ? systemAdminSnap.data() as Map<String, dynamic>
              : photoboothSnap.exists
              ? photoboothSnap.data() as Map<String, dynamic>
              : customerSnap.exists
              ? customerSnap.data() as Map<String, dynamic>
              : {};
          debugRole = (debugData['role'] as String?) ?? 'not-set';
          Fluttertoast.showToast(
            msg:
                'Signed in: ${currentUser.email}\nUID: ${currentUser.uid}\nrole: $debugRole',
            toastLength: Toast.LENGTH_LONG,
          );
        } catch (_) {
          Fluttertoast.showToast(msg: 'Login berhasil! (failed to read role)');
        }
      } else {
        Fluttertoast.showToast(msg: 'Login berhasil!');
      }
      // Routing based on role/login selection or system admin
      final currentEmail = _auth.currentUser?.email?.toLowerCase();
      if (_isSystemAdminEmail(currentEmail)) {
        // System admin always goes to system admin dashboard regardless of "login sebagai" selection
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/system-admin');
        }
        return;
      }

      // For photobooth admin selection, go to admin panel; otherwise main
      if (_loginAs == 'photobooth_admin') {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/admin');
        }
      } else {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/main');
        }
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Login gagal.';
      switch (e.code) {
        case 'user-not-found':
          message = 'Email tidak terdaftar.';
          break;
        case 'wrong-password':
          message = 'Password salah.';
          break;
        case 'invalid-email':
          message = 'Format email tidak valid.';
          break;
        case 'user-disabled':
          message = 'Akun dinonaktifkan.';
          break;
        case 'too-many-requests':
          message = 'Terlalu banyak percobaan. Coba lagi nanti.';
          break;
        case 'network-request-failed':
          message = 'Jaringan bermasalah. Periksa koneksi internet.';
          break;
        default:
          message = e.message ?? message;
      }
      Fluttertoast.showToast(msg: message);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 80),
            Image.asset('assets/images/logo.png', width: 100, height: 100),
            const SizedBox(height: 30),
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFB9CBEF),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(80),
                  topRight: Radius.circular(80),
                  bottomLeft: Radius.circular(80),
                  bottomRight: Radius.circular(80),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Column(
                children: [
                  const Text(
                    'Masuk',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  // Login as selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Masuk sebagai: '),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _loginAs,
                        items: const [
                          DropdownMenuItem(
                            value: 'user',
                            child: Text('Pengguna / Pelanggan'),
                          ),
                          DropdownMenuItem(
                            value: 'photobooth_admin',
                            child: Text('Admin Photobooth'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _loginAs = v ?? 'user'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // --- Input Email ---
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // --- Input Password dengan fitur lihat/sembunyikan ---
                  TextField(
                    controller: passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Kata sandi',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  _isLoading
                      ? const CircularProgressIndicator()
                      : SizedBox(
                          width: double.infinity,
                          height: 45,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                            ),
                            onPressed: _loginUser,
                            child: const Text(
                              'Masuk',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordPopup(),
                          ),
                        );
                      },
                      child: const Text(
                        'Lupa password?',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // --- Navigasi ke register ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Belum punya akun? "),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RegisterPopup(),
                            ),
                          );
                        },
                        child: const Text(
                          'Daftar di sini',
                          style: TextStyle(color: Colors.blueAccent),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
