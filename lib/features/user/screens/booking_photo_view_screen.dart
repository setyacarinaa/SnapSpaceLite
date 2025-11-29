import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';

class BookingPhotoViewScreen extends StatefulWidget {
  final String bookingId; // ambil ID booking untuk cari fotonya

  const BookingPhotoViewScreen({super.key, required this.bookingId});

  @override
  State<BookingPhotoViewScreen> createState() => _BookingPhotoViewScreenState();
}

class _BookingPhotoViewScreenState extends State<BookingPhotoViewScreen> {
  List<String> photoUrls = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookingPhotos();
  }

  Future<void> _loadBookingPhotos() async {
    try {
      final storageRef = FirebaseStorage.instance.ref().child(
        'bookings/${widget.bookingId}/photos',
      );

      final listResult = await storageRef.listAll();
      if (listResult.items.isEmpty) {
        setState(() {
          photoUrls = [];
          isLoading = false;
        });
        return;
      }

      final urls = await Future.wait(
        listResult.items.map((item) => item.getDownloadURL()),
      );

      setState(() {
        photoUrls = urls;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      debugPrint('Error loading photos: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4981CF),
        title: const Text(
          'Foto Booking',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadBookingPhotos,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : photoUrls.isEmpty
          ? const Center(
              child: Text(
                'Belum ada foto untuk booking ini.',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: photoUrls.length,
              itemBuilder: (context, index) {
                final url = photoUrls[index];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FullPhotoViewScreen(photoUrl: url),
                        ),
                      );
                    },
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class FullPhotoViewScreen extends StatelessWidget {
  final String photoUrl;

  const FullPhotoViewScreen({super.key, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        // No additional actions here; keep AppBar minimal and transparent.
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(
            photoUrl,
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
