import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/admin_config.dart';

class AdminBookingsScreen extends StatelessWidget {
  const AdminBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('bookings')
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        final filtered = docs.where((doc) {
          final d = doc.data();
          final rawStatus = (d['status'] ?? 'pending').toString().toLowerCase();
          final status = _normalizeStatus(rawStatus);
          return status != 'rejected';
        }).toList();

        if (filtered.isEmpty) {
          return const Center(child: Text('Belum ada booking.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final d = filtered[i].data();
            final id = filtered[i].id;
            final booth = d['boothName'] ?? '-';
            final user = d['userName'] ?? d['userEmail'] ?? d['userId'] ?? '-';
            final rawStatus = (d['status'] ?? 'pending')
                .toString()
                .toLowerCase();
            final status = _normalizeStatus(rawStatus);

            return ListTile(
              title: Text(
                booth,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('User: $user'),
              onTap: () => _showBookingDialog(context, id, d),
              trailing: DropdownButton<String>(
                value: status,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                ],
                onChanged: (v) async {
                  if (v == null || v == status) return;
                  await _changeBookingStatus(context, id, v);
                },
              ),
            );
          },
        );
      },
    );
  }
}

Future<void> _changeBookingStatus(
  BuildContext context,
  String id,
  String newStatus,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final ref = FirebaseFirestore.instance.collection('bookings').doc(id);
  try {
    if (newStatus == 'rejected') {
      if (AdminConfig.functionBaseUrl.isNotEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        final idToken = user == null ? null : await user.getIdToken();
        final base = AdminConfig.functionBaseUrl.replaceAll(RegExp(r"/+"), '');
        final url = Uri.parse('$base/deleteBooking');
        final resp = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            if (idToken != null) 'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({'bookingId': id}),
        );
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
        }
      } else {
        await ref.delete();
      }
      messenger.showSnackBar(const SnackBar(content: Text('Booking dihapus')));
      return;
    }

    // For other statuses simply update the document
    await ref.set({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    messenger.showSnackBar(
      SnackBar(content: Text('Status diperbarui: $newStatus')),
    );
  } catch (e, st) {
    // Fallback: try to mark rejected if delete failed
    try {
      await ref.set({
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
    messenger.showSnackBar(
      SnackBar(content: Text('Gagal mengubah status: ${e.toString()}')),
    );
    // ignore: avoid_print
    print('Failed to change booking $id to $newStatus: $e\n$st');
  }
}

String _normalizeStatus(String s) {
  final v = s.trim().toLowerCase();
  if (v == 'accepted' || v == 'approved') return 'approved';
  if (v == 'declined' || v == 'rejected') return 'rejected';
  return v;
}

String _formatDateForDisplay(dynamic raw) {
  if (raw == null) return '-';

  if (raw is Timestamp) {
    final dt = raw.toDate().toLocal();
    return DateFormat('d MMMM yyyy, HH:mm', 'id').format(dt);
  }

  if (raw is DateTime) {
    return DateFormat('d MMMM yyyy, HH:mm', 'id').format(raw.toLocal());
  }

  final s = raw.toString();
  final parsed = DateTime.tryParse(s);
  if (parsed != null) {
    return DateFormat('d MMMM yyyy, HH:mm', 'id').format(parsed.toLocal());
  }

  return s;
}

/// Resolve a path or URL to a usable HTTP download URL.
Future<String?> _resolveStorageUrlIfNeeded(String? path) async {
  if (path == null) return null;
  final p = path.trim();
  if (p.isEmpty) return null;
  if (p.startsWith('http')) return p;
  try {
    // If path looks like a gs:// or full storage URL, use refFromURL
    if (p.startsWith('gs://') || p.startsWith('https://')) {
      final ref = FirebaseStorage.instance.refFromURL(p);
      return await ref.getDownloadURL();
    }

    // Otherwise assume it's a storage path under the default bucket
    final ref = FirebaseStorage.instance.ref(p);
    return await ref.getDownloadURL();
  } catch (e) {
    // ignore errors and return null to fall back to placeholder
    // ignore: avoid_print
    print('Failed to resolve storage url for $path: $e');
    return null;
  }
}

// Try multiple possible field names commonly used for booth image
String _pickImageFieldFromData(Map<String, dynamic> data) {
  const candidates = <String>[
    'thumbnail',
    'cover',
    'imageUrl',
    'imageURL',
    'image',
    'url',
    'photoUrl',
    'path',
    'storagePath',
    'image_path',
  ];
  for (final key in candidates) {
    final val = data[key];
    if (val is String && val.trim().isNotEmpty) return val.trim();
  }
  const listCandidates = <String>['images', 'photos', 'gallery'];
  for (final key in listCandidates) {
    final val = data[key];
    if (val is List && val.isNotEmpty) {
      final first = val.first;
      if (first is String && first.trim().isNotEmpty) return first.trim();
    }
  }
  return '';
}

/// Fetch booth image URL by looking up booth document (by id or name)
Future<String?> _getBoothImageUrl(Map<String, dynamic> booking) async {
  // 1) if booking explicitly contains an image/path/url, prefer that
  final bImg =
      (booking['boothImage'] ?? booking['image'] ?? booking['imageUrl'])
          as String?;
  if (bImg != null && bImg.trim().isNotEmpty) {
    return await _resolveStorageUrlIfNeeded(bImg);
  }

  // 2) try boothId or boothRef fields
  final boothId =
      booking['boothId'] as String? ?? booking['boothRef'] as String?;
  if (boothId != null && boothId.trim().isNotEmpty) {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('booths')
          .doc(boothId)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final img = _pickImageFieldFromData(data);
        if (img.isNotEmpty) return await _resolveStorageUrlIfNeeded(img);
      }
    } catch (_) {}
  }

  // 3) fallback: try to find booth by name
  final boothName = (booking['boothName'] ?? booking['booth'] ?? '').toString();
  if (boothName.isNotEmpty) {
    try {
      final q = await FirebaseFirestore.instance
          .collection('booths')
          .where('name', isEqualTo: boothName)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        final data = q.docs.first.data();
        final img = _pickImageFieldFromData(data);
        if (img.isNotEmpty) return await _resolveStorageUrlIfNeeded(img);
      }
    } catch (_) {}
  }

  return null;
}

Future<void> _showBookingDialog(
  BuildContext context,
  String id,
  Map<String, dynamic> info,
) async {
  String fmt(dynamic v) {
    if (v == null) return '-';
    if (v is Timestamp) return v.toDate().toString();
    return v.toString();
  }

  final userPhoto =
      info['userPhoto'] as String? ??
      info['userAvatar'] as String? ??
      FirebaseAuth.instance.currentUser?.photoURL;
  final dateText = info['date'] ?? info['bookingDate'];

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Text(
                      'Informasi Booking',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(Icons.close, color: Colors.grey.shade600),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Avatar: support direct URLs or Firebase Storage paths
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Builder(
                      builder: (ctx) {
                        if (userPhoto == null) {
                          return CircleAvatar(
                            radius: 36,
                            backgroundColor: const Color(0xFFEEEEEE),
                            backgroundImage: const AssetImage(
                              'assets/images/default_avatar.jpg',
                            ),
                          );
                        }

                        if (userPhoto.startsWith('http')) {
                          return CircleAvatar(
                            radius: 36,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: NetworkImage(userPhoto),
                          );
                        }

                        return FutureBuilder<String?>(
                          future: _resolveStorageUrlIfNeeded(userPhoto),
                          builder: (sctx, ssnap) {
                            if (ssnap.connectionState ==
                                ConnectionState.waiting) {
                              return CircleAvatar(
                                radius: 36,
                                backgroundColor: const Color(0xFFEEEEEE),
                                backgroundImage: const AssetImage(
                                  'assets/images/default_avatar.jpg',
                                ),
                              );
                            }
                            final resolved = ssnap.data;
                            if (resolved != null) {
                              return CircleAvatar(
                                radius: 36,
                                backgroundColor: Colors.grey.shade200,
                                backgroundImage: NetworkImage(resolved),
                              );
                            }
                            return CircleAvatar(
                              radius: 36,
                              backgroundColor: const Color(0xFFEEEEEE),
                              backgroundImage: const AssetImage(
                                'assets/images/default_avatar.jpg',
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fmt(info['userName'] ?? info['userEmail'] ?? '-'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          fmt(info['userEmail'] ?? '-'),
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    FutureBuilder<String?>(
                      future: _getBoothImageUrl(info),
                      builder: (bctx, bsnap) {
                        if (bsnap.connectionState == ConnectionState.waiting) {
                          return Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey.shade200,
                            ),
                          );
                        }
                        final url = (bsnap.data ?? '').trim();
                        if (url.isNotEmpty) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              url,
                              width: 68,
                              height: 68,
                              fit: BoxFit.cover,
                              loadingBuilder: (ctx, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  width: 68,
                                  height: 68,
                                  alignment: Alignment.center,
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.0,
                                      value: progress.expectedTotalBytes != null
                                          ? progress.cumulativeBytesLoaded /
                                                (progress.expectedTotalBytes ??
                                                    1)
                                          : null,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (ctx, err, st) => Image.asset(
                                'assets/images/default_booth.jpg',
                                width: 68,
                                height: 68,
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        }
                        // Fallback: use default booth asset so there's always an image
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'assets/images/default_booth.jpg',
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Booth',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            fmt(info['boothName'] ?? '-'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (dateText != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatDateForDisplay(dateText),
                        style: TextStyle(color: Colors.grey.shade800),
                      ),
                    ),
                  ],
                ),
              ],
              if (info['createdAt'] != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tanggal Pemesanan: ${_formatDateForDisplay(info['createdAt'])}',
                        style: TextStyle(
                          color: const Color.fromARGB(255, 14, 14, 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Center(
                child: Text(
                  'menunggu pembayaran langsung di tempat',
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color.fromARGB(255, 147, 143, 143),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
