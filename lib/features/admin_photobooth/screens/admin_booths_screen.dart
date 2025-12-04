import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/cloudinary_service.dart';
import '../../../core/cloudinary_config.dart';

/// Clean admin booths screen implementation.
class AdminBoothsScreen extends StatefulWidget {
  const AdminBoothsScreen({super.key});

  @override
  State<AdminBoothsScreen> createState() => _AdminBoothsScreenState();
}

class _AdminBoothsScreenState extends State<AdminBoothsScreen> {
  Query<Map<String, dynamic>>? _query;

  @override
  void initState() {
    super.initState();
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      _query = FirebaseFirestore.instance
          .collection('booths')
          .where('createdBy', isEqualTo: userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_query == null) {
      return const Scaffold(body: Center(child: Text('User tidak ditemukan')));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query!.snapshots(),
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
        final fabBottom = bottomNav - 40.0;
        final listBottomPadding = (fabBottom + 80.0).clamp(120.0, 280.0);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Stack(
              children: [
                docs.isEmpty
                    ? _emptyState()
                    : _listView(docs, bottomPad: listBottomPadding),
                if (docs.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: fabBottom,
                    child: Center(
                      child: FloatingActionButton.extended(
                        onPressed: _openCreate,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.add),
                        label: const Text('Tambah Booth'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
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

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Belum ada data booth.',
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 24),
          FloatingActionButton.extended(
            onPressed: _openCreate,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Tambah Booth'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _listView(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    double bottomPad = 16.0,
  }) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final doc = docs[i];
        final d = doc.data();
        final id = doc.id;
        final name = (d['name'] ?? 'Tanpa Nama').toString();
        final price = d['price'] ?? 0;
        final image = (d['imageUrl'] ?? d['image'] ?? d['path'] ?? '')
            .toString();
        final description = (d['description'] ?? '').toString();
        final createdBy = d['createdBy'] as String?;

        // Validasi apakah booth ini milik user yang sedang login
        final isOwner = currentUserId != null && createdBy == currentUserId;

        return Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 72, height: 72, child: _thumb(image)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Rp ${price.toString()} / jam',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      if (description.isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.description,
                              size: 16,
                              color: Colors.black54,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                description,
                                style: const TextStyle(color: Colors.black54),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                // Hanya tampilkan menu edit/delete jika user adalah owner booth
                if (isOwner)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (val) async {
                      if (val == 'edit') {
                        _openEdit(id, d);
                      } else if (val == 'delete') {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Konfirmasi Hapus'),
                            content: const Text(
                              'Hapus booth ini? Tindakan tidak dapat dibatalkan.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Batal'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Hapus'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await _delete(id, image);
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(content: Text('Booth dihapus')),
                          );
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Ubah')),
                      PopupMenuItem(value: 'delete', child: Text('Hapus')),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _thumb(String urlOrPath) {
    // Return a rectangular thumbnail that falls back to the default booth asset.
    if (urlOrPath.isEmpty) {
      return Image.asset('assets/images/default_booth.jpg', fit: BoxFit.cover);
    }
    if (urlOrPath.startsWith('http')) {
      return Image.network(
        urlOrPath,
        fit: BoxFit.cover,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                          (progress.expectedTotalBytes ?? 1)
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (ctx, err, st) =>
            Image.asset('assets/images/default_booth.jpg', fit: BoxFit.cover),
      );
    }
    return FutureBuilder<String>(
      future: _resolveDownloadUrl(urlOrPath),
      builder: (context, s) {
        final u = s.data;
        if (u == null || u.isEmpty) {
          return Image.asset(
            'assets/images/default_booth.jpg',
            fit: BoxFit.cover,
          );
        }
        return Image.network(
          u,
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                            (progress.expectedTotalBytes ?? 1)
                      : null,
                ),
              ),
            );
          },
          errorBuilder: (ctx, err, st) =>
              Image.asset('assets/images/default_booth.jpg', fit: BoxFit.cover),
        );
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
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

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
            onSubmit: (data) async {
              // Stamp admin's location info onto booth so customer filters align
              data['createdBy'] = userId;
              try {
                final adminDoc = await FirebaseFirestore.instance
                    .collection('photobooth_admins')
                    .doc(userId)
                    .get();
                final admin = adminDoc.data() ?? <String, dynamic>{};
                // Prefer explicit fields if admin profile has them
                final location = (admin['location'] ?? '').toString().trim();
                final province = (admin['province'] ?? admin['provinsi'] ?? '')
                    .toString()
                    .trim();
                final city =
                    (admin['city'] ?? admin['kota'] ?? admin['kabupaten'] ?? '')
                        .toString()
                        .trim();
                if (location.isNotEmpty) data['location'] = location;
                if (province.isNotEmpty) data['province'] = province;
                if (city.isNotEmpty) data['city'] = city;
              } catch (_) {}
              await FirebaseFirestore.instance.collection('booths').add(data);
            },
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
            onSubmit: (data) async {
              // Keep admin location in sync when editing if not explicitly set
              try {
                final userId = FirebaseAuth.instance.currentUser?.uid;
                if (userId != null) {
                  final adminDoc = await FirebaseFirestore.instance
                      .collection('photobooth_admins')
                      .doc(userId)
                      .get();
                  final admin = adminDoc.data() ?? <String, dynamic>{};
                  data.putIfAbsent(
                    'location',
                    () => (admin['location'] ?? '').toString().trim(),
                  );
                  data.putIfAbsent(
                    'province',
                    () => (admin['province'] ?? admin['provinsi'] ?? '')
                        .toString()
                        .trim(),
                  );
                  data.putIfAbsent(
                    'city',
                    () =>
                        (admin['city'] ??
                                admin['kota'] ??
                                admin['kabupaten'] ??
                                '')
                            .toString()
                            .trim(),
                  );
                }
              } catch (_) {}
              await FirebaseFirestore.instance
                  .collection('booths')
                  .doc(id)
                  .set(data, SetOptions(merge: true));
            },
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
          // Preview gambar jika sudah dipilih
          if (imagePath.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imagePath.startsWith('http')
                    ? Image.network(imagePath, fit: BoxFit.cover)
                    : Image.file(File(imagePath), fit: BoxFit.cover),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          final picker = ImagePicker();
                          final file = await picker.pickImage(
                            source: ImageSource.gallery,
                          );
                          if (file == null) return;
                          setState(() => imagePath = file.path);
                        },
                  icon: const Icon(Icons.photo_library),
                  label: Text(imagePath.isEmpty ? 'Pilih Foto' : 'Ganti Foto'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          setState(() => saving = true);
                          final nav = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);

                          try {
                            String imageUrl = imagePath;

                            // Upload ke Cloudinary jika gambar baru dipilih (path lokal)
                            if (imagePath.isNotEmpty &&
                                !imagePath.startsWith('http')) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Mengunggah foto...'),
                                  duration: Duration(seconds: 2),
                                ),
                              );

                              final uploadedUrl =
                                  await CloudinaryService.uploadImage(
                                    imagePath,
                                    folder: CloudinaryConfig.boothImagesFolder,
                                  );

                              if (uploadedUrl == null) {
                                throw Exception(
                                  'Gagal mengunggah foto ke Cloudinary',
                                );
                              }

                              imageUrl = uploadedUrl;
                            }

                            final payload = {
                              'name': name.text.trim(),
                              'price': int.tryParse(price.text) ?? 0,
                              'duration': duration.text.trim(),
                              'capacity': capacity.text.trim(),
                              'description': description.text.trim(),
                              'imageUrl': imageUrl,
                              'updated_at': FieldValue.serverTimestamp(),
                            };

                            if (widget.initial == null) {
                              payload['created_at'] =
                                  FieldValue.serverTimestamp();
                            }

                            await widget.onSubmit(payload);

                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Booth berhasil disimpan'),
                                ),
                              );
                              nav.pop();
                            }
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Gagal: ${e.toString()}'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => saving = false);
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    saving ? 'Menyimpan...' : 'Simpan',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
