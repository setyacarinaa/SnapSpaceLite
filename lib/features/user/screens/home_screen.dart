import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:snapspace/features/user/screens/booth_detail_screen.dart';
import 'package:snapspace/features/user/screens/image_preview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? userName;
  Query<Map<String, dynamic>>? boothsQuery;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  bool _useCollectionGroup = false;

  final TextEditingController _searchController = TextEditingController();
  String? _selectedProvince;
  String? _selectedCity;
  final List<String> _availableProvinces = [];
  final Map<String, List<String>> _availableCities = {};
  final Map<String, String> _imageUrlCache = {}; // cache resolved storage URLs
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
      final provs = map.keys.map((k) => k.toString()).toList()..sort();
      final Map<String, List<String>> cities = {};
      for (final e in map.entries) {
        final list = (e.value as List).map((it) => it.toString()).toList()
          ..sort();
        cities[e.key.toString()] = list;
      }
      if (!mounted) return;
      setState(() {
        _availableProvinces
          ..clear()
          ..addAll(provs);
        _availableCities
          ..clear()
          ..addAll(cities);
      });
    } catch (e) {
      // ignore asset errors quietly; the booth-derived lists still work
      // ignore: avoid_print
      print('[HomeScreen] failed to load regions asset: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _initData();
    _loadRegionsFromAsset();
  }

  Future<void> _initData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((doc) {
            if (!mounted) {
              return;
            }
            setState(() {
              userName =
                  (doc.data()?['name'] as String?) ??
                  user.displayName ??
                  'Pengguna';
            });
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

  // Rebuild boothsQuery applying simple equality filters for province and city.
  // Note: Firestore doesn't support OR across fields; this will only query the
  // fields named 'province' and 'city'. If your documents use different field
  // names (e.g. 'provinsi'/'kota'), consider normalizing them server-side or
  // using client-side filtering (already present). This method avoids fetching
  // full dataset when possible.
  void _updateBoothsQuery() {
    Query<Map<String, dynamic>> base = _useCollectionGroup
        ? FirebaseFirestore.instance.collectionGroup('booths')
        : FirebaseFirestore.instance.collection('booths');

    if (_selectedProvince != null && _selectedProvince!.isNotEmpty) {
      try {
        base = base.where('province', isEqualTo: _selectedProvince);
      } catch (_) {
        // ignore: avoid_print
        print('[HomeScreen] could not apply province filter to query');
      }
    }
    if (_selectedCity != null && _selectedCity!.isNotEmpty) {
      try {
        base = base.where('city', isEqualTo: _selectedCity);
      } catch (_) {
        // ignore: avoid_print
        print('[HomeScreen] could not apply city filter to query');
      }
    }

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

  Widget _buildFilterChips() {
    final chips = <Widget>[];
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InputChip(
            label: Text('Cari: "$query"'),
            onDeleted: () => setState(() => _searchController.clear()),
          ),
        ),
      );
    }
    if (_selectedProvince != null && _selectedProvince!.isNotEmpty) {
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InputChip(
            label: Text('Provinsi: ${_selectedProvince!}'),
            onDeleted: () => setState(() => _selectedProvince = null),
          ),
        ),
      );
    }
    if (_selectedCity != null && _selectedCity!.isNotEmpty) {
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InputChip(
            label: Text('Kota: ${_selectedCity!}'),
            onDeleted: () => setState(() => _selectedCity = null),
          ),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(children: chips),
    );
  }

  @override
  void dispose() {
    _userSub?.cancel();
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
              userName != null ? 'Hi, $userName!' : 'Hi!',
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
              child: Text(
                (userName != null && userName!.isNotEmpty)
                    ? userName!.substring(0, 1).toUpperCase()
                    : 'U',
                style: const TextStyle(color: Colors.white),
              ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.06),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Cari photobooth atau nama studio',
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Color(0xFF6B7AA7),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF3F6FB),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 12,
                        ),
                        hintStyle: const TextStyle(color: Colors.black45),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildFilterChips()),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _selectedSort,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF3F6FB),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            items: _sortOptions
                                .map(
                                  (s) => DropdownMenuItem<String>(
                                    value: s,
                                    child: Text(
                                      s,
                                      style: const TextStyle(fontSize: 12),
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
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final gap = 8.0;
                        final half = (constraints.maxWidth - gap) / 2;

                        return Row(
                          children: [
                            SizedBox(
                              width: half,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue:
                                    (_selectedProvince == null ||
                                        _selectedProvince!.isEmpty)
                                    ? null
                                    : _selectedProvince,
                                decoration: InputDecoration(
                                  isDense: true,
                                  prefixIcon: const Icon(
                                    Icons.map,
                                    color: Color(0xFF6B7AA7),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF3F6FB),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                items: _availableProvinces
                                    .map(
                                      (p) => DropdownMenuItem<String>(
                                        value: p,
                                        child: Text(p),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setState(() {
                                  _selectedProvince = v;
                                  _selectedCity = null;
                                  _updateBoothsQuery();
                                }),
                              ),
                            ),
                            SizedBox(width: gap),
                            SizedBox(
                              width: half,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue:
                                    (_selectedCity == null ||
                                        _selectedCity!.isEmpty)
                                    ? null
                                    : _selectedCity,
                                decoration: InputDecoration(
                                  isDense: true,
                                  prefixIcon: const Icon(
                                    Icons.location_city,
                                    color: Color(0xFF6B7AA7),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF3F6FB),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                items:
                                    (_selectedProvince == null
                                            ? <String>[]
                                            : (_availableCities[_selectedProvince] ??
                                                  <String>[]))
                                        .map(
                                          (c) => DropdownMenuItem<String>(
                                            value: c,
                                            child: Text(c),
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
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
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

                        // Build province / city lists from fetched booths (for filter dropdowns)
                        final Set<String> provincesSet = <String>{};
                        final Map<String, Set<String>> citiesSets = {};
                        for (final b in booths) {
                          final prov = (b['province'] ?? b['provinsi'] ?? '')
                              .toString()
                              .trim();
                          final city =
                              (b['city'] ?? b['kota'] ?? b['kabupaten'] ?? '')
                                  .toString()
                                  .trim();
                          if (prov.isNotEmpty) provincesSet.add(prov);
                          final key = prov.isNotEmpty ? prov : '';
                          citiesSets.putIfAbsent(key, () => <String>{});
                          if (city.isNotEmpty) citiesSets[key]!.add(city);
                        }

                        final newProvinces = provincesSet.toList()..sort();
                        final Map<String, List<String>> newCities = {};
                        for (final e in citiesSets.entries) {
                          final list = e.value.toList()..sort();
                          newCities[e.key] = list;
                        }

                        final provincesChanged =
                            _availableProvinces.length != newProvinces.length ||
                            !_availableProvinces.every(
                              (p) => newProvinces.contains(p),
                            );
                        var citiesChanged =
                            _availableCities.length != newCities.length;
                        if (!citiesChanged) {
                          for (final k in newCities.keys) {
                            final a = _availableCities[k] ?? <String>[];
                            final b = newCities[k] ?? <String>[];
                            if (a.length != b.length ||
                                !a.every((x) => b.contains(x))) {
                              citiesChanged = true;
                              break;
                            }
                          }
                        }

                        if (provincesChanged || citiesChanged) {
                          // Schedule update after this build frame to avoid calling setState during build
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() {
                              _availableProvinces
                                ..clear()
                                ..addAll(newProvinces);
                              _availableCities
                                ..clear()
                                ..addAll(newCities);
                              if (_selectedProvince != null &&
                                  !_availableProvinces.contains(
                                    _selectedProvince,
                                  )) {
                                _selectedProvince = null;
                                _selectedCity = null;
                              }
                              if (_selectedCity != null) {
                                final citiesForProv =
                                    _availableCities[_selectedProvince] ??
                                    <String>[];
                                if (!citiesForProv.contains(_selectedCity)) {
                                  _selectedCity = null;
                                }
                              }
                            });
                          });
                        }

                        final query = _searchController.text
                            .trim()
                            .toLowerCase();
                        final hasFilter =
                            query.isNotEmpty ||
                            (_selectedProvince != null &&
                                _selectedProvince!.isNotEmpty) ||
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
                              final city =
                                  (b['city'] ??
                                          b['kota'] ??
                                          b['kabupaten'] ??
                                          '')
                                      .toString()
                                      .toLowerCase();
                              final province =
                                  (b['province'] ?? b['provinsi'] ?? '')
                                      .toString()
                                      .toLowerCase();
                              final matchesQuery = query.isEmpty
                                  ? true
                                  : (name.contains(query) ||
                                        city.contains(query) ||
                                        province.contains(query));
                              final matchesProvince = _selectedProvince == null
                                  ? true
                                  : (province ==
                                        _selectedProvince!.toLowerCase());
                              final matchesCity = _selectedCity == null
                                  ? true
                                  : (city == _selectedCity!.toLowerCase());
                              return matchesQuery &&
                                  matchesProvince &&
                                  matchesCity;
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
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.84,
                              ),
                          itemCount: displayList.length,
                          itemBuilder: (context, index) {
                            final b = displayList[index];
                            final locCity =
                                (b['city'] ?? b['kota'] ?? b['kabupaten'] ?? '')
                                    .toString();
                            final locProv =
                                (b['province'] ?? b['provinsi'] ?? '')
                                    .toString();
                            final imgField = _pickImageField(b);
                            final price =
                                (b['price'] ?? b['harga'] ?? b['rate'] ?? '')
                                    .toString();
                            final isOpen =
                                (b['status'] ??
                                            b['open'] ??
                                            b['isOpen'] ??
                                            'open')
                                        .toString()
                                        .toLowerCase() ==
                                    'open' ||
                                (b['open'] == true);

                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              elevation: 1.5,
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
                                borderRadius: BorderRadius.circular(10),
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
                                                final navigator = Navigator.of(
                                                  context,
                                                );
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
                                                      top: Radius.circular(10),
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
                                                            errorBuilder:
                                                                (
                                                                  c,
                                                                  e,
                                                                  st,
                                                                ) => Container(
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
                                                        color: Colors.grey[100],
                                                        child: const Center(
                                                          child: Icon(
                                                            Icons.image,
                                                            size: 44,
                                                            color:
                                                                Colors.black26,
                                                          ),
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ),
                                          if (isOpen)
                                            Positioned(
                                              left: 8,
                                              top: 8,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.blueAccent
                                                      .withAlpha(242),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Text(
                                                  'Buka',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFBFE0FF),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              bottom: Radius.circular(10),
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
                                              fontSize: 13,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  locCity.isNotEmpty
                                                      ? locCity
                                                      : locProv,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.black54,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (price.isNotEmpty)
                                                Text(
                                                  price,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black87,
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
