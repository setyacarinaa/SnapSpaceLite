import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher.dart';

class VerificationDetailScreen extends StatefulWidget {
  final String userId;
  const VerificationDetailScreen({super.key, required this.userId});

  @override
  State<VerificationDetailScreen> createState() =>
      _VerificationDetailScreenState();
}

class _VerificationDetailScreenState extends State<VerificationDetailScreen> {
  final customersRef = FirebaseFirestore.instance.collection('customers');
  final photoboothAdminsRef = FirebaseFirestore.instance.collection(
    'photobooth_admins',
  );
  bool _isProcessing = false;

  Future<DocumentSnapshot?> _getUserDoc() async {
    // Try customers collection first
    final customerDoc = await customersRef.doc(widget.userId).get();
    if (customerDoc.exists) {
      return customerDoc;
    }
    // Try photobooth_admins collection
    final photoboothDoc = await photoboothAdminsRef.doc(widget.userId).get();
    if (photoboothDoc.exists) {
      return photoboothDoc;
    }
    return null;
  }

  Future<void> _accept(Map<String, dynamic> data) async {
    setState(() => _isProcessing = true);
    try {
      // Update in customers collection if exists
      final customerDoc = await customersRef.doc(widget.userId).get();
      if (customerDoc.exists) {
        await customersRef.doc(widget.userId).update({
          'verified': true,
          'verified_at': FieldValue.serverTimestamp(),
        });
      }

      // Update in photobooth_admins collection if exists
      final photoboothDoc = await photoboothAdminsRef.doc(widget.userId).get();
      if (photoboothDoc.exists) {
        await photoboothAdminsRef.doc(widget.userId).update({
          'verified': true,
          'verified_at': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Fluttertoast.showToast(msg: 'Akun berhasil diterima');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(msg: 'Gagal menerima akun: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _decline() async {
    setState(() => _isProcessing = true);
    try {
      // Delete from customers collection if exists
      final customerDoc = await customersRef.doc(widget.userId).get();
      if (customerDoc.exists) {
        await customersRef.doc(widget.userId).delete();
      }

      // Delete from photobooth_admins collection if exists
      final photoboothDoc = await photoboothAdminsRef.doc(widget.userId).get();
      if (photoboothDoc.exists) {
        await photoboothAdminsRef.doc(widget.userId).delete();
      }

      if (mounted) {
        Fluttertoast.showToast(msg: 'Akun ditolak dan dihapus');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(msg: 'Gagal menghapus akun: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _openDriveLink(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          Fluttertoast.showToast(msg: 'Tidak dapat membuka link');
        }
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(msg: 'Gagal membuka link: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      body: SafeArea(
        child: FutureBuilder<DocumentSnapshot?>(
          future: _getUserDoc(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Gagal memuat data: ${snap.error}'));
            }
            if (!snap.hasData || snap.data == null || !snap.data!.exists) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snap.data!.data() as Map<String, dynamic>? ?? {};
            final boothName = data['boothName'] as String? ?? 'Tidak diketahui';
            final location = data['location'] as String? ?? 'Tidak ada lokasi';
            final driveLink = data['driveLink'] as String? ?? '';
            final photoUrl = data['photoUrl'] as String? ?? '';

            return Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF6BA3E8),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Verifikasi',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Informasi Akun',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Photo
                        Center(
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(12),
                              image: photoUrl.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(photoUrl),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: photoUrl.isEmpty
                                ? const Icon(
                                    Icons.store,
                                    size: 60,
                                    color: Colors.grey,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Booth Name
                        _buildInfoCard(
                          'Nama Photobooth',
                          boothName,
                          Icons.store,
                        ),
                        const SizedBox(height: 12),
                        // Location
                        _buildInfoCard('Lokasi', location, Icons.location_on),
                        const SizedBox(height: 12),
                        // Drive Link
                        if (driveLink.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.link,
                                      color: Color(0xFF6BA3E8),
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Link Drive',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () => _openDriveLink(driveLink),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF6BA3E8,
                                      ).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.cloud,
                                          color: Color(0xFF6BA3E8),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            driveLink,
                                            style: const TextStyle(
                                              color: Color(0xFF6BA3E8),
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Action Buttons
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: _isProcessing
                      ? const Center(child: CircularProgressIndicator())
                      : Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _accept(data),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6BA3E8),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Terima',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _decline,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6BA3E8),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Tolak',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF6BA3E8), size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
