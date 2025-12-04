import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/cloudinary_service.dart';

class AdminBookingsScreen extends StatelessWidget {
  const AdminBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) {
      return const Center(child: Text('User tidak ditemukan'));
    }

    // Pertama ambil semua booth milik admin ini
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('booths')
          .where('createdBy', isEqualTo: currentUserId)
          .snapshots(),
      builder: (context, boothSnap) {
        if (boothSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final myBooths = boothSnap.data?.docs ?? [];
        if (myBooths.isEmpty) {
          return const Center(
            child: Text(
              'Anda belum memiliki booth.\nTambahkan booth terlebih dahulu.',
            ),
          );
        }

        // Ambil semua boothId milik admin ini
        final myBoothIds = myBooths.map((doc) => doc.id).toSet();
        final myBoothNames = myBooths
            .map((doc) => (doc.data()['name'] ?? '').toString())
            .toSet();

        // Sekarang ambil bookings
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('bookings')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snap.data?.docs ?? [];

            // Filter hanya booking yang boothId atau boothName ada di booth milik admin ini
            final filtered = docs.where((doc) {
              final d = doc.data();
              final rawStatus = (d['status'] ?? 'pending')
                  .toString()
                  .toLowerCase();
              final status = _normalizeStatus(rawStatus);

              // Skip rejected bookings
              if (status == 'rejected') return false;

              // Check if booking is for one of this admin's booths
              final boothId =
                  d['boothId'] as String? ?? d['boothRef'] as String?;
              final boothName =
                  d['boothName'] as String? ?? d['booth'] as String?;

              // Match by boothId or boothName
              return (boothId != null && myBoothIds.contains(boothId)) ||
                  (boothName != null && myBoothNames.contains(boothName));
            }).toList();

            if (filtered.isEmpty) {
              return const Center(
                child: Text('Belum ada booking untuk booth Anda.'),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final d = filtered[i].data();
                final id = filtered[i].id;
                final boothName = d['boothName'] ?? '-';
                final userName =
                    d['userName'] ?? d['userEmail'] ?? d['userId'] ?? '-';
                final userEmail = d['userEmail'] ?? '';
                final rawStatus = (d['status'] ?? 'pending')
                    .toString()
                    .toLowerCase();
                final status = _normalizeStatus(rawStatus);
                final dateText = d['date'] ?? d['bookingDate'];

                // Label status untuk ditampilkan
                String statusLabel = 'Menunggu Verifikasi';
                Color statusColor = Colors.orange;
                if (status == 'approved') {
                  statusLabel = 'Disetujui';
                  statusColor = Colors.green;
                } else if (status == 'rejected') {
                  statusLabel = 'Ditolak';
                  statusColor = Colors.red;
                } else if (status == 'selesai') {
                  statusLabel = 'Selesai';
                  statusColor = Colors.blue;
                }

                return Card(
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 1,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showBookingDialog(context, id, d),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // Booth Image Thumbnail
                          FutureBuilder<String?>(
                            future: _getBoothImageUrl(d),
                            builder: (bctx, bsnap) {
                              final url = (bsnap.data ?? '').trim();
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 72,
                                  height: 72,
                                  child: url.isNotEmpty
                                      ? Image.network(
                                          url,
                                          fit: BoxFit.cover,
                                          errorBuilder: (ctx, err, st) =>
                                              Image.asset(
                                                'assets/images/default_booth.jpg',
                                                fit: BoxFit.cover,
                                              ),
                                        )
                                      : Image.asset(
                                          'assets/images/default_booth.jpg',
                                          fit: BoxFit.cover,
                                        ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  boothName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.person,
                                      size: 16,
                                      color: Colors.black87,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        userName,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (userEmail.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const SizedBox(width: 22),
                                      Expanded(
                                        child: Text(
                                          userEmail,
                                          style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (dateText != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDateForDisplay(dateText),
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Status Label dan Menu
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: statusColor.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert,
                                  color: Colors.grey.shade700,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                                onSelected: (v) async {
                                  if (v != status) {
                                    if (v == 'rejected') {
                                      // Show dialog to select rejection reason
                                      await _showRejectionReasonDialog(
                                        context,
                                        id,
                                      );
                                    } else {
                                      await _changeBookingStatus(
                                        context,
                                        id,
                                        v,
                                      );
                                    }
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'pending',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.pending_outlined,
                                          size: 20,
                                          color: status == 'pending'
                                              ? Colors.orange
                                              : Colors.grey,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Menunggu Verifikasi',
                                          style: TextStyle(
                                            fontWeight: status == 'pending'
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'approved',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle_outline,
                                          size: 20,
                                          color: status == 'approved'
                                              ? Colors.green
                                              : Colors.grey,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Disetujui',
                                          style: TextStyle(
                                            fontWeight: status == 'approved'
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'rejected',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.cancel_outlined,
                                          size: 20,
                                          color: status == 'rejected'
                                              ? Colors.red
                                              : Colors.grey,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Ditolak',
                                          style: TextStyle(
                                            fontWeight: status == 'rejected'
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showRejectionReasonDialog(
    BuildContext context,
    String bookingId,
  ) async {
    const predefinedReasons = [
      'Ketentuan Pembayaran Tidak Dipenuhi',
      'Tidak Ada Konfirmasi Lanjutan',
      'Permintaan Pembatalan',
    ];

    String? selectedReason;
    final customReasonController = TextEditingController();
    bool isCustom = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Pilih Alasan Penolakan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Predefined reasons
                ...predefinedReasons.map(
                  (reason) => RadioListTile<String>(
                    title: Text(reason),
                    value: reason,
                    groupValue: selectedReason,
                    onChanged: (value) {
                      setState(() {
                        selectedReason = value;
                        isCustom = false;
                        customReasonController.clear();
                      });
                    },
                  ),
                ),
                // Custom reason option
                RadioListTile<String>(
                  title: const Text('Lainnya (tulis sendiri)'),
                  value: 'custom',
                  groupValue: isCustom ? 'custom' : selectedReason,
                  onChanged: (value) {
                    setState(() {
                      isCustom = true;
                      selectedReason = null;
                    });
                  },
                ),
                if (isCustom)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                    child: TextField(
                      controller: customReasonController,
                      decoration: InputDecoration(
                        hintText: 'Masukkan alasan penolakan',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      maxLines: 3,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                final reason = isCustom
                    ? customReasonController.text
                    : selectedReason;
                if (reason != null && reason.isNotEmpty) {
                  Navigator.pop(ctx, {'reason': reason, 'isCustom': isCustom});
                }
              },
              child: const Text('Tolak', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _changeBookingStatus(
        context,
        bookingId,
        'rejected',
        rejectionReason: result['reason'],
      );
    }

    customReasonController.dispose();
  }
}

Future<void> _changeBookingStatus(
  BuildContext context,
  String id,
  String newStatus, {
  String? rejectionReason,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final ref = FirebaseFirestore.instance.collection('bookings').doc(id);
  try {
    if (newStatus == 'rejected') {
      // Update booking with rejection reason instead of deleting
      await ref.set({
        'status': 'rejected',
        'rejectionReason': rejectionReason ?? 'Pesanan ditolak oleh admin',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      messenger.showSnackBar(
        SnackBar(content: Text('Booking ditolak. Alasan: $rejectionReason')),
      );
      return;
    }

    // For other statuses simply update the document
    await ref.set({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // If approved, auto-reject conflicting bookings
    if (newStatus == 'approved') {
      await _rejectConflictingBookings(id);
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Status diperbarui: $newStatus')),
    );
  } catch (e, st) {
    // Fallback: try to mark rejected if delete failed
    try {
      await ref.set({
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
    messenger.showSnackBar(
      SnackBar(content: Text('Gagal mengubah status: ${e.toString()}')),
    );
    // ignore: avoid_print
    print('Failed to change booking $id to $newStatus: $e\n$st');
  }
}

Future<void> _rejectConflictingBookings(String approvedBookingId) async {
  try {
    // Get the approved booking details
    final approvedDoc = await FirebaseFirestore.instance
        .collection('bookings')
        .doc(approvedBookingId)
        .get();

    if (!approvedDoc.exists) return;

    final approvedData = approvedDoc.data();
    if (approvedData == null) return;

    final boothName = approvedData['boothName'];
    final tanggal = approvedData['tanggal'];
    final jam = approvedData['jam'];

    if (boothName == null || tanggal == null || jam == null) return;

    // Get booth duration
    final boothDoc = await FirebaseFirestore.instance
        .collection('booths')
        .where('name', isEqualTo: boothName)
        .limit(1)
        .get();

    int approvedDurationMinutes = 60; // default 1 hour
    if (boothDoc.docs.isNotEmpty) {
      final boothData = boothDoc.docs.first.data();
      final duration = boothData['duration'];
      if (duration != null) {
        if (duration is int) {
          approvedDurationMinutes = duration;
        } else if (duration is String) {
          final parsed = int.tryParse(duration);
          if (parsed != null) {
            approvedDurationMinutes = parsed;
          }
        }
      }
    }

    // Parse approved booking time
    final jamParts = jam.split(':');
    final approvedHour = int.parse(jamParts[0]);
    final approvedMinute = int.parse(jamParts[1]);

    final approvedStart = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      approvedHour,
      approvedMinute,
    );
    final approvedEnd = approvedStart.add(
      Duration(minutes: approvedDurationMinutes),
    );

    // Find all pending bookings on the same booth and date
    final conflictingBookings = await FirebaseFirestore.instance
        .collection('bookings')
        .where('boothName', isEqualTo: boothName)
        .where('tanggal', isEqualTo: tanggal)
        .where('status', isEqualTo: 'pending')
        .get();

    // Reject all bookings that overlap with approved booking time range
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in conflictingBookings.docs) {
      if (doc.id != approvedBookingId) {
        final docData = doc.data();
        final pendingJam = docData['jam']?.toString() ?? '';
        if (pendingJam.isEmpty) continue;

        // Get pending booking duration
        int pendingDurationMinutes = 60; // default
        if (docData['duration'] != null) {
          if (docData['duration'] is int) {
            pendingDurationMinutes = docData['duration'] as int;
          } else if (docData['duration'] is String) {
            final parsed = int.tryParse(docData['duration'] as String);
            if (parsed != null) {
              pendingDurationMinutes = parsed;
            }
          }
        }

        final pendingJamParts = pendingJam.split(':');
        final pendingHour = int.parse(pendingJamParts[0]);
        final pendingMinute = int.parse(pendingJamParts[1]);

        final pendingStart = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
          pendingHour,
          pendingMinute,
        );
        final pendingEnd = pendingStart.add(
          Duration(minutes: pendingDurationMinutes),
        );

        // Check if time ranges overlap
        final hasOverlap =
            (approvedStart.isBefore(pendingEnd) ||
                approvedStart.isAtSameMomentAs(pendingEnd)) &&
            (approvedEnd.isAfter(pendingStart) ||
                approvedEnd.isAtSameMomentAs(pendingStart));

        if (hasOverlap) {
          batch.update(doc.reference, {
            'status': 'rejected',
            'updatedAt': FieldValue.serverTimestamp(),
            'rejectionReason': 'Jadwal sudah dipesan oleh pelanggan lain',
          });
        }
      }
    }

    await batch.commit();
  } catch (e) {
    // Silently fail - main approval already succeeded
    // ignore: avoid_print
    print('Failed to reject conflicting bookings: $e');
  }
}

String _normalizeStatus(String s) {
  final v = s.trim().toLowerCase();
  if (v == 'accepted' || v == 'approved') return 'approved';
  if (v == 'declined' || v == 'rejected') return 'rejected';
  return v;
}

String _formatDateForDisplay(dynamic raw) {
  if (raw == null) return '-';

  if (raw is Timestamp) {
    final dt = raw.toDate().toLocal();
    return DateFormat('d MMMM yyyy, HH:mm', 'id').format(dt);
  }

  if (raw is DateTime) {
    return DateFormat('d MMMM yyyy, HH:mm', 'id').format(raw.toLocal());
  }

  final s = raw.toString();
  final parsed = DateTime.tryParse(s);
  if (parsed != null) {
    return DateFormat('d MMMM yyyy, HH:mm', 'id').format(parsed.toLocal());
  }

  return s;
}

/// Resolve a path or URL to a usable HTTP download URL.
Future<String?> _resolveStorageUrlIfNeeded(String? path) async {
  if (path == null) return null;
  final p = path.trim();
  if (p.isEmpty) return null;
  if (p.startsWith('http')) return p;
  try {
    // If path looks like a gs:// or full storage URL, use refFromURL
    if (p.startsWith('gs://') || p.startsWith('https://')) {
      final ref = FirebaseStorage.instance.refFromURL(p);
      return await ref.getDownloadURL();
    }

    // Otherwise assume it's a storage path under the default bucket
    final ref = FirebaseStorage.instance.ref(p);
    return await ref.getDownloadURL();
  } catch (e) {
    // ignore errors and return null to fall back to placeholder
    // ignore: avoid_print
    print('Failed to resolve storage url for $path: $e');
    return null;
  }
}

// Try multiple possible field names commonly used for booth image
String _pickImageFieldFromData(Map<String, dynamic> data) {
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
    if (val is String && val.trim().isNotEmpty) return val.trim();
  }
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

/// Fetch booth image URL by looking up booth document (by id or name)
Future<String?> _getBoothImageUrl(Map<String, dynamic> booking) async {
  // 1) if booking explicitly contains an image/path/url, prefer that
  final bImg =
      (booking['boothImage'] ?? booking['image'] ?? booking['imageUrl'])
          as String?;
  if (bImg != null && bImg.trim().isNotEmpty) {
    return await _resolveStorageUrlIfNeeded(bImg);
  }

  // 2) try boothId or boothRef fields
  final boothId =
      booking['boothId'] as String? ?? booking['boothRef'] as String?;
  if (boothId != null && boothId.trim().isNotEmpty) {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('booths')
          .doc(boothId)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final img = _pickImageFieldFromData(data);
        if (img.isNotEmpty) return await _resolveStorageUrlIfNeeded(img);
      }
    } catch (_) {}
  }

  // 3) fallback: try to find booth by name
  final boothName = (booking['boothName'] ?? booking['booth'] ?? '').toString();
  if (boothName.isNotEmpty) {
    try {
      final q = await FirebaseFirestore.instance
          .collection('booths')
          .where('name', isEqualTo: boothName)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        final data = q.docs.first.data();
        final img = _pickImageFieldFromData(data);
        if (img.isNotEmpty) return await _resolveStorageUrlIfNeeded(img);
      }
    } catch (_) {}
  }

  return null;
}

Future<void> _showBookingDialog(
  BuildContext context,
  String id,
  Map<String, dynamic> info,
) async {
  final userPhoto =
      info['userPhoto'] as String? ??
      info['userAvatar'] as String? ??
      FirebaseAuth.instance.currentUser?.photoURL;
  final dateText = info['date'] ?? info['bookingDate'];

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return _BookingDetailDialog(
        bookingId: id,
        info: info,
        userPhoto: userPhoto,
        dateText: dateText,
      );
    },
  );
}

class _BookingDetailDialog extends StatefulWidget {
  final String bookingId;
  final Map<String, dynamic> info;
  final String? userPhoto;
  final dynamic dateText;

  const _BookingDetailDialog({
    required this.bookingId,
    required this.info,
    this.userPhoto,
    this.dateText,
  });

  @override
  State<_BookingDetailDialog> createState() => _BookingDetailDialogState();
}

class _BookingDetailDialogState extends State<_BookingDetailDialog> {
  List<String> _photoUrls = [];
  bool _isLoadingPhotos = true;
  bool _isUploading = false;
  String? _userPhotoUrl;
  bool _isLoadingUserPhoto = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _loadUserPhoto();
  }

  Future<void> _loadUserPhoto() async {
    setState(() => _isLoadingUserPhoto = true);
    try {
      // Ambil userId dari booking info
      final userId = widget.info['userId'] as String?;

      if (userId != null && userId.isNotEmpty) {
        // Query ke collection customers
        final userDoc = await FirebaseFirestore.instance
            .collection('customers')
            .doc(userId)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data();
          final photoUrl = userData?['photoUrl'] as String?;

          if (photoUrl != null && photoUrl.isNotEmpty) {
            setState(() {
              _userPhotoUrl = photoUrl;
              _isLoadingUserPhoto = false;
            });
            return;
          }
        }
      }

      // Fallback ke widget.userPhoto jika tidak ada di Firestore
      setState(() {
        _userPhotoUrl = widget.userPhoto;
        _isLoadingUserPhoto = false;
      });
    } catch (e) {
      debugPrint('Error loading user photo: $e');
      setState(() {
        _userPhotoUrl = widget.userPhoto;
        _isLoadingUserPhoto = false;
      });
    }
  }

  Future<void> _loadPhotos() async {
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
            _photoUrls = photos.map((e) => e.toString()).toList();
            _isLoadingPhotos = false;
          });
          return;
        }
      }
      setState(() => _isLoadingPhotos = false);
    } catch (e) {
      setState(() => _isLoadingPhotos = false);
      debugPrint('Error loading photos: $e');
    }
  }

  Future<void> _uploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked == null) return;

    setState(() => _isUploading = true);

    try {
      final url = await CloudinaryService.uploadImage(
        picked.path,
        folder: 'snapspace/booking_results',
      );

      if (url != null) {
        final newPhotos = [..._photoUrls, url];

        await FirebaseFirestore.instance
            .collection('bookings')
            .doc(widget.bookingId)
            .update({
              'photoResults': newPhotos,
              'status': 'selesai',
              'updatedAt': FieldValue.serverTimestamp(),
            });

        setState(() {
          _photoUrls = newPhotos;
          _isUploading = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Foto berhasil diupload dan booking selesai'),
            ),
          );
        }
      } else {
        throw Exception('Upload gagal');
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal upload foto: $e')));
      }
    }
  }

  Future<void> _deletePhoto(String url) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Foto'),
        content: const Text('Yakin ingin menghapus foto ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final newPhotos = _photoUrls.where((p) => p != url).toList();

      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .update({
            'photoResults': newPhotos,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      setState(() => _photoUrls = newPhotos);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Foto berhasil dihapus')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal hapus foto: $e')));
      }
    }
  }

  String _fmt(dynamic v) {
    if (v == null) return '-';
    if (v is Timestamp) return v.toDate().toString();
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Text(
                      'Informasi Booking',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  // Tombol close dialog tetap ada, logout dihapus
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Avatar: load from Firestore customers collection
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: _isLoadingUserPhoto
                        ? CircleAvatar(
                            radius: 36,
                            backgroundColor: const Color(0xFFEEEEEE),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : (_userPhotoUrl == null || _userPhotoUrl!.isEmpty)
                        ? CircleAvatar(
                            radius: 36,
                            backgroundColor: const Color(0xFFEEEEEE),
                            backgroundImage: const AssetImage(
                              'assets/images/default_avatar.jpg',
                            ),
                          )
                        : CircleAvatar(
                            radius: 36,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: NetworkImage(_userPhotoUrl!),
                            onBackgroundImageError: (_, __) {
                              // Jika error loading, fallback handled by default
                            },
                            child: null,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fmt(
                            widget.info['userName'] ??
                                widget.info['userEmail'] ??
                                '-',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _fmt(widget.info['userEmail'] ?? '-'),
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    FutureBuilder<String?>(
                      future: _getBoothImageUrl(widget.info),
                      builder: (bctx, bsnap) {
                        if (bsnap.connectionState == ConnectionState.waiting) {
                          return Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey.shade200,
                            ),
                          );
                        }
                        final url = (bsnap.data ?? '').trim();
                        if (url.isNotEmpty) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              url,
                              width: 68,
                              height: 68,
                              fit: BoxFit.cover,
                              loadingBuilder: (ctx, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  width: 68,
                                  height: 68,
                                  alignment: Alignment.center,
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.0,
                                      value: progress.expectedTotalBytes != null
                                          ? progress.cumulativeBytesLoaded /
                                                (progress.expectedTotalBytes ??
                                                    1)
                                          : null,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (ctx, err, st) => Image.asset(
                                'assets/images/default_booth.jpg',
                                width: 68,
                                height: 68,
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        }
                        // Fallback: use default booth asset so there's always an image
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'assets/images/default_booth.jpg',
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Booth',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _fmt(widget.info['boothName'] ?? '-'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.dateText != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatDateForDisplay(widget.dateText),
                        style: TextStyle(color: Colors.grey.shade800),
                      ),
                    ),
                  ],
                ),
              ],
              if (widget.info['createdAt'] != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tanggal Pemesanan: ${_formatDateForDisplay(widget.info['createdAt'])}',
                        style: const TextStyle(
                          color: Color.fromARGB(255, 14, 14, 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const Divider(height: 32),
              // Foto Hasil Photobooth Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Foto Hasil Photobooth',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  if (!_isUploading)
                    IconButton(
                      icon: const Icon(Icons.add_photo_alternate),
                      color: const Color(0xFF4981CF),
                      onPressed: _uploadPhoto,
                      tooltip: 'Unggah Foto',
                    )
                  else
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_isLoadingPhotos)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_photoUrls.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Belum ada foto hasil photobooth',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photoUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final url = _photoUrls[index];
                      return Stack(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _FullPhotoView(url: url),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                url,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 120,
                                  height: 120,
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.broken_image),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _deletePhoto(url),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.8),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullPhotoView extends StatelessWidget {
  final String url;

  const _FullPhotoView({required this.url});

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
            url,
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
