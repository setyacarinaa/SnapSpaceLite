import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class WaitingForVerificationScreen extends StatefulWidget {
  const WaitingForVerificationScreen({super.key});

  @override
  State<WaitingForVerificationScreen> createState() =>
      _WaitingForVerificationScreenState();
}

class _WaitingForVerificationScreenState
    extends State<WaitingForVerificationScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user != null) _listen(user.uid);
    _auth.authStateChanges().listen((u) {
      if (u != null) _listen(u.uid);
    });
  }

  void _listen(String uid) {
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
          final data = snap.data() ?? {};
          final verified = data['verified'] as bool? ?? false;
          if (verified) {
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
