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

  String? _currentRole;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((u) async {
      if (u == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(u.uid)
          .get();
      setState(() => _currentRole = (doc.data()?['role'] as String?));
    });
  }

  Future<void> _approve(DocumentSnapshot doc) async {
    final id = doc.id;

    // Before approving, try to validate the submitted KTP/selfie link(s).
    final data = doc.data() as Map<String, dynamic>?;
    final driveLink = (data?['driveLink'] as String?) ?? '';
    if (driveLink.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak ada link KTP/Selfie pada akun ini.'),
          ),
        );
      }
      return;
    }

    final ok = await _validateDriveLinks(driveLink);
    if (!ok) return;

    // Update Firestore immediately so UI reflects the change
    await _col.doc(id).update({
      'verified': true,
      'verifiedAt': FieldValue.serverTimestamp(),
      'ktp_auto_verified': true,
    });
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
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

  /// Validate one or more links provided by the user.
  /// Accepts comma or newline separated links. For Google Drive `file/d/ID` or
  /// `open?id=ID` patterns we build a direct-download URL and perform a HEAD
  /// request to check Content-Type and size.
  Future<bool> _validateDriveLinks(String raw) async {
    final links = raw
        .split(RegExp(r'[\n,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (links.isEmpty) return false;

    for (final l in links) {
      final direct = _driveToDirectUrl(l);
      try {
        final head = await http
            .head(Uri.parse(direct))
            .timeout(const Duration(seconds: 10));
        final ct = head.headers['content-type'] ?? '';
        final cl = int.tryParse(head.headers['content-length'] ?? '') ?? 0;

        // Accept images or PDFs up to 8 MB
        final okType = ct.startsWith('image/') || ct.contains('pdf');
        final okSize = cl == 0 || cl <= 8 * 1024 * 1024;
        if (!okType) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('File tidak valid untuk link: $l (type: $ct)'),
              ),
            );
          }
          return false;
        }
        if (!okSize) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('File terlalu besar untuk link: $l')),
            );
          }
          return false;
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mengakses file dari link: $l')),
          );
        }
        return false;
      }
    }
    return true;
  }

  /// Convert common Google Drive share links to a direct-download URL when possible.
  /// If the link already looks like a direct URL, return it unchanged.
  String _driveToDirectUrl(String link) {
    try {
      final uri = Uri.parse(link);
      final host = uri.host.toLowerCase();
      if (host.contains('drive.google.com')) {
        final p = uri.path;
        // pattern: /file/d/FILEID/...
        final match = RegExp(r'/file/d/([A-Za-z0-9_-]+)').firstMatch(p);
        if (match != null) {
          final id = match.group(1);
          return 'https://drive.google.com/uc?export=download&id=$id';
        }
        // pattern: /open?id=FILEID
        final id = uri.queryParameters['id'];
        if (id != null && id.isNotEmpty) {
          return 'https://drive.google.com/uc?export=download&id=$id';
        }
        // pattern: drive folder or other; return original link (may not be directly downloadable)
        return link;
      }
      return link;
    } catch (_) {
      return link;
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
      if (user == null) {
        throw Exception(
          'Anda harus login sebagai System Admin untuk memanggil function.',
        );
      }
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

      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      if (resp.statusCode == 200) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Claim set via Cloud Function')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('Function error: ${resp.body}')),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal memanggil function: $e')),
      );
    }
  }

  Future<void> _reject(DocumentSnapshot doc) async {
    final id = doc.id;
    // mark rejected so there is a record; operator can delete later if desired
    await _col.doc(id).update({
      'role': 'rejected',
      'rejectedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Akun ditandai rejected')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only allow access to system_admin
    if (_currentRole != null && _currentRole != 'system_admin') {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Verifikasi Admin Photobooth'),
          backgroundColor: const Color(0xFF4981CF),
        ),
        body: const Center(
          child: Text(
            'Akses ditolak. Hanya System Admin yang dapat mengakses halaman ini.',
          ),
        ),
      );
    }

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
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'Tidak ada akun photobooth yang menunggu verifikasi.',
              ),
            );
          }
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
                              if (ok ?? false) {
                                await _approve(d);
                              }
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
                              if (ok ?? false) {
                                await _reject(d);
                              }
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
