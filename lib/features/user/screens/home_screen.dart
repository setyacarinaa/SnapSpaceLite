import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? userName;
  Query<Map<String, dynamic>>? boothsQuery;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  final TextEditingController _searchController = TextEditingController();
  String? _selectedProvince;
  String? _selectedCity;
  final List<String> _availableProvinces = [];
  final Map<String, List<String>> _availableCities = {};

  @override
  void initState() {
    super.initState();
    _initData();
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
        boothsQuery = topLevel.docs.isNotEmpty
            ? FirebaseFirestore.instance.collection('booths')
            : FirebaseFirestore.instance.collectionGroup('booths');
      });
    } catch (_) {
      setState(() {
        boothsQuery = FirebaseFirestore.instance.collectionGroup('booths');
      });
    }
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
                    _buildFilterChips(),
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
                                onChanged: (v) =>
                                    setState(() => _selectedCity = v),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildFilterChips(),
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
                          return m;
                        }).toList();

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
                        if (!hasFilter) {
                          final rnd = Random();
                          displayList.shuffle(rnd);
                          if (displayList.length > 8) {
                            displayList = displayList.sublist(0, 8);
                          }
                        } else {
                          displayList = displayList.where((b) {
                            final name =
                                (b['name'] ?? b['title'] ?? b['studio'] ?? '')
                                    .toString()
                                    .toLowerCase();
                            final city =
                                (b['city'] ?? b['kota'] ?? b['kabupaten'] ?? '')
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
                            final imgField =
                                (b['thumbnail'] ??
                                        b['image'] ??
                                        b['cover'] ??
                                        b['photoUrl'] ??
                                        '')
                                    .toString();
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
                                  // TODO: navigate to detail
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
                                            child: ClipRRect(
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                    top: Radius.circular(10),
                                                  ),
                                              child: imgField.isNotEmpty
                                                  ? FutureBuilder<String>(
                                                      future: _resolveImageUrl(
                                                        imgField,
                                                      ),
                                                      builder: (c, s) {
                                                        final resolved =
                                                            (s.data ?? '')
                                                                .trim();
                                                        if (s.connectionState ==
                                                            ConnectionState
                                                                .waiting) {
                                                          return Image.asset(
                                                            'assets/images/default_booth.jpg',
                                                            fit: BoxFit.cover,
                                                          );
                                                        }
                                                        if (resolved.isEmpty) {
                                                          return Image.asset(
                                                            'assets/images/default_booth.jpg',
                                                            fit: BoxFit.cover,
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
                                                              ) => Image.asset(
                                                                'assets/images/default_booth.jpg',
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                        );
                                                      },
                                                    )
                                                  : Image.asset(
                                                      'assets/images/default_booth.jpg',
                                                      fit: BoxFit.cover,
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
