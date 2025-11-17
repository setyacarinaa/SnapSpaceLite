import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_popup.dart';

class RegisterPopup extends StatefulWidget {
  const RegisterPopup({super.key});

  @override
  State<RegisterPopup> createState() => _RegisterPopupState();
}

class _RegisterPopupState extends State<RegisterPopup> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String _selectedRole = 'user'; // 'user' or 'photobooth_admin'
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  Future<void> _register() async {
    if (_passwordController.text != _confirmController.text) {
      Fluttertoast.showToast(msg: "Password tidak cocok!");
      return;
    }

    if (_nameController.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: "Nama tidak boleh kosong!");
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
          : 'user';
      final userDoc = {
        'uid': user.uid,
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'photoUrl': '',
        'role': roleValue,
        'created_at': FieldValue.serverTimestamp(),
      };

      // photobooth admins need verification by system admin
      if (roleValue == 'photobooth_admin') {
        userDoc['verified'] = false;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(userDoc);

      // 🔹 Update display name di Firebase Auth
      await user.updateDisplayName(_nameController.text.trim());

      // 🔹 Beri notifikasi sukses
      Fluttertoast.showToast(
        msg: "Registrasi berhasil! Silakan login.",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
      );

      // 🔹 Tunggu sejenak biar proses Firestore selesai & navigasi smooth
      if (context.mounted) {
        await Future.delayed(const Duration(seconds: 1));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPopup()),
        );
      }
    } on FirebaseAuthException catch (e) {
      Fluttertoast.showToast(
        msg: e.message ?? "Terjadi kesalahan saat registrasi.",
        toastLength: Toast.LENGTH_LONG,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                    "Register",
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
                            child: Text('User / Customer'),
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
                  const SizedBox(height: 20),

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
                            onPressed: _register,
                            child: const Text(
                              "Register",
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
