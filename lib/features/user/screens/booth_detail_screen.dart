import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:snapspace/features/user/screens/image_preview_screen.dart';
import 'package:snapspace/features/user/screens/booking_form_screen.dart';

class BoothDetailScreen extends StatefulWidget {
  final DocumentReference boothRef;
  const BoothDetailScreen({super.key, required this.boothRef});

  @override
  State<BoothDetailScreen> createState() => _BoothDetailScreenState();
}

class _BoothDetailScreenState extends State<BoothDetailScreen> {
  @override
  Widget build(BuildContext context) {
    // Gunakan reference yang diteruskan dari list agar path akurat (mendukung top-level & subkoleksi)
    final boothRef = widget.boothRef;

    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4981CF),
        title: const Text(
          'Detail Booth',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: boothRef.get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Data booth tidak ditemukan.'));
          }
          final data = (snapshot.data!.data() as Map<String, dynamic>);
          final name = data['name'] ?? 'Tanpa Nama';
          final price = data['price'] ?? 0;
          final duration = data['duration'] ?? '-';
          final description = data['description'] ?? '-';
          final capacity = data['capacity'] ?? '-';
          final imageUrl = _pickImageField(data);

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (imageUrl.isNotEmpty) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ImagePreviewScreen(imageUrl: imageUrl),
                                  ),
                                );
                              }
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _BoothDetailImage(urlOrPath: imageUrl),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Rp $price / sesi ($duration)',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            description,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Kapasitas: Maks. $capacity orang',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        BookingFormScreen(boothName: name),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4981CF),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Booking Sekarang',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      // Bottom navigation is provided by MainNavigation; avoid duplicating here.
    );
  }
}

class _BoothDetailImage extends StatelessWidget {
  final String urlOrPath;
  const _BoothDetailImage({required this.urlOrPath});

  @override
  Widget build(BuildContext context) {
    const height = 200.0;
    if (urlOrPath.isEmpty) {
      return Container(
        height: height,
        color: Colors.grey[300],
        child: const Center(child: Icon(Icons.image_not_supported)),
      );
    }
    if (urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://')) {
      return Image.network(
        urlOrPath,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          height: height,
          color: Colors.grey[300],
          child: const Center(child: Icon(Icons.image_not_supported)),
        ),
      );
    }

    final Future<String> urlFuture = () async {
      try {
        if (urlOrPath.startsWith('gs://')) {
          return await FirebaseStorage.instance
              .refFromURL(urlOrPath)
              .getDownloadURL();
        }
        return await FirebaseStorage.instance.ref(urlOrPath).getDownloadURL();
      } catch (_) {
        return '';
      }
    }();

    return FutureBuilder<String>(
      future: urlFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            height: height,
            color: Colors.grey[300],
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final resolved = (snap.data ?? '').trim();
        if (resolved.isEmpty) {
          return Container(
            height: height,
            color: Colors.grey[300],
            child: const Center(child: Icon(Icons.image_not_supported)),
          );
        }
        return Image.network(
          resolved,
          width: double.infinity,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            height: height,
            color: Colors.grey[300],
            child: const Center(child: Icon(Icons.image_not_supported)),
          ),
        );
      },
    );
  }
}

String _pickImageField(Map<String, dynamic> data) {
  // 1) Common single-string keys
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
    if (val is String && val.trim().isNotEmpty) {
      return val.trim();
    }
  }
  // 2) Array-based keys: take first non-empty
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
