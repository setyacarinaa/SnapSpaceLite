import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AdminVerificationScreen extends StatefulWidget {
  const AdminVerificationScreen({super.key});

  @override
  State<AdminVerificationScreen> createState() =>
      _AdminVerificationScreenState();
}

class _AdminVerificationScreenState extends State<AdminVerificationScreen> {
  final _col = FirebaseFirestore.instance.collection('users');

  Future<void> _approve(DocumentSnapshot doc) async {
    final id = doc.id;
    // Update Firestore immediately so UI reflects the change
    await _col.doc(id).update({
      'verified': true,
      'verifiedAt': FieldValue.serverTimestamp(),
    });
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Akun diverifikasi (Firestore)')),
      );

    // Offer to call the deployed Cloud Function to set custom claim automatically
    final shouldCall = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Otomatis set claim?'),
        content: const Text(
          'Jalankan Cloud Function untuk memberikan akses admin photobooth secara otomatis? (butuh URL function)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Tidak'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya'),
          ),
        ],
      ),
    );
    if (shouldCall ?? false) {
      final url = await _inputFunctionUrl();
      if (url != null) {
        await _callSetClaimFunction(url, doc);
      }
    }
  }

  Future<String?> _inputFunctionUrl() async {
    String input = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Function URL'),
        content: TextField(
          onChanged: (v) => input = v.trim(),
          decoration: const InputDecoration(
            hintText: 'https://us-central1-.../setPhotoboothAdmin',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok ?? false) return input.isEmpty ? null : input;
    return null;
  }

  Future<void> _callSetClaimFunction(String url, DocumentSnapshot doc) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null)
        throw Exception(
          'Anda harus login sebagai System Admin untuk memanggil function.',
        );
      final idToken = await user.getIdToken();
      final email = (doc.data() as Map<String, dynamic>)['email'] as String?;
      final resp = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Claim set via Cloud Function')),
          );
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Function error: ${resp.body}')),
          );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memanggil function: $e')));
    }
  }

  Future<void> _reject(DocumentSnapshot doc) async {
    final id = doc.id;
    // mark rejected so there is a record; operator can delete later if desired
    await _col.doc(id).update({
      'role': 'rejected',
      'rejectedAt': FieldValue.serverTimestamp(),
    });
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Akun ditandai rejected')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifikasi Admin Photobooth'),
        backgroundColor: const Color(0xFF4981CF),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _col
            .where('role', isEqualTo: 'photobooth_admin')
            .where('verified', isEqualTo: false)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (!snap.hasData || snap.data!.docs.isEmpty)
            return const Center(
              child: Text(
                'Tidak ada akun photobooth yang menunggu verifikasi.',
              ),
            );
          final docs = snap.data!.docs;
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data() as Map<String, dynamic>;
              final name = data['name'] ?? '(tanpa nama)';
              final email = data['email'] ?? '';
              final studioName = data['studioName'] ?? data['company'] ?? '';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(email),
                      if (studioName != '') ...[
                        const SizedBox(height: 8),
                        Text('Studio: $studioName'),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Konfirmasi'),
                                  content: Text(
                                    'Setujui akun $name ($email) sebagai Admin Photobooth?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Batal'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Setujui'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok ?? false) await _approve(d);
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('Approve'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Konfirmasi Reject'),
                                  content: Text(
                                    'Tandai akun $name ($email) sebagai rejected?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Batal'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Reject'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok ?? false) await _reject(d);
                            },
                            icon: const Icon(Icons.close),
                            label: const Text('Reject'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
