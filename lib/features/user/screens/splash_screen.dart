import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_popup.dart';
import '../../../core/admin_config.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  User? user;

  @override
  void initState() {
    super.initState();
    user = FirebaseAuth.instance.currentUser;
    // Auto navigate shortly after splash shows
    Timer(const Duration(milliseconds: 900), () {
      if (mounted) _goNext();
    });
  }

  Future<void> _goNext() async {
    if (user == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPopup()),
      );
      return;
    }

    // Check role from Firestore
    try {
      final uid = user!.uid;
      final email = (user!.email ?? '').toLowerCase().trim();

      // Check system admin first
      if (email == AdminConfig.systemAdminEmail.toLowerCase().trim()) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/system-admin');
        }
        return;
      }

      // Check photobooth_admins collection
      final photoboothDoc = await FirebaseFirestore.instance
          .collection('photobooth_admins')
          .doc(uid)
          .get();

      if (photoboothDoc.exists) {
        final role = photoboothDoc.data()?['role'] as String?;
        if (role == 'photobooth_admin') {
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/admin');
          }
          return;
        }
      }

      // Default to customer/main navigation
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/main');
      }
    } catch (e) {
      // If error, default to main
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/main');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/logo.png', width: 120, height: 120),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Colors.blueAccent),
          ],
        ),
      ),
    );
  }
}
