import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

String _formatDateForDisplay(String raw) {
  return raw;
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

  final boothImage = info['boothImage'] as String?;
  final userPhoto =
      info['userPhoto'] as String? ?? info['userAvatar'] as String?;
  final dateText = fmt(info['date'] ?? info['bookingDate'] ?? '-');

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
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage:
                        (userPhoto != null && userPhoto.startsWith('http'))
                        ? NetworkImage(userPhoto)
                        : null,
                    child: userPhoto == null
                        ? const Icon(Icons.person, size: 36, color: Colors.grey)
                        : null,
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
                    if (boothImage != null && boothImage.startsWith('http'))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          boothImage,
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade200,
                        ),
                        child: const Icon(
                          Icons.photo_camera,
                          size: 32,
                          color: Colors.grey,
                        ),
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
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatDateForDisplay(dateText),
                      style: TextStyle(color: Colors.grey.shade800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4981CF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('bookings')
                            .doc(id)
                            .set({
                              'status': 'approved',
                              'updatedAt': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                      },
                      child: const Text('Accept'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ref = FirebaseFirestore.instance
                            .collection('bookings')
                            .doc(id);
                        try {
                          if (AdminConfig.functionBaseUrl.isNotEmpty) {
                            final user = FirebaseAuth.instance.currentUser;
                            final idToken = user == null
                                ? null
                                : await user.getIdToken();
                            final base = AdminConfig.functionBaseUrl.replaceAll(
                              RegExp(r"/+"),
                              '',
                            );
                            final url = Uri.parse('$base/deleteBooking');
                            final resp = await http.post(
                              url,
                              headers: {
                                'Content-Type': 'application/json',
                                if (idToken != null)
                                  'Authorization': 'Bearer $idToken',
                              },
                              body: jsonEncode({'bookingId': id}),
                            );
                            if (resp.statusCode != 200) {
                              throw Exception(
                                'HTTP ${resp.statusCode}: ${resp.body}',
                              );
                            }
                          } else {
                            await ref.delete();
                          }
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Booking dihapus')),
                          );
                        } catch (e, st) {
                          await ref.set({
                            'status': 'rejected',
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Gagal menghapus: ${e.toString()} (dokumen diberi status rejected)',
                              ),
                            ),
                          );
                          // ignore: avoid_print
                          print('Failed to delete booking $id: $e\n$st');
                        }
                      },
                      child: Text(
                        'Decline',
                        style: TextStyle(color: Colors.grey.shade800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
