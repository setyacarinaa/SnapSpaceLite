import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class MapPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;
  final String? initialAddress;

  const MapPickerScreen({super.key, this.initialLocation, this.initialAddress});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late MapController mapController;
  LatLng? selectedLocation;
  String? selectedAddress;
  TextEditingController searchController = TextEditingController();
  bool isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    mapController = MapController();
    selectedLocation =
        widget.initialLocation ??
        const LatLng(-6.2088, 106.8456); // Jakarta center
    selectedAddress = widget.initialAddress;
  }

  @override
  void dispose() {
    mapController.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<String> _getAddressFromCoordinates(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;

        // Prioritas: subAdministrativeArea (kab/kota) > administrativeArea (provinsi) > country
        String locality =
            placemark.subAdministrativeArea ??
            placemark.administrativeArea ??
            placemark.country ??
            'Lokasi Tidak Dikenal';

        // Normalisasi: Tambahkan prefix "Kabupaten" jika belum ada dan bukan kota
        // Untuk konsistensi dengan data di indonesia_regions.json
        if (locality.isNotEmpty &&
            locality != 'Lokasi Tidak Dikenal' &&
            !locality.toLowerCase().startsWith('kabupaten') &&
            !locality.toLowerCase().startsWith('kota') &&
            placemark.administrativeArea != null) {
          // Cek apakah ini adalah nama provinsi (skip normalisasi untuk provinsi)
          final provinceNames = [
            'Aceh',
            'Bali',
            'Banten',
            'Bengkulu',
            'Gorontalo',
            'Jakarta',
            'Jambi',
            'Lampung',
            'Maluku',
            'Papua',
            'Riau',
            'Sulawesi',
            'Sumatera',
            'Jawa',
            'Kalimantan',
            'Nusa Tenggara',
            'Yogyakarta',
          ];
          final isProvince = provinceNames.any((p) => locality.contains(p));

          if (!isProvince) {
            locality = 'Kabupaten $locality';
          }
        }

        return locality;
      }
      return 'Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}';
    } catch (e) {
      return 'Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}';
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      setState(() => isLoadingLocation = true);

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final result = await Geolocator.requestPermission();
        if (result == LocationPermission.denied) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Izin lokasi ditolak')));
          setState(() => isLoadingLocation = false);
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final address = await _getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      setState(() {
        selectedLocation = LatLng(position.latitude, position.longitude);
        selectedAddress = address;
        isLoadingLocation = false;
      });

      mapController.move(selectedLocation!, 15);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal mendapatkan lokasi: $e')));
      setState(() => isLoadingLocation = false);
    }
  }

  void _confirmLocation() {
    if (selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan pilih lokasi di peta')),
      );
      return;
    }

    Navigator.pop(context, {
      'location': selectedLocation,
      'address':
          selectedAddress ??
          'Lat: ${selectedLocation!.latitude.toStringAsFixed(5)}, Lng: ${selectedLocation!.longitude.toStringAsFixed(5)}',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Lokasi'),
        backgroundColor: const Color(0xFF4981CF),
        elevation: 0,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter:
                  selectedLocation ?? const LatLng(-6.2088, 106.8456),
              initialZoom: 13,
              onTap: (tapPosition, latLng) async {
                setState(() {
                  selectedLocation = latLng;
                  selectedAddress = 'Memuat alamat...';
                });

                final address = await _getAddressFromCoordinates(
                  latLng.latitude,
                  latLng.longitude,
                );

                setState(() {
                  selectedAddress = address;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.snapspace',
              ),
              if (selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: selectedLocation!,
                      width: 60,
                      height: 60,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Color(0xFF4981CF),
                            size: 50,
                          ),
                          Positioned(
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4981CF),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'Lokasi',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // Top search/info bar
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Column(
              children: [
                if (selectedAddress != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      selectedAddress!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Bottom buttons
          Positioned(
            bottom: 20,
            left: 10,
            right: 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: isLoadingLocation ? null : _getCurrentLocation,
                  icon: isLoadingLocation
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.my_location),
                  label: const Text('Lokasi Saat Ini'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4981CF),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _confirmLocation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Konfirmasi Lokasi',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
