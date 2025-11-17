import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:snapspace/features/user/screens/opening_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool isEditing = false;
  bool _isSaving = false;
  final user = FirebaseAuth.instance.currentUser;
  final firestore = FirebaseFirestore.instance;

  late TextEditingController nameController;
  late TextEditingController emailController;

  String? photoUrl;
  File? _imageFile;
  XFile? _pickedXFile;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController();
    emailController = TextEditingController();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (user == null) return;

    final doc = await firestore.collection('users').doc(user!.uid).get();
    final data = doc.data();

    if (data != null) {
      setState(() {
        nameController.text =
            (data['name'] as String?) ?? user!.displayName ?? '';
        emailController.text = (data['email'] as String?) ?? user!.email ?? '';
        photoUrl = (data['photoUrl'] as String?) ?? user!.photoURL;
      });
    } else {
      // Jika dokumen belum ada, tampilkan fallback dari FirebaseAuth agar tidak kosong
      setState(() {
        nameController.text =
            user!.displayName ?? (user!.email?.split('@').first ?? '');
        emailController.text = user!.email ?? '';
        photoUrl = user!.photoURL;
      });
    }
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 85, // kompresi moderat
      maxWidth: 1080,
      maxHeight: 1080,
    );

    if (picked != null) {
      setState(() {
        _pickedXFile = picked;
        _imageFile = File(
          picked.path,
        ); // untuk preview lokal (jika path tersedia)
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
      final bytes = await picked.readAsBytes();
      // Tentukan ekstensi & content-type sederhana
      final path = picked.path;
      final dot = path.lastIndexOf('.');
      final ext = (dot != -1 ? path.substring(dot + 1) : 'jpg').toLowerCase();
      String contentType = 'image/jpeg';
      if (ext == 'png') contentType = 'image/png';
      if (ext == 'webp') contentType = 'image/webp';

      final fileName = '${user!.uid}.${ext.isEmpty ? 'jpg' : ext}';
      // Pakai instance default agar konsisten dengan konfigurasi Firebase di app
      final storage = FirebaseStorage.instance;
      final ref = storage.ref().child('profile_images').child(fileName);

      final task = await ref
          .putData(bytes, SettableMetadata(contentType: contentType))
          .timeout(const Duration(seconds: 45));

      // Ambil URL dari snapshot.ref dan retry singkat jika perlu (eventual consistency)
      int attempts = 0;
      while (true) {
        try {
          final url = await task.ref.getDownloadURL().timeout(
            const Duration(seconds: 8),
          );
          return url;
        } on TimeoutException {
          if (attempts < 2) {
            attempts++;
            continue;
          }
          rethrow;
        } on FirebaseException catch (e) {
          if (e.code == 'object-not-found' && attempts < 2) {
            attempts++;
            await Future.delayed(const Duration(milliseconds: 250));
            continue;
          }
          rethrow;
        }
      }
    } catch (e) {
      // Tampilkan alasan error supaya mudah didiagnosa (rules/bucket/konfigurasi)
      print("Upload failed: $e");
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
      if (mounted) setState(() => _isSaving = true);
      // Ambil data saat ini untuk fallback agar tidak menimpa dengan string kosong
      final currentSnap = await firestore
          .collection('users')
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
          // Jangan lanjut menimpa field lain jika upload gagal
          return;
        }
        newPhotoUrl = url;
      }

      final enteredName = nameController.text.trim();
      final enteredEmail = emailController.text.trim();

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
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (newPhotoUrl != null && newPhotoUrl.isNotEmpty) {
        updateData['photoUrl'] = newPhotoUrl;
      }

      await firestore
          .collection('users')
          .doc(user!.uid)
          .set(updateData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 12));

      // Sinkronkan displayName di Firebase Auth jika nama efektif tersedia
      if (effectiveName.isNotEmpty) {
        await user!
            .updateDisplayName(effectiveName)
            .timeout(const Duration(seconds: 10));
      }

      setState(() {
        photoUrl = newPhotoUrl;
        isEditing = false;
        _imageFile = null;
        _pickedXFile = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile updated successfully")),
      );
    } on TimeoutException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Operasi timeout. Periksa koneksi dan coba lagi.'),
          ),
        );
      }
    } catch (e) {
      print("Error updating profile: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memperbarui profil.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const OpeningScreen()),
    );
  }

  Future<void> _removePhoto() async {
    if (user == null) return;
    try {
      if (photoUrl != null && photoUrl!.isNotEmpty) {
        try {
          final storage = FirebaseStorage.instanceFor(
            bucket: 'snapspace-lite.appspot.com',
          );
          final ref = storage.refFromURL(photoUrl!);
          await ref.delete();
        } catch (_) {
          // abaikan bila file tidak ada atau tidak bisa dihapus
        }
      }

      await firestore.collection('users').doc(user!.uid).set({
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

  Future<void> _changeEmail() async {
    if (user == null) return;

    final newEmailController = TextEditingController(text: user!.email ?? '');
    final passwordController = TextEditingController();
    bool obscure = true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: const Text('Ubah Email'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: newEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email baru'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Password saat ini',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setSt(() => obscure = !obscure),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Simpan'),
              ),
            ],
          ),
        );
      },
    );

    if (proceed != true) return;

    final newEmail = newEmailController.text.trim();
    final password = passwordController.text.trim();
    if (newEmail.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email dan password wajib diisi.')),
      );
      return;
    }

    try {
      setState(() => _isSaving = true);
      final credential = EmailAuthProvider.credential(
        email: user!.email!,
        password: password,
      );
      await user!.reauthenticateWithCredential(credential);
      await user!.updateEmail(newEmail);

      await firestore.collection('users').doc(user!.uid).set({
        'email': newEmail,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        emailController.text = newEmail;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email berhasil diperbarui.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Gagal mengubah email.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal mengubah email: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4981CF),
        title: const Text(
          'Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
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
                  if (isEditing)
                    InkWell(
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
                ],
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Personal Information",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(height: 10),
              _buildTextField(Icons.person, nameController, 'Name'),
              const SizedBox(height: 12),
              _buildTextField(
                Icons.email,
                emailController,
                'Email',
                enabled: false,
              ),
              const SizedBox(height: 20),
              if (isEditing)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving ? null : _changeEmail,
                        icon: const Icon(Icons.alternate_email),
                        label: const Text('Ubah Email'),
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
                  if (_isSaving) return; // cegah double tap
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
                        isEditing ? 'Save' : 'Edit',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 30),
              TextButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  "Logout",
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
      // Bottom navigation is provided by MainNavigation; avoid duplicating here.
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
