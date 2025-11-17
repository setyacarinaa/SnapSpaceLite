import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'booth_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? userName;
  Query<Map<String, dynamic>>? boothsQuery;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final user = FirebaseAuth.instance.currentUser;
    // Ambil nama pengguna jika ada
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      setState(() {
        userName = userDoc.data()?['name'] ?? 'Pengguna';
      });
    }

    // Prefer koleksi global 'booths'. Jika kosong, fallback ke collectionGroup('booths')
    try {
      final topLevel = await FirebaseFirestore.instance
          .collection('booths')
          .limit(1)
          .get();
      setState(() {
        boothsQuery = topLevel.docs.isNotEmpty
            ? FirebaseFirestore.instance.collection('booths')
            : FirebaseFirestore.instance.collectionGroup('booths');
      });
    } catch (_) {
      // Jika terjadi error (mis. rules), tetap coba collectionGroup sebagai fallback
      setState(() {
        boothsQuery = FirebaseFirestore.instance.collectionGroup('booths');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF4981CF),
        elevation: 2,
        title: Text(
          userName != null ? 'Hi, $userName!' : 'Hi!',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: boothsQuery == null
            ? const Center(child: CircularProgressIndicator())
            : StreamBuilder<QuerySnapshot>(
                stream: boothsQuery!.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    final email =
                        (FirebaseAuth.instance.currentUser?.email ?? '')
                            .toLowerCase()
                            .trim();
                    final isAdmin = email == 'adminsnapspace29@gmail.com';
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("Belum ada data booth."),
                          const SizedBox(height: 12),
                          if (isAdmin)
                            ElevatedButton.icon(
                              onPressed: () => Navigator.pushReplacementNamed(
                                context,
                                '/admin',
                              ),
                              icon: const Icon(Icons.admin_panel_settings),
                              label: const Text(
                                'Buka Admin untuk menambah Booth',
                              ),
                            ),
                        ],
                      ),
                    );
                  }

                  final booths = snapshot.data!.docs;

                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: GridView.builder(
                      itemCount: booths.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisExtent: 270,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      itemBuilder: (context, index) {
                        final booth = booths[index];
                        final data = booth.data() as Map<String, dynamic>;
                        final name = data['name'] ?? 'Tanpa Nama';
                        final price = data['price'] ?? 0;
                        final image = _pickImageField(data);

                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BoothDetailScreen(
                                  boothRef: booth.reference,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 5,
                                  offset: const Offset(2, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(15),
                                  ),
                                  child: _BoothImage(
                                    urlOrPath: image,
                                    height: 140,
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          "Rp $price / jam",
                                          style: const TextStyle(
                                            color: Colors.blueGrey,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: ElevatedButton(
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      BoothDetailScreen(
                                                        boothRef:
                                                            booth.reference,
                                                      ),
                                                ),
                                              );
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFF4169E1,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 6,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            child: const Text(
                                              "Detail",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
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
                  );
                },
              ),
      ),
      // Bottom navigation is provided by MainNavigation; avoid duplicating here.
    );
  }

  // Helper widget to resolve Firebase Storage paths or direct HTTP URLs
  Widget _BoothImage({required String urlOrPath, required double height}) {
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
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          height: height,
          color: Colors.grey[300],
          child: const Center(child: Icon(Icons.broken_image)),
        ),
      );
    }

    // gs://bucket/path or storage relative path
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
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            height: height,
            color: Colors.grey[300],
            child: const Center(child: Icon(Icons.broken_image)),
          ),
        );
      },
    );
  }

  // Try multiple possible field names commonly used, including arrays
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
    // 2) Array-based keys: take the first non-empty string
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
}
