import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'booking_photo_view_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _loadProfileName();
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
    final bool isApproved = status == 'approved';
    final bool isRejected = status == 'rejected';
    final bool isDone = status == 'completed';

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
            _buildInfoTile(Icons.info, 'Status', status.toUpperCase()),

            const SizedBox(height: 40),
            // Tombol untuk View Photos
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDone
                      ? const Color(0xFF4981CF)
                      : Colors.grey.withAlpha(102),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 12,
                  ),
                ),
                onPressed: isDone
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BookingPhotoViewScreen(
                              bookingId: widget.bookingId,
                            ),
                          ),
                        );
                      }
                    : null,
                child: Text(
                  isDone
                      ? 'View Photos'
                      : (isApproved
                            ? 'Disetujui'
                            : (isRejected ? 'Ditolak' : 'Menunggu')),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
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
                      'Edit',
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
                      'Delete',
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
}
