import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class BookingFormScreen extends StatefulWidget {
  final String boothName;
  final String? createdBy;
  final String? bookingId;
  final Map<String, dynamic>? existingData;

  const BookingFormScreen({
    super.key,
    required this.boothName,
    this.createdBy,
    this.bookingId,
    this.existingData,
  });

  @override
  State<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends State<BookingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _namaController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _status = 'pending';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // ✅ Inisialisasi data locale untuk format tanggal (wajib!)
    initializeDateFormatting('id_ID', null);

    if (widget.existingData != null) {
      _fillExistingData(widget.existingData!);
    } else if (widget.bookingId != null) {
      _loadBookingData();
    }
    // Prefill name field from signed-in user's profile when creating a new booking
    if (widget.existingData == null) {
      _loadProfileName();
    }
  }

  Future<Map<String, dynamic>> _validateBookingTime(
    DateTime date,
    TimeOfDay time,
  ) async {
    if (widget.createdBy == null || widget.createdBy!.isEmpty) {
      return {'isValid': true, 'message': ''};
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('photobooth_admins')
          .doc(widget.createdBy)
          .get();

      if (!doc.exists) {
        return {'isValid': true, 'message': ''};
      }

      final data = doc.data();
      if (data == null) {
        return {'isValid': true, 'message': ''};
      }

      // Check manual studio status
      final status = data['status'] ?? data['isOpen'] ?? data['open'];
      bool isManuallyOpen = true;
      if (status is bool) {
        isManuallyOpen = status;
      } else if (status is String) {
        isManuallyOpen = status.toLowerCase() == 'open';
      }

      if (!isManuallyOpen) {
        return {
          'isValid': false,
          'message': 'Studio sedang tutup. Silakan pilih waktu lain.',
        };
      }

      // Check operating hours
      final operatingHours = data['operatingHours'];
      if (operatingHours == null) {
        return {'isValid': true, 'message': ''};
      }

      final dayNames = [
        'Minggu',
        'Senin',
        'Selasa',
        'Rabu',
        'Kamis',
        'Jumat',
        'Sabtu',
      ];
      final bookingDay = dayNames[date.weekday % 7];

      final daySchedule = operatingHours[bookingDay];
      if (daySchedule == null) {
        return {
          'isValid': false,
          'message':
              'Studio tutup pada hari $bookingDay. Silakan pilih hari lain.',
        };
      }

      final isDayOpen =
          daySchedule['isOpen'] == true || daySchedule['isOpen'] == 'true';
      if (!isDayOpen) {
        return {
          'isValid': false,
          'message':
              'Studio tutup pada hari $bookingDay. Silakan pilih hari lain.',
        };
      }

      // Check if booking time is within operating hours
      final openTime = daySchedule['open']?.toString() ?? '09:00';
      final closeTime = daySchedule['close']?.toString() ?? '17:00';

      final openParts = openTime.split(':');
      final closeParts = closeTime.split(':');

      final bookingDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

      final openDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(openParts[0]),
        int.parse(openParts[1]),
      );

      var closeDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(closeParts[0]),
        int.parse(closeParts[1]),
      );

      // Check if 24 hours (00:00 - 00:00)
      if (openTime == '00:00' && closeTime == '00:00') {
        return {'isValid': true, 'message': ''};
      }

      // Handle case where close time is on the next day (e.g., 22:00 - 02:00)
      if (closeDateTime.isBefore(openDateTime)) {
        closeDateTime = closeDateTime.add(const Duration(days: 1));
      }

      if (bookingDateTime.isBefore(openDateTime) ||
          bookingDateTime.isAfter(closeDateTime) ||
          bookingDateTime.isAtSameMomentAs(closeDateTime)) {
        return {
          'isValid': false,
          'message':
              'Jam booking di luar jam operasional. Studio buka pukul $openTime - $closeTime pada hari $bookingDay.',
        };
      }

      return {'isValid': true, 'message': ''};
    } catch (e) {
      return {'isValid': true, 'message': ''};
    }
  }

  Future<Map<String, dynamic>> _checkConflictingBooking(
    String boothName,
    String date,
    String time,
  ) async {
    try {
      // Get booth duration (in minutes)
      final boothDoc = await FirebaseFirestore.instance
          .collection('booths')
          .where('name', isEqualTo: boothName)
          .limit(1)
          .get();

      int durationMinutes = 60; // default 1 hour
      if (boothDoc.docs.isNotEmpty) {
        final boothData = boothDoc.docs.first.data();
        final duration = boothData['duration'];
        if (duration != null) {
          // duration format could be string or number (in minutes)
          if (duration is int) {
            durationMinutes = duration;
          } else if (duration is String) {
            final parsed = int.tryParse(duration);
            if (parsed != null) {
              durationMinutes = parsed;
            }
          }
        }
      }

      // Parse booking time
      final timeParts = time.split(':');
      final bookingHour = int.parse(timeParts[0]);
      final bookingMinute = int.parse(timeParts[1]);

      // Calculate booking end time
      final bookingStart = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
        bookingHour,
        bookingMinute,
      );
      final bookingEnd = bookingStart.add(Duration(minutes: durationMinutes));

      // Check all approved bookings on the same booth and date
      final existingBookings = await FirebaseFirestore.instance
          .collection('bookings')
          .where('boothName', isEqualTo: boothName)
          .where('tanggal', isEqualTo: date)
          .where('status', isEqualTo: 'approved')
          .get();

      for (final doc in existingBookings.docs) {
        // If editing, skip if it's the same booking
        if (widget.bookingId != null && doc.id == widget.bookingId) {
          continue;
        }

        final docData = doc.data();
        final existingTime = docData['jam']?.toString() ?? '';
        if (existingTime.isEmpty) continue;

        final existingTimeParts = existingTime.split(':');
        final existingHour = int.parse(existingTimeParts[0]);
        final existingMinute = int.parse(existingTimeParts[1]);

        // Get existing booking duration
        int existingDurationMinutes = 60; // default
        if (docData['duration'] != null) {
          if (docData['duration'] is int) {
            existingDurationMinutes = docData['duration'] as int;
          } else if (docData['duration'] is String) {
            final parsed = int.tryParse(docData['duration'] as String);
            if (parsed != null) {
              existingDurationMinutes = parsed;
            }
          }
        }

        final existingStart = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
          existingHour,
          existingMinute,
        );
        final existingEnd = existingStart.add(
          Duration(minutes: existingDurationMinutes),
        );

        // Check if time ranges overlap
        final hasOverlap =
            (bookingStart.isBefore(existingEnd) ||
                bookingStart.isAtSameMomentAs(existingEnd)) &&
            (bookingEnd.isAfter(existingStart) ||
                bookingEnd.isAtSameMomentAs(existingStart));

        if (hasOverlap) {
          return {
            'hasConflict': true,
            'message':
                'Maaf, jadwal ini sudah dipesan oleh pelanggan lain. Silakan pilih waktu yang berbeda.',
          };
        }
      }

      return {'hasConflict': false, 'message': ''};
    } catch (e) {
      return {'hasConflict': false, 'message': ''};
    }
  }

  Future<void> _loadProfileName() async {
    try {
      // Don't override if existing name already provided (e.g., editing)
      if (_namaController.text.trim().isNotEmpty) return;

      final user = FirebaseAuth.instance.currentUser;
      String? name = user?.displayName;

      if ((name == null || name.isEmpty) && user?.uid != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .get();
        name =
            doc.data()?['name'] as String? ??
            doc.data()?['fullName'] as String?;
      }

      if (!mounted) return;
      if (name != null && name.isNotEmpty) {
        setState(() => _namaController.text = name ?? '');
      }
    } catch (_) {
      // ignore and leave controller as-is
    }
  }

  void _fillExistingData(Map<String, dynamic> data) {
    _namaController.text = data['nama'] ?? '';
    _selectedDate = _parseDate(data['tanggal']);
    _selectedTime = _parseTime(data['jam']);
    _status = data['status'] ?? 'waiting';
  }

  Future<void> _loadBookingData() async {
    final doc = await FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.bookingId)
        .get();
    if (doc.exists) {
      final data = doc.data()!;
      setState(() => _fillExistingData(data));
    }
  }

  DateTime _parseDate(String? dateStr) {
    try {
      return DateFormat('dd-MM-yyyy').parse(dateStr ?? '');
    } catch (_) {
      return DateTime.now();
    }
  }

  TimeOfDay _parseTime(String? timeStr) {
    try {
      final parts = timeStr!.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return TimeOfDay.now();
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2026),
      locale: const Locale('id', 'ID'),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      // Validate immediately if time is already selected
      if (_selectedTime != null) {
        final validation = await _validateBookingTime(picked, _selectedTime!);
        if (validation['isValid'] == false) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(validation['message'] as String),
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        }
      }
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
      // Validate immediately if date is already selected
      if (_selectedDate != null) {
        final validation = await _validateBookingTime(_selectedDate!, picked);
        if (validation['isValid'] == false) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(validation['message'] as String),
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        }
      }
    }
  }

  Future<void> _saveBooking() async {
    if (!_formKey.currentState!.validate() ||
        _selectedDate == null ||
        _selectedTime == null) {
      return;
    }

    // Validate booking time against studio operating hours
    final validation = await _validateBookingTime(
      _selectedDate!,
      _selectedTime!,
    );
    if (validation['isValid'] == false) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validation['message'] as String),
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    final formattedDate = DateFormat(
      'dd-MM-yyyy',
      'id_ID',
    ).format(_selectedDate!);
    final formattedTime =
        '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}';

    // Check for conflicting approved bookings
    final conflictCheck = await _checkConflictingBooking(
      widget.boothName,
      formattedDate,
      formattedTime,
    );
    if (conflictCheck['hasConflict'] == true) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(conflictCheck['message'] as String),
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    // Try fetching user's profile to enrich the booking payload
    String? userName;
    String? userEmail = user?.email;
    try {
      if (user?.uid != null) {
        final prof = await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .get();
        userName = prof.data()?['name'];
        userEmail ??= prof.data()?['email'];
      }
    } catch (_) {}

    final data = {
      'nama': _namaController.text,
      'userId': user?.uid,
      'userName': userName ?? user?.displayName,
      'userEmail': userEmail,
      'boothName': widget.boothName,
      'tanggal': formattedDate,
      'jam': formattedTime,
      // canonical status life-cycle used across app and admin
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (widget.bookingId == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('bookings').add(data);
      } else {
        await FirebaseFirestore.instance
            .collection('bookings')
            .doc(widget.bookingId)
            .update(data);
      }

      if (!mounted) return;
      final nav = Navigator.of(context);
      nav.pushReplacement(
        MaterialPageRoute(builder: (_) => const BookingSuccessScreen()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal menyimpan data: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteBooking() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff1E3A5F),
        title: const Text(
          'Hapus Booking?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Apakah Anda yakin ingin menghapus booking ini?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
            child: const Text(
              'Hapus',
              style: TextStyle(color: Color(0xff1E3A5F)),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && widget.bookingId != null) {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .delete();

      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _status == 'pending';
    final isNew = widget.bookingId == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Booking Baru' : 'Detail Booking'),
        backgroundColor: const Color(0xff4981CF),
        foregroundColor: Colors.white,
        actions: [
          if (!isNew && canEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteBooking,
            ),
        ],
      ),
      backgroundColor: const Color(0xffE9EEF5),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(13),
                  blurRadius: 8,
                  offset: const Offset(2, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Form Booking',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _namaController,
                  enabled: canEdit || isNew,
                  decoration: const InputDecoration(labelText: 'Nama Lengkap'),
                  validator: (v) =>
                      v!.isEmpty ? 'Harap isi nama lengkap' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  readOnly: true,
                  onTap: (canEdit || isNew) ? _selectDate : null,
                  decoration: InputDecoration(
                    labelText: _selectedDate == null
                        ? 'Pilih Tanggal'
                        : DateFormat(
                            'dd MMMM yyyy',
                            'id_ID',
                          ).format(_selectedDate!),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  readOnly: true,
                  onTap: (canEdit || isNew) ? _selectTime : null,
                  decoration: InputDecoration(
                    labelText: _selectedTime == null
                        ? 'Pilih Jam'
                        : _selectedTime!.format(context),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: (canEdit || isNew) && !_isLoading
                      ? _saveBooking
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff4981CF),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          isNew
                              ? 'Booking Sekarang'
                              : (canEdit
                                    ? 'Simpan Perubahan'
                                    : 'Tidak dapat diedit setelah diproses'),
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '*Pembayaran dilakukan cash di tempat.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BookingSuccessScreen extends StatefulWidget {
  const BookingSuccessScreen({super.key});

  @override
  State<BookingSuccessScreen> createState() => _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends State<BookingSuccessScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xff6EA8FF), Color(0xffA4C8FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 100),
              SizedBox(height: 20),
              Text(
                'Booking Berhasil',
                style: TextStyle(fontSize: 22, color: Colors.white),
              ),
              SizedBox(height: 10),
              Text(
                'Terima kasih',
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
