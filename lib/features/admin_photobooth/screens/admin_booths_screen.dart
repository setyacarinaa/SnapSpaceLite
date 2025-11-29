import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Clean admin booths screen implementation.
class AdminBoothsScreen extends StatefulWidget {
  const AdminBoothsScreen({super.key});

  @override
  State<AdminBoothsScreen> createState() => _AdminBoothsScreenState();
}

class _AdminBoothsScreenState extends State<AdminBoothsScreen> {
  final _query = FirebaseFirestore.instance
      .collection('booths')
      .orderBy('name');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data?.docs ?? [];
        final bottomNav =
            kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom;
        // place FAB just above the bottom navigation bar
        final fabBottom = bottomNav - 20.0;
        final listBottomPadding = (fabBottom + 80.0).clamp(120.0, 280.0);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Stack(
              children: [
                docs.isEmpty
                    ? Center(child: _emptyState())
                    : _listView(docs, bottomPad: listBottomPadding),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: fabBottom,
                  child: Center(
                    child: FloatingActionButton.extended(
                      onPressed: _openCreate,
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah Booth'),
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

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24.0),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Belum ada data booth.',
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _openCreate,
          icon: const Icon(Icons.add),
          label: const Text('Tambah Booth Baru'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _seedSampleBooths,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Isi Contoh Data'),
        ),
      ],
    ),
  );

  Widget _listView(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    double bottomPad = 16.0,
  }) => ListView.separated(
    padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad),
    separatorBuilder: (_, __) => const SizedBox(height: 10),
    itemCount: docs.length,
    itemBuilder: (context, i) {
      final doc = docs[i];
      final d = doc.data();
      final id = doc.id;
      final name = (d['name'] ?? 'Tanpa Nama').toString();
      final price = d['price'] ?? 0;
      final image = (d['imageUrl'] ?? d['image'] ?? d['path'] ?? '').toString();

      return Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          leading: SizedBox(width: 48, height: 48, child: _thumb(image)),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('Rp $price / jam'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => _openEdit(id, d),
                icon: const Icon(Icons.edit),
                visualDensity: VisualDensity.compact,
                splashRadius: 20,
              ),
              IconButton(
                onPressed: () => _delete(id, image),
                icon: Icon(
                  Icons.delete,
                  color: Theme.of(context).colorScheme.error,
                ),
                visualDensity: VisualDensity.compact,
                splashRadius: 20,
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _thumb(String urlOrPath) {
    if (urlOrPath.isEmpty) {
      return const CircleAvatar(child: Icon(Icons.image_not_supported));
    }
    if (urlOrPath.startsWith('http')) {
      return CircleAvatar(backgroundImage: NetworkImage(urlOrPath));
    }
    return FutureBuilder<String>(
      future: _resolveDownloadUrl(urlOrPath),
      builder: (context, s) {
        final u = s.data;
        if (u == null || u.isEmpty) {
          return const CircleAvatar(child: Icon(Icons.image));
        }
        return CircleAvatar(backgroundImage: NetworkImage(u));
      },
    );
  }

  Future<String> _resolveDownloadUrl(String path) async {
    if (path.isEmpty) {
      return '';
    }
    try {
      if (path.startsWith('gs://')) {
        return FirebaseStorage.instance.refFromURL(path).getDownloadURL();
      }
      return FirebaseStorage.instance.ref(path).getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  Future<void> _openCreate() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: _BoothForm(
            onSubmit: (data) async =>
                FirebaseFirestore.instance.collection('booths').add(data),
          ),
        ),
      ),
    );
  }

  Future<void> _openEdit(String id, Map<String, dynamic> initial) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: _BoothForm(
            initial: initial,
            onSubmit: (data) async => FirebaseFirestore.instance
                .collection('booths')
                .doc(id)
                .set(data, SetOptions(merge: true)),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(String id, String image) async {
    await FirebaseFirestore.instance.collection('booths').doc(id).delete();
    if (image.isNotEmpty && !image.startsWith('http')) {
      try {
        final ref = image.startsWith('gs://')
            ? FirebaseStorage.instance.refFromURL(image)
            : FirebaseStorage.instance.ref(image);
        await ref.delete();
      } catch (_) {}
    }
  }

  Future<void> _seedSampleBooths() async {
    final batch = FirebaseFirestore.instance.batch();
    final booths = FirebaseFirestore.instance.collection('booths');
    final samples = [
      {
        'name': 'Classic Photo Booth',
        'price': 50000,
        'duration': '1 jam',
        'capacity': '3-4 orang',
        'description':
            'Booth klasik dengan background polos dan properti lucu.',
        'imageUrl': '',
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Neon Selfie Booth',
        'price': 75000,
        'duration': '1 jam',
        'capacity': '2-3 orang',
        'description': 'Tema neon modern, cocok untuk konten media sosial.',
        'imageUrl': '',
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Vintage Corner',
        'price': 65000,
        'duration': '1 jam',
        'capacity': '2 orang',
        'description': 'Gaya vintage dengan properti retro.',
        'imageUrl': '',
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      },
    ];
    for (final s in samples) {
      batch.set(booths.doc(), s);
    }
    final messenger = ScaffoldMessenger.of(context);
    await batch.commit();
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('3 contoh booth berhasil dibuat.')),
    );
  }
}

class _BoothForm extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final Future<void> Function(Map<String, dynamic>) onSubmit;
  const _BoothForm({this.initial, required this.onSubmit});

  @override
  State<_BoothForm> createState() => _BoothFormState();
}

class _BoothFormState extends State<_BoothForm> {
  final name = TextEditingController();
  final price = TextEditingController();
  final duration = TextEditingController();
  final capacity = TextEditingController();
  final description = TextEditingController();
  String imagePath = '';
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      name.text = (i['name'] ?? '').toString();
      price.text = (i['price'] ?? '').toString();
      duration.text = (i['duration'] ?? '').toString();
      capacity.text = (i['capacity'] ?? '').toString();
      description.text = (i['description'] ?? '').toString();
      imagePath = (i['imageUrl'] ?? i['image'] ?? i['path'] ?? '').toString();
    }
  }

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    duration.dispose();
    capacity.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle and header
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Booth',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: name,
            decoration: InputDecoration(
              labelText: 'Nama',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Harga / jam',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: duration,
            decoration: InputDecoration(
              labelText: 'Durasi (mis. 1 jam)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: capacity,
            decoration: InputDecoration(
              labelText: 'Kapasitas',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: description,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Deskripsi',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final file = await picker.pickImage(
                      source: ImageSource.gallery,
                    );
                    if (file == null) return;
                    setState(() => imagePath = file.path);
                  },
                  child: const Text('Pilih Foto'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final payload = {
                            'name': name.text.trim(),
                            'price': int.tryParse(price.text) ?? 0,
                            'duration': duration.text.trim(),
                            'capacity': capacity.text.trim(),
                            'description': description.text.trim(),
                            'image': imagePath,
                            'updated_at': FieldValue.serverTimestamp(),
                          };
                          if (widget.initial == null) {
                            payload['created_at'] =
                                FieldValue.serverTimestamp();
                          }
                          setState(() => saving = true);
                          final nav = Navigator.of(context);
                          try {
                            await widget.onSubmit(payload);
                            if (mounted) nav.pop();
                          } finally {
                            if (mounted) setState(() => saving = false);
                          }
                        },
                  child: const Text('Simpan'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
