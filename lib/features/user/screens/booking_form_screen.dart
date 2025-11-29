import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class BookingFormScreen extends StatefulWidget {
  final String boothName;
  final String? bookingId;
  final Map<String, dynamic>? existingData;

  const BookingFormScreen({
    super.key,
    required this.boothName,
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
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _saveBooking() async {
    if (!_formKey.currentState!.validate() ||
        _selectedDate == null ||
        _selectedTime == null) {
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
