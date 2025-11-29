import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AdminVerificationScreen extends StatefulWidget {
  const AdminVerificationScreen({super.key});

  @override
  State<AdminVerificationScreen> createState() =>
      _AdminVerificationScreenState();
}

class _AdminVerificationScreenState extends State<AdminVerificationScreen> {
  final _col = FirebaseFirestore.instance.collection('users');

  String? _currentRole;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    // Keep the subscription so we can cancel it in dispose and avoid
    // calling setState after the widget has been removed.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) async {
      if (u == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(u.uid)
          .get();
      if (!mounted) return;
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

    // Note: This app no longer prompts for a Cloud Function URL. If you
    // require setting custom claims automatically, run the server-side
    // function or use the Firebase Console / admin tools.
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

        // Google Drive folder links (drive.google.com/drive/folders/...) return
        // an HTML page; treat them as acceptable for verification since the
        // admin may provide a folder containing KTP/selfie images. Warn the
        // operator but do not fail validation for HTML Drive pages.
        final isDriveLink = l.contains('drive.google.com');
        if (ct.startsWith('text/html') && isDriveLink) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Terima folder Google Drive untuk link: $l'),
              ),
            );
          }
          // accept and continue to next link
          continue;
        }

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

  // Cloud Function HTTP helper removed. Custom claims must be set via
  // server-side tools (Firebase Console, admin SDK or deployed functions).

  Future<void> _reject(DocumentSnapshot doc) async {
    // mark rejected so there is a record; operator can delete later if desired
    // Mark as rejected but do NOT set a permanent 'rejected' role that
    // would blacklist the account. Reset role back to 'user' so the
    // person can re-register later if they wish. Store rejection metadata
    // for audit purposes.
    await doc.reference.update({
      'rejected': true,
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectionNote': 'Rejected by system admin',
      // Reset role to allow re-registration; keep original role history
      // in case you want to audit later.
      'role': 'user',
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
          if (!snap.hasData) {
            return const Center(child: Text('Tidak ada data.'));
          }

          // Filter out documents that have been explicitly rejected so they
          // don't appear in the pending list anymore. Default to not
          // rejected when the field is absent.
          final docs = snap.data!.docs.where((d) {
            final m = d.data() as Map<String, dynamic>;
            final rejected = m['rejected'] as bool? ?? false;
            return !rejected;
          }).toList();

          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 36.0),
                child: Text(
                  'Tidak ada akun photobooth yang menunggu verifikasi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            );
          }

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

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
