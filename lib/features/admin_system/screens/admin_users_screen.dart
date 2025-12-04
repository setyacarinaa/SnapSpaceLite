import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AdminUsersScreen extends StatefulWidget {
  final String role;
  const AdminUsersScreen({super.key, this.role = 'system_admin'});

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
      // Slightly reduce horizontal padding so chips don't risk overflow
      // while keeping a comfortable tap target.
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _buildQuery();
    // This screen is displayed inside the `AdminDashboard` scaffold.
    // Avoid returning a full Scaffold here (which would create nested
    // app bars and clipped layouts). Return a column that the parent
    // can display.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0.5,
            clipBehavior: Clip.none,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tampilkan:', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    // Add a small left padding so the first chip's rounded
                    // edge doesn't get visually clipped on narrow containers.
                    padding: const EdgeInsets.only(left: 3, right: 28),
                    child: Row(
                      children: [
                        _buildFilterChip(label: 'Semua', value: 'all'),
                        const SizedBox(width: 4),
                        _buildFilterChip(
                          label: 'Pelanggan',
                          value: 'customers',
                        ),
                        const SizedBox(width: 4),
                        _buildFilterChip(
                          label: 'Pemilik Studio',
                          value: 'studio',
                        ),
                        const SizedBox(width: 22),
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
                final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(errText);
                final indexUrl = urlMatch?.group(0);
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Gagal memuat pengguna'),
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
                            child: const Text('Coba Lagi'),
                          ),
                          const SizedBox(width: 12),
                          if (indexUrl != null) ...[
                            ElevatedButton.icon(
                              icon: const Icon(Icons.link),
                              label: const Text('Buat Indeks'),
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
                return const Center(child: Text('Tidak ada data'));
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
                return const Center(child: Text('Tidak ada pengguna'));
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final data = d.data();
                  final roleLabel = (data['role'] ?? 'unknown').toString();
                  return Card(
                    child: ListTile(
                      title: Text(data['name'] as String? ?? '(tanpa nama)'),
                      subtitle: Text('$roleLabel • ${data['email'] ?? ''}'),
                      trailing: widget.role == 'system_admin'
                          ? IconButton(
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.redAccent,
                              ),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Hapus pengguna'),
                                    content: const Text(
                                      'Apakah Anda yakin ingin menghapus pengguna ini?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Tidak'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Ya'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  try {
                                    await usersRef.doc(d.id).delete();
                                    Fluttertoast.showToast(
                                      msg: 'Pengguna dihapus',
                                    );
                                  } catch (e) {
                                    Fluttertoast.showToast(
                                      msg: 'Gagal menghapus pengguna',
                                    );
                                  }
                                }
                              },
                            )
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
