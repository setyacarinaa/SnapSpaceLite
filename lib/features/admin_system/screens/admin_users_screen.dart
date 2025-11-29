import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final usersRef = FirebaseFirestore.instance.collection('users');
  String _filter = 'all'; // 'all' | 'customers' | 'studio'

  Query<Map<String, dynamic>> _buildQuery() {
    final base = usersRef.orderBy('created_at', descending: true);
    if (_filter == 'customers') {
      return base.where('role', isEqualTo: 'user');
    }
    if (_filter == 'studio') {
      return base.where('role', isEqualTo: 'photobooth_admin');
    }
    return base;
  }

  Widget _buildFilterChip({required String label, required String value}) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: selected ? const TextStyle(color: Colors.white) : null,
      ),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: Theme.of(context).primaryColor,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected
              ? Theme.of(context).primaryColor
              : Colors.grey.shade300,
        ),
      ),
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _buildQuery();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        backgroundColor: const Color(0xFF4981CF),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0.5,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tampilkan:', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(label: 'Semua', value: 'all'),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: 'Customer',
                            value: 'customers',
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: 'Pemilik Studio',
                            value: 'studio',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  final err = snap.error;
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Error loading users'),
                        const SizedBox(height: 8),
                        Text(
                          err?.toString() ?? 'Unknown error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData) {
                  return const Center(child: Text('No data'));
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('No users'));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final data = d.data();
                    final roleLabel = (data['role'] ?? 'unknown').toString();
                    return Card(
                      child: ListTile(
                        title: Text(data['name'] as String? ?? '(no name)'),
                        subtitle: Text('$roleLabel • ${data['email'] ?? ''}'),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                          ),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete user'),
                                content: const Text(
                                  'Are you sure you want to delete this user?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('No'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Yes'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              try {
                                await usersRef.doc(d.id).delete();
                                Fluttertoast.showToast(msg: 'User removed');
                              } catch (e) {
                                Fluttertoast.showToast(
                                  msg: 'Failed to remove user',
                                );
                              }
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
