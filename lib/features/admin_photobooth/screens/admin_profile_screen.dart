import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:snapspace/features/user/screens/opening_screen.dart';
import '../../../core/cloudinary_service.dart';
import '../../shared/screens/map_picker_screen.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  bool isEditing = false;
  bool _isSaving = false;
  final user = FirebaseAuth.instance.currentUser;
  final firestore = FirebaseFirestore.instance;

  late TextEditingController nameController;
  late TextEditingController emailController;
  late TextEditingController locationController;
  late TextEditingController boothNameController;

  String? photoUrl;
  File? _imageFile;
  XFile? _pickedXFile;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  double? _latitude;
  double? _longitude;

  late Map<String, Map<String, dynamic>> operatingHours;
  static const List<String> dayNames = [
    'Minggu',
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
  ];

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController();
    emailController = TextEditingController();
    locationController = TextEditingController();
    boothNameController = TextEditingController();
    _initializeOperatingHours();
    // Load initial data first, then setup listener
    _loadUserData().then((_) {
      if (user != null && mounted) {
        _userSub = firestore
            .collection('photobooth_admins')
            .doc(user!.uid)
            .snapshots()
            .listen((docSnap) {
              if (!mounted) return;
              final data = docSnap.data();
              // Always load operating hours
              _loadOperatingHours(data);
              // But only update other fields if not editing
              if (!isEditing) {
                setState(() {
                  nameController.text =
                      (data?['name'] as String?) ?? user!.displayName ?? '';
                  emailController.text =
                      (data?['email'] as String?) ?? user!.email ?? '';
                  locationController.text =
                      (data?['location'] as String?) ?? '';
                  boothNameController.text =
                      (data?['boothName'] as String?) ?? '';
                  photoUrl = (data?['photoUrl'] as String?) ?? user!.photoURL;
                });
              }
            });
      }
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    nameController.dispose();
    emailController.dispose();
    locationController.dispose();
    boothNameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (user == null) return;

    final doc = await firestore
        .collection('photobooth_admins')
        .doc(user!.uid)
        .get();
    final data = doc.data();
    if (!mounted) return;
    if (data != null) {
      setState(() {
        nameController.text =
            (data['name'] as String?) ?? user!.displayName ?? '';
        emailController.text = (data['email'] as String?) ?? user!.email ?? '';
        locationController.text = (data['location'] as String?) ?? '';
        boothNameController.text = (data['boothName'] as String?) ?? '';
        photoUrl = (data['photoUrl'] as String?) ?? user!.photoURL;
        _latitude = (data['latitude'] as num?)?.toDouble() ?? -6.2088;
        _longitude = (data['longitude'] as num?)?.toDouble() ?? 106.8456;
        _loadOperatingHours(data);
      });
      return;
    }

    setState(() {
      nameController.text =
          user!.displayName ?? (user!.email?.split('@').first ?? '');
      emailController.text = user!.email ?? '';
      photoUrl = user!.photoURL;
    });
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1080,
      maxHeight: 1080,
    );

    if (picked != null) {
      setState(() {
        _pickedXFile = picked;
        _imageFile = File(picked.path);
      });
    }
  }

  Future<void> _showImageSourcePicker() async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamera'),
              onTap: () async {
                Navigator.pop(context);
                await _pickImageFromSource(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeri'),
              onTap: () async {
                Navigator.pop(context);
                await _pickImageFromSource(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<String?> _uploadImageFromPicker(XFile picked) async {
    try {
      final url = await CloudinaryService.uploadImage(
        picked.path,
        folder: 'snapspace/avatars',
      );
      return url;
    } catch (e) {
      debugPrint("Upload failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload gagal: $e')));
      }
      return null;
    }
  }

  Future<void> _saveProfile() async {
    try {
      if (mounted) {
        setState(() => _isSaving = true);
      }

      final currentSnap = await firestore
          .collection('photobooth_admins')
          .doc(user!.uid)
          .get()
          .timeout(const Duration(seconds: 12));
      final currentData = currentSnap.data() ?? <String, dynamic>{};

      String? newPhotoUrl = photoUrl;
      if (_pickedXFile != null) {
        final url = await _uploadImageFromPicker(_pickedXFile!);
        if (url == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Upload foto gagal. Coba lagi.')),
            );
          }
          return;
        }
        newPhotoUrl = url;
      }

      final enteredName = nameController.text.trim();
      final enteredEmail = emailController.text.trim();
      final enteredLocation = locationController.text.trim();
      final enteredBoothName = boothNameController.text.trim();

      final effectiveName = enteredName.isNotEmpty
          ? enteredName
          : (currentData['name'] as String?) ??
                user!.displayName ??
                (user!.email?.split('@').first ?? '');
      final effectiveEmail = enteredEmail.isNotEmpty
          ? enteredEmail
          : (currentData['email'] as String?) ?? user!.email ?? '';

      final updateData = <String, dynamic>{
        'uid': user!.uid,
        'name': effectiveName,
        'email': effectiveEmail,
        'location': enteredLocation,
        'latitude': _latitude ?? -6.2088,
        'longitude': _longitude ?? 106.8456,
        'boothName': enteredBoothName,
        'role': 'photobooth_admin',
        'updated_at': FieldValue.serverTimestamp(),
        'operatingHours': operatingHours,
      };
      if (newPhotoUrl != null && newPhotoUrl.isNotEmpty) {
        updateData['photoUrl'] = newPhotoUrl;
      }

      await firestore
          .collection('photobooth_admins')
          .doc(user!.uid)
          .set(updateData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 12));

      if (effectiveName.isNotEmpty) {
        await user!
            .updateDisplayName(effectiveName)
            .timeout(const Duration(seconds: 10));
      }

      if (mounted) {
        setState(() {
          photoUrl = newPhotoUrl;
          isEditing = false;
          _imageFile = null;
          _pickedXFile = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profil berhasil diperbarui")),
        );
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Operasi timeout. Periksa koneksi dan coba lagi.'),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error updating profile: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memperbarui profil.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const OpeningScreen()),
    );
  }

  Future<void> _removePhoto() async {
    if (user == null) return;
    try {
      await firestore.collection('photobooth_admins').doc(user!.uid).set({
        'photoUrl': '',
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        photoUrl = '';
        _imageFile = null;
        _pickedXFile = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Foto profil dihapus.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal menghapus foto: $e')));
      }
    }
  }

  Future<void> _resetPassword() async {
    if (user == null) return;

    final targetEmail = (user!.email ?? emailController.text).trim();
    if (targetEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email tidak tersedia untuk melakukan reset.'),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Kata Sandi'),
        content: Text('Kirim tautan reset password ke $targetEmail?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kirim'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      setState(() => _isSaving = true);
      await FirebaseAuth.instance.sendPasswordResetEmail(email: targetEmail);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tautan reset telah dikirim ke $targetEmail')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Gagal mengirim tautan reset.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengirim tautan reset: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _initializeOperatingHours() {
    operatingHours = {
      'Minggu': {'isOpen': true, 'open': '00:00', 'close': '00:00'},
      'Senin': {'isOpen': true, 'open': '00:00', 'close': '00:00'},
      'Selasa': {'isOpen': true, 'open': '00:00', 'close': '00:00'},
      'Rabu': {'isOpen': true, 'open': '00:00', 'close': '00:00'},
      'Kamis': {'isOpen': true, 'open': '00:00', 'close': '00:00'},
      'Jumat': {'isOpen': true, 'open': '00:00', 'close': '00:00'},
      'Sabtu': {'isOpen': true, 'open': '00:00', 'close': '00:00'},
    };
  }

  void _loadOperatingHours(Map<String, dynamic>? data) {
    if (data == null) return;
    final hours = data['operatingHours'] as Map<String, dynamic>?;
    if (hours != null) {
      bool hasChanges = false;
      hours.forEach((day, schedule) {
        if (schedule is Map<String, dynamic> &&
            operatingHours.containsKey(day)) {
          final newData = {
            'isOpen': schedule['isOpen'] as bool? ?? true,
            'open': schedule['open'] as String? ?? '00:00',
            'close': schedule['close'] as String? ?? '00:00',
          };
          // Check if data has changed
          if (operatingHours[day] != newData) {
            operatingHours[day] = newData;
            hasChanges = true;
          }
        }
      });
      // Only call setState if there are actual changes
      if (hasChanges && mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _selectTime(String day, String timeType) async {
    final currentTime = timeType == 'open'
        ? operatingHours[day]!['open']
        : operatingHours[day]!['close'];
    final timeParts = (currentTime as String).split(':');
    final initialTime = TimeOfDay(
      hour: int.parse(timeParts[0]),
      minute: int.parse(timeParts[1]),
    );

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (selectedTime != null) {
      setState(() {
        final timeStr =
            '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
        operatingHours[day]![timeType] = timeStr;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: _imageFile != null
                        ? FileImage(_imageFile!)
                        : (photoUrl != null && photoUrl!.isNotEmpty
                                  ? NetworkImage(photoUrl!)
                                  : const AssetImage(
                                      'assets/images/default_avatar.jpg',
                                    ))
                              as ImageProvider,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: InkWell(
                      onTap: _showImageSourcePicker,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: const Icon(
                          Icons.edit,
                          size: 20,
                          color: Color(0xFF4981CF),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Informasi Pribadi",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(height: 10),
              _buildTextField(Icons.person, nameController, 'Nama'),
              const SizedBox(height: 12),
              _buildTextField(
                Icons.email,
                emailController,
                'Email',
                enabled: false,
              ),
              const SizedBox(height: 12),
              _buildTextField(Icons.store, boothNameController, 'Nama Studio'),
              const SizedBox(height: 12),
              _buildTextField(Icons.location_on, locationController, 'Lokasi'),
              if (isEditing) ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MapPickerScreen(
                          initialLocation:
                              _latitude != null && _longitude != null
                              ? LatLng(_latitude!, _longitude!)
                              : null,
                          initialAddress: locationController.text.isEmpty
                              ? null
                              : locationController.text,
                        ),
                      ),
                    );
                    if (result != null) {
                      setState(() {
                        _latitude = result['location'].latitude;
                        _longitude = result['location'].longitude;
                        locationController.text = result['address'];
                      });
                    }
                  },
                  icon: const Icon(Icons.map),
                  label: const Text('Ubah Lokasi di Peta'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4981CF),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Jam Operasional",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(height: 10),
              _buildOperatingHoursSection(),
              const SizedBox(height: 20),
              if (isEditing)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving ? null : _resetPassword,
                        icon: const Icon(Icons.lock_reset),
                        label: const Text('Atur Ulang Kata Sandi'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving ? null : _removePhoto,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Hapus Foto'),
                      ),
                    ),
                  ],
                ),
              if (isEditing) const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4981CF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 50,
                    vertical: 12,
                  ),
                ),
                onPressed: () {
                  if (_isSaving) return;
                  if (isEditing) {
                    _saveProfile();
                  } else {
                    setState(() => isEditing = true);
                  }
                },
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : Text(
                        isEditing ? 'Simpan' : 'Edit',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 30),
              TextButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  "Keluar",
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    IconData icon,
    TextEditingController controller,
    String label, {
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: isEditing && enabled,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF4981CF)),
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildOperatingHoursSection() {
    return Column(
      children: dayNames.map((day) {
        final hours = operatingHours[day]!;
        final isOpen = hours['isOpen'] as bool;
        final openTime = hours['open'] as String;
        final closeTime = hours['close'] as String;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          day,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (isEditing)
                        Switch(
                          value: isOpen,
                          onChanged: (value) {
                            setState(() {
                              operatingHours[day]!['isOpen'] = value;
                            });
                          },
                        )
                      else
                        Text(
                          isOpen ? 'Buka' : 'Tutup',
                          style: TextStyle(
                            color: isOpen ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                  if (isOpen) ...[
                    const SizedBox(height: 8),
                    if (isEditing)
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => _selectTime(day, 'open'),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: 'Buka',
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      openTime,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: () => _selectTime(day, 'close'),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: 'Tutup',
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      closeTime,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '$openTime - $closeTime',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                  ] else if (!isEditing)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Tutup',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
