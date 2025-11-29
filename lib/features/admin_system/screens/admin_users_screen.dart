import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final usersRef = FirebaseFirestore.instance.collection('users');
  String _filter = 'all'; // 'all' | 'customers' | 'studio'

  Query<Map<String, dynamic>> _buildQuery() {
    // To avoid requiring a Firestore composite index for a where + orderBy
    // query, we perform a simple where(...) on the server and sort locally.
    // For the 'all' filter we can use an ordered query server-side.
    if (_filter == 'customers') {
      return usersRef.where('role', isEqualTo: 'user');
    }
    if (_filter == 'studio') {
      return usersRef.where('role', isEqualTo: 'photobooth_admin');
    }
    return usersRef.orderBy('created_at', descending: true);
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
                  // Try to extract a URL from the error text (Firestore suggests the index URL)
                  final errText = err?.toString() ?? 'Unknown error';
                  final urlMatch = RegExp(
                    r'https?://[^\s]+',
                  ).firstMatch(errText);
                  final indexUrl = urlMatch?.group(0);
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Error loading users'),
                        const SizedBox(height: 8),
                        Text(
                          errText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: () => setState(() {}),
                              child: const Text('Retry'),
                            ),
                            const SizedBox(width: 12),
                            if (indexUrl != null) ...[
                              ElevatedButton.icon(
                                icon: const Icon(Icons.link),
                                label: const Text('Create Index'),
                                onPressed: () async {
                                  try {
                                    await launchUrlString(
                                      indexUrl,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  } catch (_) {
                                    Fluttertoast.showToast(
                                      msg: 'Gagal membuka link.',
                                    );
                                  }
                                },
                              ),
                            ],
                          ],
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
                var docs = snap.data!.docs;
                // If we requested a filtered list (customers or studio), Firestore
                // returned results without ordering. Sort locally by created_at
                // descending so UI matches expected ordering.
                if (_filter != 'all') {
                  docs = List.of(docs);
                  docs.sort((a, b) {
                    final da = a.data();
                    final db = b.data();
                    final ta = da['created_at'];
                    final tb = db['created_at'];
                    // created_at is expected to be a Timestamp from Firestore.
                    int ma = 0;
                    int mb = 0;
                    try {
                      if (ta is Timestamp) {
                        ma = ta.toDate().millisecondsSinceEpoch;
                      }
                      if (tb is Timestamp) {
                        mb = tb.toDate().millisecondsSinceEpoch;
                      }
                    } catch (_) {}
                    return mb.compareTo(ma); // descending
                  });
                }
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
