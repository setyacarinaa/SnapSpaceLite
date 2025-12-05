import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:snapspace/features/user/screens/image_preview_screen.dart';
import 'package:snapspace/features/user/screens/booking_form_screen.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

class BoothDetailScreen extends StatefulWidget {
  final DocumentReference boothRef;
  const BoothDetailScreen({super.key, required this.boothRef});

  @override
  State<BoothDetailScreen> createState() => _BoothDetailScreenState();
}

class _BoothDetailScreenState extends State<BoothDetailScreen> {
  Future<String> _getStudioName(String? createdBy) async {
    if (createdBy == null || createdBy.isEmpty) return '-';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('photobooth_admins')
          .doc(createdBy)
          .get();
      if (doc.exists) {
        final data = doc.data();
        return data?['boothName'] ?? data?['name'] ?? '-';
      }
    } catch (e) {
      return '-';
    }
    return '-';
  }

  Future<Map<String, dynamic>> _getStudioStatus(String? createdBy) async {
    if (createdBy == null || createdBy.isEmpty) {
      return {'isOpen': false, 'message': 'Informasi studio tidak tersedia'};
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('photobooth_admins')
          .doc(createdBy)
          .get();

      if (!doc.exists) {
        return {'isOpen': false, 'message': 'Studio tidak ditemukan'};
      }

      final data = doc.data();
      if (data == null) {
        return {'isOpen': false, 'message': 'Data studio tidak tersedia'};
      }

      // Check manual studio status
      final status = data['status'] ?? data['isOpen'] ?? data['open'];
      bool isManuallyOpen = true;
      if (status is bool) {
        isManuallyOpen = status;
      } else if (status is String) {
        isManuallyOpen = status.toLowerCase() == 'open';
      }

      // Check operating hours
      final operatingHours = data['operatingHours'];

      // Get list of open days
      final dayNames = [
        'Minggu',
        'Senin',
        'Selasa',
        'Rabu',
        'Kamis',
        'Jumat',
        'Sabtu',
      ];
      final openDays = <String>[];
      if (operatingHours != null) {
        for (var day in dayNames) {
          final schedule = operatingHours[day];
          if (schedule != null) {
            final isDayOpen =
                schedule['isOpen'] == true || schedule['isOpen'] == 'true';
            if (isDayOpen) {
              openDays.add(day);
            }
          }
        }
      }

      if (!isManuallyOpen) {
        if (openDays.isEmpty) {
          return {'isOpen': false, 'message': 'Studio sedang tutup'};
        }
        return {
          'isOpen': false,
          'message': 'Studio sedang tutup. Buka: ${openDays.join(", ")}',
        };
      }
      if (operatingHours == null) {
        return {'isOpen': true, 'message': ''}; // No schedule means open
      }

      final now = DateTime.now();
      final currentDay = dayNames[now.weekday % 7];

      final daySchedule = operatingHours[currentDay];
      if (daySchedule == null) {
        if (openDays.isEmpty) {
          return {'isOpen': false, 'message': 'Studio tutup hari ini'};
        }
        return {
          'isOpen': false,
          'message': 'Studio tutup hari ini. Buka: ${openDays.join(", ")}',
        };
      }

      final isDayOpen =
          daySchedule['isOpen'] == true || daySchedule['isOpen'] == 'true';
      if (!isDayOpen) {
        if (openDays.isEmpty) {
          return {'isOpen': false, 'message': 'Studio tutup hari ini'};
        }
        return {
          'isOpen': false,
          'message': 'Studio tutup hari ini. Buka: ${openDays.join(", ")}',
        };
      }

      // Parse open and close times
      try {
        final openTime = daySchedule['open']?.toString() ?? '09:00';
        final closeTime = daySchedule['close']?.toString() ?? '17:00';

        final openParts = openTime.split(':');
        final closeParts = closeTime.split(':');

        final openDateTime = DateTime(
          now.year,
          now.month,
          now.day,
          int.parse(openParts[0]),
          int.parse(openParts[1]),
        );
        var closeDateTime = DateTime(
          now.year,
          now.month,
          now.day,
          int.parse(closeParts[0]),
          int.parse(closeParts[1]),
        );

        // Check if 24 hours (00:00 - 00:00)
        if (openTime == '00:00' && closeTime == '00:00') {
          return {'isOpen': true, 'message': ''};
        }

        // Handle case where close time is on the next day (e.g., 22:00 - 02:00)
        if (closeDateTime.isBefore(openDateTime)) {
          closeDateTime = closeDateTime.add(const Duration(days: 1));
        }

        final isWithinHours =
            (now.isAfter(openDateTime) || now.isAtSameMomentAs(openDateTime)) &&
            now.isBefore(closeDateTime);

        if (!isWithinHours) {
          String additionalInfo = '';
          if (openDays.isNotEmpty) {
            additionalInfo = ' Hari buka: ${openDays.join(", ")}';
          }
          return {
            'isOpen': false,
            'message':
                'Studio buka pukul $openTime - $closeTime.$additionalInfo',
          };
        }

        return {'isOpen': true, 'message': ''};
      } catch (e) {
        return {'isOpen': false, 'message': 'Jadwal operasional tidak valid'};
      }
    } catch (e) {
      return {'isOpen': false, 'message': 'Gagal memeriksa status studio'};
    }
  }

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
            return const Center(child: Text('Data studio tidak ditemukan.'));
          }
          final data = (snapshot.data!.data() as Map<String, dynamic>);
          final name = data['name'] ?? 'Tanpa Nama';
          final price = data['price'] ?? 0;
          final duration = data['duration'] ?? '-';
          final description = data['description'] ?? '-';
          final capacity = data['capacity'] ?? '-';
          final createdBy = data['createdBy'] as String?;
          final imageUrl = _pickImageField(data);

          return FutureBuilder<Map<String, dynamic>>(
            future:
                Future.wait([
                  _getStudioName(createdBy),
                  _getStudioStatus(createdBy),
                ]).then(
                  (results) => {
                    'studioName': results[0] as String,
                    'statusInfo': results[1] as Map<String, dynamic>,
                  },
                ),
            builder: (context, combinedSnapshot) {
              final studioName =
                  (combinedSnapshot.data?['studioName'] as String?) ?? '-';
              final statusInfo =
                  (combinedSnapshot.data?['statusInfo']
                      as Map<String, dynamic>?) ??
                  {'isOpen': false, 'message': 'Memuat...'};
              final isOpen = statusInfo['isOpen'] as bool;
              final statusMessage = statusInfo['message'] as String;

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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Image
                              Center(
                                child: GestureDetector(
                                  onTap: () {
                                    if (imageUrl.isNotEmpty) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ImagePreviewScreen(
                                            imageUrl: imageUrl,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: _BoothDetailImage(
                                      urlOrPath: imageUrl,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Nama Booth
                              _buildInfoRow('Nama Booth:', name, isBold: true),
                              const SizedBox(height: 12),

                              // Nama Studio
                              _buildInfoRow('Nama Studio:', studioName),
                              const SizedBox(height: 12),

                              // Status Studio
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(
                                    width: 100,
                                    child: Text(
                                      'Status:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isOpen
                                            ? Colors.green.shade50
                                            : Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isOpen
                                              ? Colors.green.shade300
                                              : Colors.red.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isOpen
                                                ? Icons.check_circle
                                                : Icons.cancel,
                                            size: 16,
                                            color: isOpen
                                                ? Colors.green.shade700
                                                : Colors.red.shade700,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              isOpen ? 'Buka' : statusMessage,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: isOpen
                                                    ? Colors.green.shade700
                                                    : Colors.red.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Harga
                              _buildInfoRow(
                                'Harga:',
                                'Rp $price / sesi ($duration)',
                              ),
                              const SizedBox(height: 12),

                              // Kapasitas
                              _buildInfoRow('Kapasitas:', '$capacity'),
                              const SizedBox(height: 12),

                              // Deskripsi
                              const Text(
                                'Deskripsi:',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                description,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Tombol Lihat Lokasi
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: OutlinedButton.icon(
                                  onPressed: () => _showLocationMap(
                                    data['location'] as String?,
                                    createdBy,
                                  ),
                                  icon: const Icon(Icons.location_on),
                                  label: const Text('Lihat Lokasi di Peta'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF4981CF),
                                    side: const BorderSide(
                                      color: Color(0xFF4981CF),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Tombol Booking
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: isOpen
                                      ? () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => BookingFormScreen(
                                                boothName: name,
                                                createdBy: createdBy,
                                              ),
                                            ),
                                          );
                                        }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isOpen
                                        ? const Color(0xFF4981CF)
                                        : Colors.grey.shade300,
                                    disabledBackgroundColor:
                                        Colors.grey.shade300,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: Text(
                                    isOpen
                                        ? 'Booking Sekarang'
                                        : 'Studio Sedang Tutup',
                                    style: TextStyle(
                                      color: isOpen
                                          ? Colors.white
                                          : Colors.grey.shade600,
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
          );
        },
      ),
      // Bottom navigation is provided by MainNavigation; avoid duplicating here.
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  void _showLocationMap(String? location, String? createdBy) async {
    if (createdBy == null) return;

    try {
      final adminDoc = await FirebaseFirestore.instance
          .collection('photobooth_admins')
          .doc(createdBy)
          .get();

      if (!adminDoc.exists) return;

      final adminData = adminDoc.data();
      final latitude = adminData?['latitude'] as double? ?? -6.2088;
      final longitude = adminData?['longitude'] as double? ?? 106.8456;

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Lokasi Studio',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(latitude, longitude),
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.snapspace',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(latitude, longitude),
                          width: 60,
                          height: 60,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Color(0xFF4981CF),
                                size: 50,
                              ),
                              Positioned(
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4981CF),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text(
                                    'Studio',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Lokasi: ${location ?? "Tidak tersedia"}',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal memuat lokasi: $e')));
    }
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
