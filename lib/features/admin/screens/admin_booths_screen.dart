import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class AdminBoothsScreen extends StatefulWidget {
  const AdminBoothsScreen({super.key});

  @override
  State<AdminBoothsScreen> createState() => _AdminBoothsScreenState();
}

class _AdminBoothsScreenState extends State<AdminBoothsScreen> {
  @override
  Widget build(BuildContext context) {
    final booths = FirebaseFirestore.instance
        .collection('booths')
        .orderBy('name');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: booths.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openCreate,
            icon: const Icon(Icons.add),
            label: const Text('Tambah Booth'),
          ),
          body: docs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Belum ada data booth.'),
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
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final id = docs[i].id;
                    final name = d['name'] ?? 'Tanpa Nama';
                    final price = d['price'] ?? 0;
                    final image =
                        d['imageUrl'] ?? d['image'] ?? d['path'] ?? '';
                    return ListTile(
                      leading: _thumb(image),
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
                          ),
                          IconButton(
                            onPressed: () => _delete(id, image),
                            icon: const Icon(Icons.delete, color: Colors.red),
                          ),
                        ],
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(),
                  itemCount: docs.length,
                ),
        );
      },
    );
  }

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
        if (u == null || u.isEmpty)
          return const CircleAvatar(child: Icon(Icons.image));
        return CircleAvatar(backgroundImage: NetworkImage(u));
      },
    );
  }

  Future<String> _resolveDownloadUrl(String urlOrPath) async {
    try {
      if (urlOrPath.startsWith('gs://')) {
        return FirebaseStorage.instance.refFromURL(urlOrPath).getDownloadURL();
      }
      return FirebaseStorage.instance.ref(urlOrPath).getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  Future<void> _openCreate() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _BoothForm(
          onSubmit: (data) async {
            await FirebaseFirestore.instance.collection('booths').add(data);
          },
        ),
      ),
    );
  }

  Future<void> _openEdit(String id, Map<String, dynamic> initial) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _BoothForm(
          initial: initial,
          onSubmit: (data) async {
            await FirebaseFirestore.instance
                .collection('booths')
                .doc(id)
                .set(data, SetOptions(merge: true));
          },
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
    await batch.commit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'Booth',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              IconButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Nama'),
          ),
          TextField(
            controller: price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Harga / jam'),
          ),
          TextField(
            controller: duration,
            decoration: const InputDecoration(labelText: 'Durasi (mis. 1 jam)'),
          ),
          TextField(
            controller: capacity,
            decoration: const InputDecoration(labelText: 'Kapasitas'),
          ),
          TextField(
            controller: description,
            decoration: const InputDecoration(labelText: 'Deskripsi'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  imagePath.isEmpty ? 'Belum ada gambar' : imagePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: saving ? null : _pickAndUpload,
                icon: const Icon(Icons.upload),
                label: const Text('Upload Gambar'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: saving ? null : _enterImageUrl,
                icon: const Icon(Icons.link),
                label: const Text('Pakai URL'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: saving ? null : _submit,
              child: saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Simpan'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxHeight: 1080,
      maxWidth: 1080,
    );
    if (x == null) return;
    setState(() => saving = true);
    try {
      final bytes = await x.readAsBytes();
      final ext = (x.path.split('.').last).toLowerCase();
      final fileName = 'booths/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final meta = SettableMetadata(
        contentType: ext == 'png'
            ? 'image/png'
            : ext == 'webp'
            ? 'image/webp'
            : 'image/jpeg',
      );
      final ref = FirebaseStorage.instance.ref(fileName);
      await ref.putData(bytes, meta);
      final url = await ref.getDownloadURL();
      setState(() => imagePath = url); // simpan url langsung agar mudah tampil
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _enterImageUrl() async {
    final controller = TextEditingController(text: imagePath);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Masukkan URL / Path Gambar'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://... atau gs://... atau booths/path.jpg',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pakai'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      setState(() => imagePath = controller.text.trim());
    }
  }

  Future<void> _submit() async {
    final n = name.text.trim();
    if (n.isEmpty) return;
    setState(() => saving = true);
    try {
      final data = <String, dynamic>{
        'name': n,
        'price': int.tryParse(price.text.trim()) ?? 0,
        'duration': duration.text.trim(),
        'capacity': capacity.text.trim(),
        'description': description.text.trim(),
        // Simpan di field imageUrl untuk konsistensi
        'imageUrl': imagePath,
        'updated_at': FieldValue.serverTimestamp(),
      };
      await widget.onSubmit(data);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}
