import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'edit_booking_screen.dart';

class DetailBookingScreen extends StatefulWidget {
  final String bookingId;
  final Map<String, dynamic> bookingData;

  const DetailBookingScreen({
    super.key,
    required this.bookingId,
    required this.bookingData,
  });

  @override
  State<DetailBookingScreen> createState() => _DetailBookingScreenState();
}

class _DetailBookingScreenState extends State<DetailBookingScreen> {
  String? _profileName;
  List<String> _photoResults = [];
  bool _isLoadingPhotos = true;

  @override
  void initState() {
    super.initState();
    _loadProfileName();
    _loadPhotoResults();
  }

  Future<void> _loadPhotoResults() async {
    setState(() => _isLoadingPhotos = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final photos = data?['photoResults'] as List<dynamic>?;
        if (photos != null) {
          setState(() {
            _photoResults = photos.map((e) => e.toString()).toList();
            _isLoadingPhotos = false;
          });
          return;
        }
      }
      setState(() => _isLoadingPhotos = false);
    } catch (e) {
      setState(() => _isLoadingPhotos = false);
      debugPrint('Error loading photo results: $e');
    }
  }

  Future<void> _loadProfileName() async {
    try {
      String? name;

      // Try to resolve the booking owner's uid from common fields
      final uidFromBooking =
          (widget.bookingData['userId'] ??
                  widget.bookingData['userUid'] ??
                  widget.bookingData['uid'])
              ?.toString();

      if (uidFromBooking != null && uidFromBooking.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uidFromBooking)
            .get();
        final data = doc.data();
        name = data?['name'] as String? ?? data?['fullName'] as String?;
      }

      // Fallback to signed-in user's displayName
      name ??= FirebaseAuth.instance.currentUser?.displayName;

      // Final fallback to bookingData fields
      name ??= (widget.bookingData['nama'] ?? widget.bookingData['name'])
          ?.toString();

      if (!mounted) return;
      setState(() => _profileName = name ?? '-');
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _profileName =
            (widget.bookingData['nama'] ?? widget.bookingData['name'])
                ?.toString() ??
            '-',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nama = (_profileName ?? (widget.bookingData['nama'] ?? '-'))
        .toString();
    final booth = (widget.bookingData['boothName'] ?? '-').toString();
    final tanggal = (widget.bookingData['tanggal'] ?? '-').toString();
    final status = (widget.bookingData['status'] ?? 'pending')
        .toString()
        .toLowerCase();

    final bool isPending = status == 'pending';

    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4981CF),
        title: const Text(
          'Detail Booking',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informasi Booking',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 15),
            _buildInfoTile(Icons.person, 'Nama User', nama),
            const SizedBox(height: 10),
            _buildInfoTile(Icons.store, 'Booth', booth),
            const SizedBox(height: 10),
            _buildInfoTile(Icons.calendar_month, 'Tanggal', tanggal),
            const SizedBox(height: 10),
            _buildInfoTile(
              Icons.info,
              'Status',
              status == 'pending'
                  ? 'Menunggu'
                  : status == 'approved'
                  ? 'Diterima'
                  : status == 'rejected'
                  ? 'Ditolak'
                  : status == 'completed'
                  ? 'Selesai'
                  : status.toUpperCase(),
            ),

            // Show rejection reason if booking was rejected
            if (status == 'rejected' &&
                widget.bookingData['rejectionReason'] != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alasan Penolakan:',
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.bookingData['rejectionReason'].toString(),
                            style: TextStyle(
                              color: Colors.red.shade800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 30),

            // Section Foto Hasil Photobooth
            if (_isLoadingPhotos)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_photoResults.isEmpty) ...[
              // Belum ada foto - tampilkan info pembayaran hanya jika tidak ditolak
              if (status != 'rejected')
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.shade200,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange.shade700,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'Menunggu pembayaran langsung di tempat',
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ] else ...[
              // Sudah ada foto - tampilkan tombol lihat dan download
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.green.shade200,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green.shade700,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Foto hasil photobooth sudah tersedia!',
                            style: TextStyle(
                              color: Colors.green.shade900,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4981CF),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 15,
                            ),
                          ),
                          icon: const Icon(
                            Icons.photo_library,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Lihat Foto',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _PhotoResultsViewScreen(
                                  photoUrls: _photoResults,
                                  bookingId: widget.bookingId,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 15,
                            ),
                          ),
                          icon: const Icon(Icons.download, color: Colors.white),
                          label: const Text(
                            'Unduh',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          onPressed: () => _downloadAllPhotos(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],

            const SizedBox(height: 20),

            // Tombol Edit & Delete hanya muncul saat waiting
            if (isPending) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.edit, color: Colors.white),
                    label: const Text(
                      'Ubah',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditBookingScreen(
                            bookingId: widget.bookingId,
                            bookingData: widget.bookingData,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.delete, color: Colors.white),
                    label: const Text(
                      'Hapus',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _showDeleteDialog(),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF4981CF), size: 28),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus Booking'),
          content: const Text(
            'Apakah kamu yakin ingin menghapus booking ini? Tindakan ini tidak dapat dibatalkan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('bookings')
                    .doc(widget.bookingId)
                    .delete();

                if (!mounted) return;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Booking berhasil dihapus'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                });
              },
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadAllPhotos() async {
    if (_photoResults.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mengunduh foto...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      Directory? directory;

      if (Platform.isAndroid) {
        // Untuk Android, gunakan Downloads folder
        directory = Directory('/storage/emulated/0/Download');

        // Jika tidak ada, coba path alternatif
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        // Untuk iOS, gunakan app documents directory
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      // Jika directory masih null, tampilkan error
      if (directory == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal mengakses folder penyimpanan'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      int successCount = 0;

      for (int i = 0; i < _photoResults.length; i++) {
        final url = _photoResults[i];
        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final fileName =
              'SnapSpace_${widget.bookingId}_${i + 1}_$timestamp.jpg';
          final file = File('${directory.path}/$fileName');
          await file.writeAsBytes(response.bodyBytes);
          successCount++;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$successCount foto berhasil diunduh ke folder Downloads',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengunduh foto: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// Screen untuk melihat foto hasil photobooth
class _PhotoResultsViewScreen extends StatelessWidget {
  final List<String> photoUrls;
  final String bookingId;

  const _PhotoResultsViewScreen({
    required this.photoUrls,
    required this.bookingId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4981CF),
        title: const Text(
          'Foto Hasil Photobooth',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: photoUrls.isEmpty
          ? const Center(
              child: Text(
                'Belum ada foto',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: photoUrls.length,
              itemBuilder: (context, index) {
                final url = photoUrls[index];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _FullPhotoView(photoUrl: url),
                        ),
                      );
                    },
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// Fullscreen photo view
class _FullPhotoView extends StatelessWidget {
  final String photoUrl;

  const _FullPhotoView({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(
            photoUrl,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
          ),
        ),
      ),
    );
  }
}
