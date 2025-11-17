import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance.collection('users').orderBy('name');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty)
          return const Center(child: Text('Tidak ada pengguna.'));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final name = d['name'] ?? '-';
            final email = d['email'] ?? '-';
            final photo = d['photoUrl'] ?? '';
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: (photo is String && photo.isNotEmpty)
                    ? NetworkImage(photo)
                    : null,
                child: photo is String && photo.isNotEmpty
                    ? null
                    : const Icon(Icons.person),
              ),
              title: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(email),
            );
          },
          separatorBuilder: (_, __) => const Divider(),
        );
      },
    );
  }
}
