import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'detail_booking_screen.dart';

class RiwayatBookingScreen extends StatelessWidget {
  const RiwayatBookingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4981CF),
        title: const Text(
          'Riwayat Booking',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: uid == null
          ? const Center(
              child: Text(
                'Anda belum login.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('bookings')
                  .where('userId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Belum ada data booking.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }

                // Urutkan secara lokal berdasarkan createdAt (desc) agar tidak perlu index gabungan
                final bookings = List<QueryDocumentSnapshot>.from(
                  snapshot.data!.docs,
                );
                bookings.sort((a, b) {
                  final ta = (a['createdAt'] is Timestamp)
                      ? (a['createdAt'] as Timestamp)
                      : (a['updatedAt'] is Timestamp)
                      ? (a['updatedAt'] as Timestamp)
                      : Timestamp(0, 0);
                  final tb = (b['createdAt'] is Timestamp)
                      ? (b['createdAt'] as Timestamp)
                      : (b['updatedAt'] is Timestamp)
                      ? (b['updatedAt'] as Timestamp)
                      : Timestamp(0, 0);
                  // descending
                  return tb.compareTo(ta);
                });

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  itemCount: bookings.length,
                  itemBuilder: (context, index) {
                    final data = bookings[index].data() as Map<String, dynamic>;
                    final boothName = data['boothName'] ?? '-';
                    final tanggal = data['tanggal'] ?? '-';
                    final jam = data['jam'] ?? '-';
                    final rawStatus = (data['status'] ?? 'pending').toString();
                    final status = _statusLabel(rawStatus);
                    final statusColor = _statusColor(rawStatus);

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetailBookingScreen(
                              bookingId: bookings[index].id,
                              bookingData: data,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.2),
                              blurRadius: 5,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4981CF).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.store,
                              color: Color(0xFF4981CF),
                            ),
                          ),
                          title: Text(
                            boothName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF333333),
                            ),
                          ),
                          subtitle: Text(
                            '$tanggal • $jam',
                            style: const TextStyle(color: Colors.black54),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
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
}

String _statusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'pending':
      return 'Menunggu';
    case 'approved':
      return 'Disetujui';
    case 'rejected':
      return 'Ditolak';
    case 'completed':
      return 'Selesai';
    // backward-compat synonyms
    case 'waiting':
      return 'Menunggu';
    case 'selesai':
      return 'Selesai';
    case 'dibatalkan':
      return 'Ditolak';
    case 'proses':
      return 'Disetujui';
    default:
      return status;
  }
}

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'pending':
      return Colors.grey;
    case 'approved':
      return Colors.blue;
    case 'rejected':
      return Colors.red;
    case 'completed':
      return Colors.green;
    // backward-compat synonyms
    case 'waiting':
      return Colors.grey;
    case 'selesai':
      return Colors.green;
    case 'dibatalkan':
      return Colors.red;
    case 'proses':
      return Colors.blue;
    default:
      return Colors.grey;
  }
}
