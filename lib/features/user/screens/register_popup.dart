import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_popup.dart';
import 'waiting_verification.dart';

class RegisterPopup extends StatefulWidget {
  const RegisterPopup({super.key});

  @override
  State<RegisterPopup> createState() => _RegisterPopupState();
}

class _RegisterPopupState extends State<RegisterPopup> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _boothNameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _driveLinkController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String _selectedRole = 'user'; // 'user' or 'photobooth_admin'
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _nameMatchesKtp = false;
  FocusNode? _driveFocusNode;

  // Jam operasional per hari (format 24 jam)
  final Map<String, Map<String, String>> _operatingHours = {
    'Senin': {'open': '09:00', 'close': '17:00', 'isOpen': 'true'},
    'Selasa': {'open': '09:00', 'close': '17:00', 'isOpen': 'true'},
    'Rabu': {'open': '09:00', 'close': '17:00', 'isOpen': 'true'},
    'Kamis': {'open': '09:00', 'close': '17:00', 'isOpen': 'true'},
    'Jumat': {'open': '09:00', 'close': '17:00', 'isOpen': 'true'},
    'Sabtu': {'open': '09:00', 'close': '17:00', 'isOpen': 'true'},
    'Minggu': {'open': '09:00', 'close': '17:00', 'isOpen': 'false'},
  };

  Future<void> _pickTime(String day, String type) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(_operatingHours[day]![type]!.split(':')[0]),
        minute: int.parse(_operatingHours[day]![type]!.split(':')[1]),
      ),
    );
    if (picked != null) {
      setState(() {
        _operatingHours[day]![type] =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _register() async {
    if (_passwordController.text != _confirmController.text) {
      Fluttertoast.showToast(msg: "Password tidak cocok!");
      return;
    }

    if (_nameController.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: "Nama tidak boleh kosong!");
      return;
    }

    // For photobooth admins, require confirmation that the provided name
    // matches the KTP before allowing registration.
    if (_selectedRole == 'photobooth_admin' && !_nameMatchesKtp) {
      Fluttertoast.showToast(msg: "Silakan konfirmasi bahwa nama sesuai KTP.");
      return;
    }

    // If registering as photobooth admin, require KTP & selfie drive link
    if (_selectedRole == 'photobooth_admin' &&
        _driveLinkController.text.trim().isEmpty) {
      Fluttertoast.showToast(
        msg:
            "Link foto KTP & selfie wajib diisi untuk pendaftaran Admin Photobooth.",
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 🔹 Buat akun di Firebase Auth
      UserCredential userCred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      final user = userCred.user;
      if (user == null) {
        Fluttertoast.showToast(msg: "Registrasi gagal, coba lagi.");
        return;
      }

      // 🔹 Simpan data user ke Firestore
      final roleValue = _selectedRole == 'photobooth_admin'
          ? 'photobooth_admin'
          : 'customer';

      // Save into separate collections depending on role:
      // - customers: regular users/customers
      // - photobooth_admins: photobooth admin applicants (requires verification)
      final userDoc = {
        'uid': user.uid,
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'photoUrl': '',
        'role': roleValue,
        'created_at': FieldValue.serverTimestamp(),
      };

      if (roleValue == 'photobooth_admin') {
        userDoc['verified'] = false;
        userDoc['boothName'] = _boothNameController.text.trim();
        userDoc['location'] = _locationController.text.trim();
        userDoc['driveLink'] = _driveLinkController.text.trim();
        userDoc['operatingHours'] = _operatingHours;
        userDoc['status'] = 'open'; // default studio status
      }

      final collectionName = roleValue == 'photobooth_admin'
          ? 'photobooth_admins'
          : 'customers';
      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(user.uid)
          .set(userDoc);

      // Update display name in Firebase Auth
      await user.updateDisplayName(_nameController.text.trim());

      // Navigate: photobooth admins go to waiting screen, others go to login
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      if (roleValue == 'photobooth_admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WaitingForVerificationScreen(
              collectionName: 'photobooth_admins',
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPopup()),
        );
      }
    } on FirebaseAuthException catch (e) {
      // If the email is already in use, try to sign in with the provided
      // password. If sign-in succeeds, the user proves ownership and we can
      // delete that auth account and recreate a fresh one (so re-registration
      // succeeds). If sign-in fails, silently send a password-reset email and
      // redirect to login.
      if (e.code == 'email-already-in-use') {
        final email = _emailController.text.trim();
        final providedPassword = _passwordController.text.trim();
        try {
          // Try signing in with provided password to prove ownership
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: providedPassword,
          );

          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            // delete the existing auth user (user just proved ownership)
            await currentUser.delete();
          }

          // Now try creating the account again
          UserCredential newCred = await FirebaseAuth.instance
              .createUserWithEmailAndPassword(
                email: email,
                password: providedPassword,
              );

          final newUser = newCred.user;
          if (newUser != null) {
            final roleValue = _selectedRole == 'photobooth_admin'
                ? 'photobooth_admin'
                : 'user';
            final userDoc = {
              'uid': newUser.uid,
              'name': _nameController.text.trim(),
              'email': email,
              'photoUrl': '',
              'role': roleValue,
              'created_at': FieldValue.serverTimestamp(),
            };
            if (roleValue == 'photobooth_admin') userDoc['verified'] = false;
            await FirebaseFirestore.instance
                .collection('users')
                .doc(newUser.uid)
                .set(userDoc);
            await newUser.updateDisplayName(_nameController.text.trim());
          }

          if (!mounted) return;
          final nav = Navigator.of(context);
          nav.pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginPopup()),
          );
          return;
        } catch (signErr) {
          // Could not sign in with provided password (user forgot password)
          // or deletion/creation failed. Fall back to sending password reset
          // silently and redirect to login.
          try {
            await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
          } catch (_) {
            // ignore
          }
          if (!mounted) return;
          final nav = Navigator.of(context);
          nav.pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginPopup()),
          );
          return;
        }
      }

      Fluttertoast.showToast(
        msg: e.message ?? "Terjadi kesalahan saat registrasi.",
        toastLength: Toast.LENGTH_LONG,
      );
    } catch (e, st) {
      // Log unexpected errors to debug output (avoid using plain print)
      // Keep silent in the UI per requirement.
      // Use debugPrint which is more analyzer-friendly.
      // ignore: avoid_print
      debugPrint('Register error: $e');
      // ignore: avoid_print
      debugPrint(st.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _driveFocusNode = FocusNode()
      ..addListener(() {
        // Rebuild so hintStyle can react to focus changes.
        if (mounted) setState(() {});
      });
  }

  Future<void> _onRegisterPressed() async {
    // If the user is registering as photobooth_admin and hasn't provided
    // a Drive link yet, prompt for it after the user presses Register.
    if (_selectedRole == 'photobooth_admin' &&
        _driveLinkController.text.trim().isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Link Drive Foto (KTP & Selfie)'),
          content: SizedBox(
            width: MediaQuery.of(ctx).size.width * 0.86,
            child: TextField(
              focusNode: _driveFocusNode,
              autofocus: true,
              controller: _driveLinkController,
              maxLines: 1,
              decoration: InputDecoration(
                hintText:
                    'Masukkan link Drive yang bisa diakses (contoh: https://drive.google.com/...)',
                hintStyle: TextStyle(
                  color: Colors.black54,
                  fontSize: (_driveFocusNode?.hasFocus ?? false) ? 12 : 14,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              style: const TextStyle(color: Colors.black87, fontSize: 14),
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Batal'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(ctx).primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          if (_driveLinkController.text.trim().isEmpty) {
                            Fluttertoast.showToast(
                              msg:
                                  'Link Drive wajib diisi untuk Admin Photobooth',
                            );
                            return;
                          }
                          Navigator.pop(ctx, true);
                        },
                        child: const Text('Kirim'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      if (ok != true) {
        return; // user cancelled
      }
    }

    // Proceed with the normal registration flow
    await _register();
  }

  @override
  void dispose() {
    _driveFocusNode?.dispose();
    _nameController.dispose();
    _boothNameController.dispose();
    _locationController.dispose();
    _driveLinkController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 80),
            Image.asset('assets/images/logo.png', width: 100, height: 100),
            const SizedBox(height: 30),
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFB9CBEF),
                borderRadius: BorderRadius.all(Radius.circular(80)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Column(
                children: [
                  const Text(
                    "Daftar",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 30),
                  // Role selector: User or Admin Photobooth
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Daftar sebagai: '),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _selectedRole,
                        items: const [
                          DropdownMenuItem(
                            value: 'user',
                            child: Text('Pengguna / Pelanggan'),
                          ),
                          DropdownMenuItem(
                            value: 'photobooth_admin',
                            child: Text('Admin Photobooth'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedRole = v ?? 'user'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 🔹 Nama Lengkap
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: "Nama Lengkap",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Nama harus sesuai isi KTP',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // If registering as photobooth admin, collect booth details
                  if (_selectedRole == 'photobooth_admin') ...[
                    TextField(
                      controller: _boothNameController,
                      decoration: InputDecoration(
                        labelText: 'Nama Studio',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.storefront),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        labelText: 'Lokasi',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Jam Operasional
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 20,
                                color: Colors.blueAccent,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Jam Operasional',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ..._operatingHours.keys.map((day) {
                            final hours = _operatingHours[day]!;
                            final isOpen = hours['isOpen'] == 'true';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      day,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Checkbox(
                                    value: isOpen,
                                    onChanged: (val) {
                                      setState(() {
                                        _operatingHours[day]!['isOpen'] = val
                                            .toString();
                                      });
                                    },
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  Expanded(
                                    child: isOpen
                                        ? Row(
                                            children: [
                                              Expanded(
                                                child: InkWell(
                                                  onTap: () =>
                                                      _pickTime(day, 'open'),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                        color: Colors
                                                            .grey
                                                            .shade300,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      hours['open']!,
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                ),
                                                child: Text(
                                                  '-',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: InkWell(
                                                  onTap: () =>
                                                      _pickTime(day, 'close'),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                        color: Colors
                                                            .grey
                                                            .shade300,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      hours['close']!,
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        : const Text(
                                            'Tutup',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Confirmation: make sure name matches KTP before registering
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Saya pastikan nama di atas sesuai KTP',
                      ),
                      value: _nameMatchesKtp,
                      onChanged: (v) =>
                          setState(() => _nameMatchesKtp = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 8),
                    // Drive link input is collected after user taps Register
                    // to reduce visual clutter. It will be requested via
                    // a dialog when needed.
                  ],

                  // 🔹 Email
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: "Email",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 🔹 Password
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: "Password",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 🔹 Konfirmasi Password
                  TextField(
                    controller: _confirmController,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      labelText: "Konfirmasi Password",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // 🔹 Tombol Register
                  _isLoading
                      ? const CircularProgressIndicator()
                      : SizedBox(
                          width: double.infinity,
                          height: 45,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                            ),
                            onPressed: _onRegisterPressed,
                            child: const Text(
                              "Daftar",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                  const SizedBox(height: 20),

                  // 🔹 Pindah ke Login
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Sudah punya akun? "),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginPopup(),
                            ),
                          );
                        },
                        child: const Text(
                          "Login di sini",
                          style: TextStyle(color: Colors.blueAccent),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
