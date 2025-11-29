import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'login_popup.dart';

class WaitingForVerificationScreen extends StatefulWidget {
  final String collectionName;
  const WaitingForVerificationScreen({Key? key, this.collectionName = 'users'})
    : super(key: key);

  @override
  State<WaitingForVerificationScreen> createState() =>
      _WaitingForVerificationScreenState();
}

class _WaitingForVerificationScreenState
    extends State<WaitingForVerificationScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  final _auth = FirebaseAuth.instance;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user != null) _listen(user.uid);
    _auth.authStateChanges().listen((u) {
      if (u != null) _listen(u.uid);
    });
    // After 5 seconds, if still on this screen and not verified, return to login/register.
    _fallbackTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPopup()),
      );
    });
  }

  void _listen(String uid) {
    _sub?.cancel();
    final collection = widget.collectionName;
    _sub = FirebaseFirestore.instance
        .collection(collection)
        .doc(uid)
        .snapshots()
        .listen((snap) {
          final data = snap.data() ?? {};
          final verified = data['verified'] as bool? ?? false;
          if (verified) {
            // Cancel fallback timer if verification happened early.
            _fallbackTimer?.cancel();
            // When verified, navigate to admin dashboard
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/admin');
            }
          }
        });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _fallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF9CC1F0), Color(0xFF7BA6E3)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              const Icon(
                Icons.check_circle_outline,
                size: 120,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              const Text(
                'Waiting For Verification',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 36.0),
                child: Text(
                  'Akun Anda sedang menunggu verifikasi oleh admin sistem. Anda akan otomatis diarahkan ketika akun disetujui.',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
