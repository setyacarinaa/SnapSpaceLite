import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:snapspace/features/user/screens/opening_screen.dart';
import '../../../core/cloudinary_service.dart';

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

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController();
    emailController = TextEditingController();
    locationController = TextEditingController();
    boothNameController = TextEditingController();
    _loadUserData();
    if (user != null) {
      _userSub = firestore
          .collection('photobooth_admins')
          .doc(user!.uid)
          .snapshots()
          .listen((docSnap) {
            if (!mounted) return;
            if (isEditing) return;
            final data = docSnap.data();
            setState(() {
              nameController.text =
                  (data?['name'] as String?) ?? user!.displayName ?? '';
              emailController.text =
                  (data?['email'] as String?) ?? user!.email ?? '';
              locationController.text = (data?['location'] as String?) ?? '';
              boothNameController.text = (data?['boothName'] as String?) ?? '';
              photoUrl = (data?['photoUrl'] as String?) ?? user!.photoURL;
            });
          });
    }
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
        'boothName': enteredBoothName,
        'role': 'photobooth_admin',
        'updated_at': FieldValue.serverTimestamp(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      body: Padding(
        padding: const EdgeInsets.all(20),
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
}
