import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
        if (docs.isEmpty)
          return const Center(child: Text('Belum ada booking.'));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final id = docs[i].id;
            final booth = d['boothName'] ?? '-';
            final user = d['userName'] ?? d['userEmail'] ?? d['userId'] ?? '-';
            // Normalize legacy/unknown statuses to the canonical set
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
              trailing: DropdownButton<String>(
                value: status,
                items: const [
                  DropdownMenuItem(value: 'pending', child: Text('pending')),
                  DropdownMenuItem(value: 'approved', child: Text('approved')),
                  DropdownMenuItem(value: 'rejected', child: Text('rejected')),
                  DropdownMenuItem(
                    value: 'completed',
                    child: Text('completed'),
                  ),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  await FirebaseFirestore.instance
                      .collection('bookings')
                      .doc(id)
                      .set({
                        'status': v,
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                },
              ),
            );
          },
          separatorBuilder: (_, __) => const Divider(),
        );
      },
    );
  }
}

String _normalizeStatus(String s) {
  switch (s) {
    case 'pending':
    case 'approved':
    case 'rejected':
    case 'completed':
      return s;
    // legacy synonyms -> map to current values
    case 'waiting':
      return 'pending';
    case 'selesai':
      return 'completed';
    case 'dibatalkan':
      return 'rejected';
    case 'proses':
      return 'approved';
    default:
      return 'pending';
  }
}
