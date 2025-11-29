import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class VerificationDetailScreen extends StatefulWidget {
  final String userId;
  const VerificationDetailScreen({super.key, required this.userId});

  @override
  State<VerificationDetailScreen> createState() =>
      _VerificationDetailScreenState();
}

class _VerificationDetailScreenState extends State<VerificationDetailScreen> {
  final usersRef = FirebaseFirestore.instance.collection('users');
  bool _isProcessing = false;

  Future<void> _accept(Map<String, dynamic> data) async {
    if (mounted) {
      setState(() => _isProcessing = true);
    }
    try {
      await usersRef.doc(widget.userId).update({
        'verified': true,
        'verified_at': FieldValue.serverTimestamp(),
      });
      if (mounted) Fluttertoast.showToast(msg: 'Account accepted');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _decline() async {
    if (mounted) {
      setState(() => _isProcessing = true);
    }
    try {
      await usersRef.doc(widget.userId).delete();
      if (mounted) Fluttertoast.showToast(msg: 'Account declined and removed');
    } catch (_) {
      if (mounted) Fluttertoast.showToast(msg: 'Failed to remove account');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: usersRef.doc(widget.userId).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Error loading'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!.data() ?? {};
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (data['name'] as String?) ??
                      (data['boothName'] as String?) ??
                      '(no name)',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if ((data['boothName'] as String?) != null) ...[
                  Text('Nama Photobooth: ${data['boothName'] as String}'),
                  const SizedBox(height: 8),
                ],
                if ((data['location'] as String?) != null) ...[
                  Text('Lokasi: ${data['location']}'),
                  const SizedBox(height: 8),
                ],
                if ((data['driveLink'] as String?) != null) ...[
                  Text('Link Drive:'),
                  const SizedBox(height: 6),
                  SelectableText(data['driveLink'] as String),
                  const SizedBox(height: 16),
                ],
                const Spacer(),
                if (_isProcessing)
                  const Center(child: CircularProgressIndicator())
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () => _accept(data),
                        child: const Text('Accept'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                        ),
                        onPressed: _decline,
                        child: const Text('Decline'),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
