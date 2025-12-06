import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:snapspace/features/user/screens/booth_detail_screen.dart';
import 'package:snapspace/features/user/screens/image_preview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? userName;
  String? _photoUrl;
  Query<Map<String, dynamic>>? boothsQuery;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  bool _useCollectionGroup = false;
  Timer? _statusUpdateTimer;
  bool _triedUsersFallback = false;

  final TextEditingController _searchController = TextEditingController();
  String? _selectedCity;
  final List<String> _availableCities = [];
  final Map<String, String> _imageUrlCache = {}; // cache resolved storage URLs
  final Map<String, String> _adminLocationCache =
      {}; // cache adminId -> location string
  final Map<String, String> _adminStudioNameCache =
      {}; // cache adminId -> studio name (boothName)
  final Map<String, bool> _adminStatusCache =
      {}; // cache adminId -> studio open/close status
  final Map<String, Map<String, Map<String, String>>>
  _adminOperatingHoursCache = {}; // cache adminId -> operating hours per day
  String _selectedSort = 'Rekomendasi';
  final List<String> _sortOptions = [
    'Rekomendasi',
    'Terbaru',
    'Nama A-Z',
    'Nama Z-A',
    'Harga Terendah',
    'Harga Tertinggi',
  ];

  // Load regions data from assets/data/indonesia_regions.json
  Future<void> _loadRegionsFromAsset() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/data/indonesia_regions.json',
      );
      final Map<String, dynamic> map = json.decode(raw) as Map<String, dynamic>;
      // Flatten all cities from all provinces into a single sorted list
      final Set<String> allCities = {};
      for (final e in map.entries) {
        final list = (e.value as List).map((it) => it.toString()).toList();
        allCities.addAll(list);
      }
      final sortedCities = allCities.toList()..sort();
      if (!mounted) return;
      setState(() {
        _availableCities
          ..clear()
          ..addAll(sortedCities);
      });
    } catch (e) {
      // ignore asset errors quietly; the booth-derived lists still work
      // ignore: avoid_print
      print('[HomeScreen] failed to load regions asset: $e');
    }
  }

  // Helper method untuk normalisasi nama kota saat filtering
  // Menghapus prefix "Kota" atau "Kabupaten" untuk perbandingan yang konsisten
  String _normalizeCity(String cityName) {
    return cityName
        .toLowerCase()
        .trim()
        .replaceFirst(RegExp(r'^(kota|kabupaten)\s+', caseSensitive: false), '')
        .trim();
  }

  @override
  void initState() {
    super.initState();
    _initData();
    _loadRegionsFromAsset();
    // Update status setiap menit untuk real-time badge buka/tutup
    _statusUpdateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {
          // Trigger rebuild untuk update badge status
        });
      }
    });
  }

  Future<void> _initData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Tampilkan terlebih dahulu data dasar dari FirebaseAuth agar UI tidak kosong
      setState(() {
        userName =
            user.displayName ?? (user.email?.split('@').first ?? 'Pengguna');
        _photoUrl = user.photoURL;
      });

      _userSub = FirebaseFirestore.instance
          .collection('customers')
          .doc(user.uid)
          .snapshots()
          .listen((doc) {
            if (!mounted) {
              return;
            }
            final data = doc.data();
            if (data != null) {
              setState(() {
                userName =
                    (data['name'] as String?) ?? user.displayName ?? 'Pengguna';
                _photoUrl =
                    (data['photoUrl'] as String?) ?? user.photoURL ?? '';
              });
            } else if (!_triedUsersFallback) {
              // Jika dokumen customers belum ada, coba ambil dari koleksi lama "users"
              _triedUsersFallback = true;
              _loadUserFallback(user);
            }
          });
    }

    try {
      final topLevel = await FirebaseFirestore.instance
          .collection('booths')
          .limit(1)
          .get();
      setState(() {
        if (topLevel.docs.isNotEmpty) {
          boothsQuery = FirebaseFirestore.instance.collection('booths');
          _useCollectionGroup = false;
        } else {
          boothsQuery = FirebaseFirestore.instance.collectionGroup('booths');
          _useCollectionGroup = true;
        }
      });
    } catch (_) {
      setState(() {
        boothsQuery = FirebaseFirestore.instance.collectionGroup('booths');
        _useCollectionGroup = true;
      });
    }
  }

  Future<void> _loadUserFallback(User user) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      final data = snap.data();
      setState(() {
        userName = (data?['name'] as String?) ?? user.displayName ?? 'Pengguna';
        _photoUrl = (data?['photoUrl'] as String?) ?? user.photoURL ?? '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        userName = user.displayName ?? 'Pengguna';
        _photoUrl = user.photoURL ?? '';
      });
    }
  }

  // Rebuild boothsQuery - no server-side filtering, rely on client-side filtering
  void _updateBoothsQuery() {
    Query<Map<String, dynamic>> base = _useCollectionGroup
        ? FirebaseFirestore.instance.collectionGroup('booths')
        : FirebaseFirestore.instance.collection('booths');

    setState(() {
      boothsQuery = base;
    });
  }

  Future<String> _resolveImageUrl(String path) async {
    final p = path.trim();
    if (p.isEmpty) return '';
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    try {
      if (p.startsWith('gs://')) {
        return await FirebaseStorage.instance.refFromURL(p).getDownloadURL();
      }
      return await FirebaseStorage.instance.ref(p).getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  // Wrapper that caches resolved URLs to avoid re-resolving the same storage path
  Future<String> _getResolvedImageUrl(String path) async {
    final key = path.trim();
    if (key.isEmpty) return '';
    final cached = _imageUrlCache[key];
    if (cached != null) return cached;
    final resolved = await _resolveImageUrl(key);
    // store even empty results to avoid repeated failed attempts
    _imageUrlCache[key] = resolved;
    // debug log to help trace resolution issues
    // ignore: avoid_print
    print('[HomeScreen] resolve "$key" -> "$resolved"');
    return resolved;
  }

  String _pickImageField(Map<String, dynamic> data) {
    const candidates = <String>[
      'thumbnail',
      'cover',
      'imageUrl',
      'imageURL',
      'image',
      'url',
      'photoUrl',
      'path',
      'storagePath',
      'image_path',
    ];
    for (final key in candidates) {
      final val = data[key];
      if (val is String && val.trim().isNotEmpty) return val.trim();
    }
    const listCandidates = <String>['images', 'photos', 'gallery'];
    for (final key in listCandidates) {
      final val = data[key];
      if (val is List && val.isNotEmpty) {
        final first = val.first;
        if (first is String && first.trim().isNotEmpty) return first.trim();
      }
    }
    return '';
  }

  int _getMillisFromMap(Map<String, dynamic> m) {
    try {
      final dynamic ts =
          m['createdAt'] ??
          m['created_at'] ??
          m['createdAtMillis'] ??
          m['created_at_millis'];
      if (ts == null) return 0;
      if (ts is int) return ts;
      if (ts is String) {
        try {
          return DateTime.parse(ts).millisecondsSinceEpoch;
        } catch (_) {
          final digits = RegExp(
            r'\d+',
          ).allMatches(ts).map((e) => e.group(0)).join();
          if (digits.isNotEmpty) return int.parse(digits);
          return 0;
        }
      }
      if (ts is Timestamp) return ts.toDate().millisecondsSinceEpoch;
    } catch (_) {
      // ignore
    }
    return 0;
  }

  String _getNameFromMap(Map<String, dynamic> m) {
    return (m['name'] ?? m['title'] ?? m['studio'] ?? '')
        .toString()
        .toLowerCase();
  }

  int _getPriceFromMap(Map<String, dynamic> m) {
    try {
      final raw = (m['price'] ?? m['harga'] ?? m['rate'] ?? '').toString();
      final digits = RegExp(
        r'\d+',
      ).allMatches(raw).map((e) => e.group(0)).join();
      if (digits.isEmpty) return 1 << 60;
      return int.parse(digits);
    } catch (_) {
      return 1 << 60;
    }
  }

  String _formatPrice(dynamic priceValue) {
    try {
      final raw = (priceValue ?? '').toString();
      final digits = RegExp(
        r'\d+',
      ).allMatches(raw).map((e) => e.group(0)).join();
      if (digits.isEmpty) return 'Hubungi Admin';
      final amount = int.parse(digits);
      final formatter = NumberFormat.currency(
        locale: 'id_ID',
        symbol: 'Rp ',
        decimalDigits: 0,
      );
      return formatter.format(amount);
    } catch (_) {
      return 'Hubungi Admin';
    }
  }

  // Prefetch admin locations and status for a set of admin userIds and cache them
  Future<void> _prefetchAdminData(Set<String> adminIds) async {
    final missing = adminIds
        .where((id) => !_adminLocationCache.containsKey(id))
        .toList();
    if (missing.isEmpty) return;
    try {
      final futures = missing.map(
        (id) => FirebaseFirestore.instance
            .collection('photobooth_admins')
            .doc(id)
            .get(),
      );
      final snaps = await Future.wait(futures);
      for (final snap in snaps) {
        if (snap.exists) {
          final data = snap.data() ?? {};
          final loc = (data['location'] ?? '').toString();
          _adminLocationCache[snap.id] = loc;

          // Get studio name (boothName)
          final studioName = (data['boothName'] ?? '').toString();
          _adminStudioNameCache[snap.id] = studioName;
          print('DEBUG: Loaded studio name for ${snap.id}: $studioName');

          // Get operating hours
          final operatingHours = data['operatingHours'];
          if (operatingHours != null && operatingHours is Map) {
            final Map<String, Map<String, String>> hours = {};
            operatingHours.forEach((key, value) {
              if (value is Map) {
                hours[key.toString()] = {
                  'open': (value['open'] ?? '09:00').toString(),
                  'close': (value['close'] ?? '17:00').toString(),
                  'isOpen': (value['isOpen'] ?? 'true').toString(),
                };
              }
            });
            _adminOperatingHoursCache[snap.id] = hours;
          }

          // Get studio status (open/close) - will be overridden by real-time check
          final status = data['status'] ?? data['isOpen'] ?? data['open'];
          bool isOpen = true; // default open
          if (status is bool) {
            isOpen = status;
          } else if (status is String) {
            isOpen = status.toLowerCase() == 'open';
          }
          _adminStatusCache[snap.id] = isOpen;
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      // ignore fetch errors
    }
  }

  // Check if studio is open based on current day and time
  bool _isStudioOpenNow(String adminId) {
    // If no cache data, return false (closed) for safety
    if (!_adminStatusCache.containsKey(adminId)) return false;
    if (!_adminStatusCache[adminId]!) return false; // Studio manually closed

    // Check operating hours
    if (!_adminOperatingHoursCache.containsKey(adminId)) return false;

    final now = DateTime.now();
    final dayNames = [
      'Minggu',
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
    ];
    final currentDay = dayNames[now.weekday % 7];

    final hours = _adminOperatingHoursCache[adminId];
    if (hours == null || !hours.containsKey(currentDay)) return false;

    final daySchedule = hours[currentDay]!;
    final isDayOpen = daySchedule['isOpen'] == 'true';
    if (!isDayOpen) return false;

    // Parse open and close times
    try {
      final openParts = daySchedule['open']!.split(':');
      final closeParts = daySchedule['close']!.split(':');

      final openTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(openParts[0]),
        int.parse(openParts[1]),
      );
      final closeTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(closeParts[0]),
        int.parse(closeParts[1]),
      );

      // Check if 24 hours (00:00 - 00:00)
      if (daySchedule['open'] == '00:00' && daySchedule['close'] == '00:00') {
        return true;
      }

      // Handle case where close time is on the next day (e.g., 22:00 - 02:00)
      var adjustedCloseTime = closeTime;
      if (adjustedCloseTime.isBefore(openTime)) {
        adjustedCloseTime = adjustedCloseTime.add(const Duration(days: 1));
      }

      // Check if current time is within operating hours
      // now >= openTime AND now < closeTime
      return (now.isAfter(openTime) || now.isAtSameMomentAs(openTime)) &&
          now.isBefore(adjustedCloseTime);
    } catch (e) {
      // If parsing fails, return false (closed) for safety
      // ignore: avoid_print
      print('[HomeScreen] Error parsing operating hours: $e');
      return false;
    }
  }

  void _applySortToList(List<Map<String, dynamic>> list) {
    switch (_selectedSort) {
      case 'Terbaru':
        list.sort(
          (a, b) => _getMillisFromMap(b).compareTo(_getMillisFromMap(a)),
        );
        break;
      case 'Nama A-Z':
        list.sort((a, b) => _getNameFromMap(a).compareTo(_getNameFromMap(b)));
        break;
      case 'Nama Z-A':
        list.sort((a, b) => _getNameFromMap(b).compareTo(_getNameFromMap(a)));
        break;
      case 'Harga Terendah':
        list.sort((a, b) => _getPriceFromMap(a).compareTo(_getPriceFromMap(b)));
        break;
      case 'Harga Tertinggi':
        list.sort((a, b) => _getPriceFromMap(b).compareTo(_getPriceFromMap(a)));
        break;
      default:
        break;
    }
  }

  // Removed filter chips builder; chips no longer displayed under search bar.

  @override
  void dispose() {
    _userSub?.cancel();
    _statusUpdateTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EBF2),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              userName != null ? 'Hai, $userName!' : 'Hai!',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Temukan photobooth terdekat',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: CircleAvatar(
              backgroundColor: Colors.white24,
              backgroundImage: (_photoUrl != null && _photoUrl!.isNotEmpty)
                  ? NetworkImage(_photoUrl!)
                  : null,
              child: (_photoUrl == null || _photoUrl!.isEmpty)
                  ? Text(
                      (userName != null && userName!.isNotEmpty)
                          ? userName!.substring(0, 1).toUpperCase()
                          : 'U',
                      style: const TextStyle(color: Colors.white),
                    )
                  : null,
            ),
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4E86D6), Color(0xFF6EA8FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Cari photobooth atau nama studio',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF4E86D6),
                              size: 20,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8F9FD),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 12,
                            ),
                            hintStyle: const TextStyle(
                              color: Colors.black38,
                              fontSize: 13,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF4E86D6),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 155,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFE5E8F0),
                            width: 1,
                          ),
                        ),
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          alignment: Alignment.centerLeft,
                          initialValue: _selectedSort,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: InputBorder.none,
                          ),
                          icon: const Icon(
                            Icons.arrow_drop_down_rounded,
                            color: Color(0xFF6B7AA7),
                            size: 20,
                          ),
                          selectedItemBuilder: (context) => _sortOptions
                              .map(
                                (s) => Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.sort_rounded,
                                      size: 16,
                                      color: Color(0xFF4E86D6),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        s,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF2F3B52),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                          items: _sortOptions
                              .map(
                                (s) => DropdownMenuItem<String>(
                                  value: s,
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.sort_rounded,
                                        size: 16,
                                        color: Color(0xFF4E86D6),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          s,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF2F3B52),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(
                            () => _selectedSort = v ?? 'Rekomendasi',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFE5E8F0),
                        width: 1,
                      ),
                    ),
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue:
                          (_selectedCity == null || _selectedCity!.isEmpty)
                          ? null
                          : _selectedCity,
                      hint: const Text(
                        'Pilih Kota/Kabupaten',
                        style: TextStyle(fontSize: 13, color: Colors.black45),
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(
                          Icons.location_city_outlined,
                          size: 18,
                          color: Color(0xFF4E86D6),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        border: InputBorder.none,
                      ),
                      icon: const Icon(
                        Icons.arrow_drop_down_rounded,
                        color: Color(0xFF6B7AA7),
                      ),
                      items: _availableCities
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c,
                              child: Text(
                                c,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selectedCity = v;
                        _updateBoothsQuery();
                      }),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: boothsQuery == null
                  ? const Center(child: CircularProgressIndicator())
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: boothsQuery!.snapshots(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (!snap.hasData || snap.data!.docs.isEmpty) {
                          return const Center(
                            child: Text('Tidak ada photobooth.'),
                          );
                        }

                        final docs = snap.data!.docs;
                        final booths = docs.map((d) {
                          final m = Map<String, dynamic>.from(d.data());
                          m['__id'] = d.id;
                          m['__ref'] = d
                              .reference; // keep the DocumentReference for navigation
                          return m;
                        }).toList();

                        // Prefetch admin locations and status for filtering and display
                        final adminIds = booths
                            .map((b) => (b['createdBy'] ?? '').toString())
                            .where((id) => id.isNotEmpty)
                            .toSet();
                        unawaited(_prefetchAdminData(adminIds));

                        // Keep province/city options from assets (indonesia_regions.json) only

                        final query = _searchController.text
                            .trim()
                            .toLowerCase();
                        final hasFilter =
                            query.isNotEmpty ||
                            (_selectedCity != null &&
                                _selectedCity!.isNotEmpty);

                        var displayList = booths.cast<Map<String, dynamic>>();
                        if (!hasFilter && _selectedSort == 'Rekomendasi') {
                          final rnd = Random();
                          displayList.shuffle(rnd);
                          if (displayList.length > 8) {
                            displayList = displayList.sublist(0, 8);
                          }
                        } else {
                          if (hasFilter) {
                            displayList = displayList.where((b) {
                              final name =
                                  (b['name'] ?? b['title'] ?? b['studio'] ?? '')
                                      .toString()
                                      .toLowerCase();

                              // Ambil lokasi dari photobooth_admins (via cache) sebagai sumber utama
                              final createdBy = (b['createdBy'] ?? '')
                                  .toString();
                              String locationStr = '';
                              if (createdBy.isNotEmpty &&
                                  _adminLocationCache.containsKey(createdBy)) {
                                locationStr =
                                    _adminLocationCache[createdBy] ?? '';
                              }
                              // Fallback: jika admin location tidak ada, gunakan booth location
                              if (locationStr.trim().isEmpty) {
                                locationStr = (b['location'] ?? '').toString();
                              }

                              // Parse city dari locationStr
                              // Jika format "Kota, Provinsi" ambil bagian pertama saja
                              // Jika format "Padang" langsung gunakan itu
                              String rawCity = locationStr.trim();
                              if (locationStr.contains(',')) {
                                final parts = locationStr
                                    .split(',')
                                    .map((s) => s.trim())
                                    .toList();
                                rawCity = parts[0];
                              }

                              // PERBAIKAN: Jangan hapus prefix untuk konsistensi dengan dropdown filter
                              // Gunakan rawCity langsung untuk matching
                              final city = rawCity.toLowerCase().trim();

                              final matchesQuery = query.isEmpty
                                  ? true
                                  : (name.contains(query) ||
                                        city.contains(query) ||
                                        locationStr.toLowerCase().contains(
                                          query,
                                        ));

                              // Pencocokan filter dropdown: case-insensitive contains matching untuk kota
                              // Normalisasi untuk matching: hapus prefix dari KEDUA sisi untuk perbandingan
                              final matchesCity =
                                  _selectedCity == null ||
                                      _selectedCity!.isEmpty
                                  ? true
                                  : _normalizeCity(city) ==
                                        _normalizeCity(
                                          _selectedCity!.toLowerCase(),
                                        );

                              return matchesQuery && matchesCity;
                            }).toList();
                          }

                          // Apply client-side sorting if a sort other than 'Rekomendasi' is selected
                          if (_selectedSort != 'Rekomendasi') {
                            try {
                              _applySortToList(displayList);
                            } catch (e) {
                              // ignore sorting errors
                              // ignore: avoid_print
                              print('[HomeScreen] sorting failed: $e');
                            }
                          }

                          // If not filtering but a sort is selected, show a limited top set for discovery
                          if (!hasFilter &&
                              _selectedSort != 'Rekomendasi' &&
                              displayList.length > 8) {
                            displayList = displayList.sublist(0, 8);
                          }
                        }

                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: 0.72,
                              ),
                          itemCount: displayList.length,
                          itemBuilder: (context, index) {
                            final b = displayList[index];
                            final createdBy = (b['createdBy'] ?? '').toString();
                            final imgField = _pickImageField(b);
                            final price = b['price'] ?? b['harga'] ?? b['rate'];
                            final duration = (b['duration'] ?? '1').toString();
                            // Check if studio is open based on real-time operating hours
                            final isOpen = createdBy.isNotEmpty
                                ? _isStudioOpenNow(createdBy)
                                : false; // default closed if no admin info

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  onTap: () {
                                    final ref = b['__ref'];
                                    if (ref is DocumentReference) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              BoothDetailScreen(boothRef: ref),
                                        ),
                                      );
                                    } else if (b['__id'] != null) {
                                      // Fallback: try to construct a top-level reference using the id
                                      final fallbackRef = FirebaseFirestore
                                          .instance
                                          .collection('booths')
                                          .doc(b['__id'].toString());
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => BoothDetailScreen(
                                            boothRef: fallbackRef,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: Stack(
                                          children: [
                                            Positioned.fill(
                                              child: GestureDetector(
                                                onTap: () async {
                                                  if (imgField.isEmpty) return;
                                                  final messenger =
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      );
                                                  final navigator =
                                                      Navigator.of(context);
                                                  final url =
                                                      await _getResolvedImageUrl(
                                                        imgField,
                                                      );
                                                  if (!mounted) return;
                                                  if (url.isNotEmpty) {
                                                    navigator.push(
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            ImagePreviewScreen(
                                                              imageUrl: url,
                                                            ),
                                                      ),
                                                    );
                                                  } else {
                                                    messenger.showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Gagal memuat foto',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                },
                                                child: ClipRRect(
                                                  borderRadius:
                                                      const BorderRadius.vertical(
                                                        top: Radius.circular(
                                                          16,
                                                        ),
                                                      ),
                                                  child: imgField.isNotEmpty
                                                      ? FutureBuilder<String>(
                                                          future:
                                                              _getResolvedImageUrl(
                                                                imgField,
                                                              ),
                                                          builder: (c, s) {
                                                            final resolved =
                                                                (s.data ?? '')
                                                                    .trim();
                                                            if (s.connectionState ==
                                                                ConnectionState
                                                                    .waiting) {
                                                              return Container(
                                                                color: Colors
                                                                    .grey[200],
                                                                child: const Center(
                                                                  child: SizedBox(
                                                                    width: 28,
                                                                    height: 28,
                                                                    child: CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                    ),
                                                                  ),
                                                                ),
                                                              );
                                                            }
                                                            if (resolved
                                                                .isEmpty) {
                                                              return Container(
                                                                color: Colors
                                                                    .grey[100],
                                                                child: const Center(
                                                                  child: Icon(
                                                                    Icons
                                                                        .image_not_supported,
                                                                    size: 48,
                                                                    color: Colors
                                                                        .black38,
                                                                  ),
                                                                ),
                                                              );
                                                            }
                                                            return Image.network(
                                                              resolved,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (c, e, st) => Container(
                                                                color: Colors
                                                                    .grey[100],
                                                                child: const Center(
                                                                  child: Icon(
                                                                    Icons
                                                                        .broken_image,
                                                                    size: 48,
                                                                    color: Colors
                                                                        .black38,
                                                                  ),
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        )
                                                      : Container(
                                                          color:
                                                              Colors.grey[100],
                                                          child: const Center(
                                                            child: Icon(
                                                              Icons.image,
                                                              size: 44,
                                                              color: Colors
                                                                  .black26,
                                                            ),
                                                          ),
                                                        ),
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              left: 10,
                                              top: 10,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  gradient: isOpen
                                                      ? const LinearGradient(
                                                          colors: [
                                                            Color(0xFF4CAF50),
                                                            Color(0xFF66BB6A),
                                                          ],
                                                        )
                                                      : const LinearGradient(
                                                          colors: [
                                                            Color(0xFFF44336),
                                                            Color(0xFFE57373),
                                                          ],
                                                        ),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: isOpen
                                                          ? Colors.green
                                                                .withOpacity(
                                                                  0.3,
                                                                )
                                                          : Colors.red
                                                                .withOpacity(
                                                                  0.3,
                                                                ),
                                                      blurRadius: 6,
                                                      offset: const Offset(
                                                        0,
                                                        2,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      isOpen
                                                          ? Icons.check_circle
                                                          : Icons.cancel,
                                                      color: Colors.white,
                                                      size: 12,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      isOpen ? 'Buka' : 'Tutup',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.vertical(
                                            bottom: Radius.circular(16),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              b['name'] ??
                                                  b['title'] ??
                                                  'Photobooth',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Color(0xFF2C3E50),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            // Nama Studio
                                            if (createdBy.isNotEmpty)
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.store,
                                                    size: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Builder(
                                                      builder: (context) {
                                                        final studioName =
                                                            _adminStudioNameCache
                                                                .containsKey(
                                                                  createdBy,
                                                                )
                                                            ? (_adminStudioNameCache[createdBy]!
                                                                      .isNotEmpty
                                                                  ? _adminStudioNameCache[createdBy]!
                                                                  : 'Studio')
                                                            : 'Studio';
                                                        print(
                                                          'DEBUG RENDER: Studio name for $createdBy: $studioName (cache has: ${_adminStudioNameCache.containsKey(createdBy)})',
                                                        );
                                                        return Text(
                                                          studioName,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: Colors
                                                                .grey
                                                                .shade600,
                                                            fontStyle: FontStyle
                                                                .italic,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.location_on_rounded,
                                                  size: 14,
                                                  color: Color(0xFF6B7AA7),
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    createdBy.isNotEmpty &&
                                                            _adminLocationCache
                                                                .containsKey(
                                                                  createdBy,
                                                                )
                                                        ? (_adminLocationCache[createdBy]!
                                                                  .isNotEmpty
                                                              ? _adminLocationCache[createdBy]!
                                                              : 'Lokasi tidak tersedia')
                                                        : 'Lokasi tidak tersedia',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.black54,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            if (price != null)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  gradient:
                                                      const LinearGradient(
                                                        colors: [
                                                          Color(0xFFE3F2FD),
                                                          Color(0xFFBBDEFB),
                                                        ],
                                                      ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        _formatPrice(price),
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Color(
                                                            0xFF1565C0,
                                                          ),
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFF1565C0,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        duration,
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
