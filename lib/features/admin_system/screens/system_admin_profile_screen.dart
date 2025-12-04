import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SystemAdminProfileScreen extends StatefulWidget {
  final VoidCallback? onBackPressed;

  const SystemAdminProfileScreen({super.key, this.onBackPressed});

  @override
  State<SystemAdminProfileScreen> createState() =>
      _SystemAdminProfileScreenState();
}

class _SystemAdminProfileScreenState extends State<SystemAdminProfileScreen>
    with SingleTickerProviderStateMixin {
  final customersRef = FirebaseFirestore.instance.collection('customers');
  final photoboothAdminsRef = FirebaseFirestore.instance.collection(
    'photobooth_admins',
  );
  final currentUser = FirebaseAuth.instance.currentUser;
  late TabController _tabController;
  String _sectionTitle = 'Semua Akun';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {
        _sectionTitle = switch (_tabController.index) {
          0 => 'Semua Akun',
          1 => 'Akun Admin Photobooth',
          2 => 'Akun Pelanggan',
          _ => 'Semua Akun',
        };
      });
    });
  }

  Future<void> _deleteAccount(String userId, String userName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Akun'),
        content: Text('Apakah Anda yakin ingin menghapus "$userName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Check and delete from customers collection
        final customerDoc = await customersRef.doc(userId).get();
        if (customerDoc.exists) {
          await customersRef.doc(userId).delete();
        }

        // Check and delete from photobooth_admins collection
        final photoboothDoc = await photoboothAdminsRef.doc(userId).get();
        if (photoboothDoc.exists) {
          await photoboothAdminsRef.doc(userId).delete();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Akun berhasil dihapus')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Gagal menghapus akun: $e')));
        }
      }
    }
  }

  Future<void> _openDriveLink(String url) async {
    try {
      // Ensure the URL has a proper scheme
      String finalUrl = url.trim();
      if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
        finalUrl = 'https://$finalUrl';
      }

      final uri = Uri.parse(finalUrl);

      // Try to launch the URL
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Gagal membuka link')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Tidak dapat membuka link. Pastikan browser terinstall.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal: ${e.toString()}')));
      }
    }
  }

  void _showAccountDetail(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final name =
        data['name'] as String? ??
        data['boothName'] as String? ??
        'Tidak diketahui';
    final email = data['email'] as String? ?? 'Tidak ada email';
    final location = data['location'] as String? ?? '';
    final driveLink = data['driveLink'] as String? ?? '';
    final photoUrl = data['photoUrl'] as String? ?? '';
    final isPhotobooth =
        data['role'] == 'photobooth_admin' || data.containsKey('boothName');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Informasi Akun',
                      style: TextStyle(
                        fontSize: 20,
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
                            ? Icon(
                                data['role'] == 'photobooth_admin' ||
                                        data.containsKey('boothName')
                                    ? Icons.store
                                    : Icons.person,
                                size: 60,
                                color: Colors.grey,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildDetailRow(
                      isPhotobooth ? 'Nama Photobooth' : 'Nama',
                      name,
                      isPhotobooth ? Icons.store : Icons.person,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow('Email', email, Icons.email),
                    if (isPhotobooth && location.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow('Lokasi', location, Icons.location_on),
                    ],
                    if (driveLink.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDetailRowWithLink(
                        'Link Drive',
                        driveLink,
                        Icons.link,
                        () => _openDriveLink(driveLink),
                      ),
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteAccount(doc.id, name);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6BA3E8),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Hapus',
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EBF2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF6BA3E8), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRowWithLink(
    String label,
    String value,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFE8EBF2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF6BA3E8), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6BA3E8),
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new, color: Color(0xFF6BA3E8), size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      body: SafeArea(
        child: Column(
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
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      if (widget.onBackPressed != null) {
                        widget.onBackPressed!();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  const Icon(Icons.person, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  const Text(
                    'Pengguna',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Section Header with Dropdown
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _sectionTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<int>(
                        value: _tabController.index,
                        underline: const SizedBox(),
                        isDense: true,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 0,
                            child: Text('Lihat Semua'),
                          ),
                          DropdownMenuItem(value: 1, child: Text('Admin')),
                          DropdownMenuItem(value: 2, child: Text('Pelanggan')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _tabController.animateTo(value);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAllAccountsList(),
                  _buildAdminAccountsList(),
                  _buildCustomerAccountsList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllAccountsList() {
    // Use broadcast streams to avoid "already been listened to" issues
    return StreamBuilder<QuerySnapshot>(
      stream: customersRef.snapshots(),
      builder: (context, customersSnapshot) {
        if (customersSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return StreamBuilder<QuerySnapshot>(
          stream: photoboothAdminsRef.snapshots(),
          builder: (context, pbSnapshot) {
            if (pbSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final customersDocs = customersSnapshot.data?.docs ?? [];
            // Only show verified photobooth admins
            final pbDocs = (pbSnapshot.data?.docs ?? []).where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return (data['verified'] as bool? ?? false) == true;
            }).toList();
            final allDocs = [...customersDocs, ...pbDocs];

            if (allDocs.isEmpty) {
              return const Center(child: Text('Tidak ada akun ditemukan'));
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: allDocs.length,
              itemBuilder: (context, index) {
                final doc = allDocs[index];
                final data = doc.data() as Map<String, dynamic>;
                final name =
                    data['name'] as String? ??
                    data['boothName'] as String? ??
                    'Admin ${index + 1}';
                final isPhotobooth =
                    data['role'] == 'photobooth_admin' ||
                    data.containsKey('boothName');

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.shade300,
                      child: Icon(
                        isPhotobooth ? Icons.store : Icons.person,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: () => _showAccountDetail(doc),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF6BA3E8),
                      ),
                      child: const Text('Lihat'),
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

  Widget _buildAdminAccountsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: photoboothAdminsRef
          .where('verified', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final adminDocs = snapshot.data?.docs ?? [];

        if (adminDocs.isEmpty) {
          return const Center(child: Text('Tidak ada akun admin ditemukan'));
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: adminDocs.length,
          itemBuilder: (context, index) {
            final doc = adminDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final name =
                data['name'] as String? ??
                data['boothName'] as String? ??
                'Admin ${index + 1}';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundColor: Colors.grey.shade300,
                  child: Icon(Icons.store, color: Colors.grey.shade600),
                ),
                title: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                trailing: TextButton(
                  onPressed: () => _showAccountDetail(doc),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6BA3E8),
                  ),
                  child: const Text('Lihat'),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCustomerAccountsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: customersRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final customerDocs = snapshot.data?.docs ?? [];

        if (customerDocs.isEmpty) {
          return const Center(
            child: Text('Tidak ada akun pelanggan ditemukan'),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: customerDocs.length,
          itemBuilder: (context, index) {
            final doc = customerDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final name = data['name'] as String? ?? 'Cust ${index + 1}';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundColor: Colors.grey.shade300,
                  child: Icon(Icons.person, color: Colors.grey.shade600),
                ),
                title: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                trailing: TextButton(
                  onPressed: () => _showAccountDetail(doc),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6BA3E8),
                  ),
                  child: const Text('Lihat'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
