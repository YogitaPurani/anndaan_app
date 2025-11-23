import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';

class MapScreen extends StatefulWidget {
  final bool pickMode;
  final LatLng? initialLatLng;
  final String? searchAddress;

  const MapScreen({
    super.key,
    this.pickMode = false,
    this.initialLatLng,
    this.searchAddress,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  GoogleMapController? _mapController;
  final Map<String, Marker> _otherMarkers = {};
  Marker? _myMarker;
  Marker? _pickedMarker;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _locationsSub;
  Timer? _throttleTimer;

  static const CameraPosition _initialCam = CameraPosition(
    target: LatLng(20.5937, 78.9629), // India center fallback
    zoom: 5.0,
  );

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _locationsSub?.cancel();
    _mapController?.dispose();
    _throttleTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final ok = await _ensurePermissions();
    if (!ok) return;

    await _listenToOtherLocations();
    await _startPositionStream();

    if (widget.initialLatLng != null) {
      Future.delayed(const Duration(milliseconds: 600), () {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(widget.initialLatLng!, 15),
        );
      });
    }

    if (widget.searchAddress != null && widget.searchAddress!.trim().isNotEmpty) {
      try {
        final list = await locationFromAddress(widget.searchAddress!);
        if (list.isNotEmpty) {
          final l = list.first;
          final latLng = LatLng(l.latitude, l.longitude);
          Future.delayed(const Duration(milliseconds: 700), () {
            _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 14));
          });
        }
      } catch (_) {}
    }
  }

  Future<bool> _ensurePermissions() async {
    final status = await Permission.locationWhenInUse.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (!mounted) return false;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Location permission required'),
          content: const Text('Please allow location permission to share and view nearby donors/NGOs.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () => openAppSettings(), child: const Text('Open settings')),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _startPositionStream() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable location services')),
      );
      return;
    }

    final locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 10,
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (pos) => _onPosition(pos),
      onError: (e) {},
    );

    try {
      final p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      _onPosition(p, animate: true);
    } catch (_) {}
  }

  Future<void> _onPosition(Position pos, {bool animate = false}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final lat = pos.latitude;
    final lng = pos.longitude;

    final m = Marker(
      markerId: MarkerId(uid),
      position: LatLng(lat, lng),
      infoWindow: const InfoWindow(title: 'You'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    );

    setState(() => _myMarker = m);

    if (animate && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15),
      );
    }

    if (_throttleTimer?.isActive ?? false) return;
    _throttleTimer = Timer(const Duration(seconds: 5), () {});

    final userDoc = await _fs.collection('users').doc(uid).get();
    final userRole = userDoc.data()?['role'] ?? 'unknown';

    try {
      await _fs.collection('locations').doc(uid).set({
        'uid': uid,
        'role': userRole,
        'lat': lat,
        'lng': lng,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _listenToOtherLocations() async {
    final uid = _auth.currentUser?.uid;

    _locationsSub = _fs.collection('locations').snapshots().listen((QuerySnapshot snap) {
      final Map<String, Marker> newMarkers = {};

      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final docUid = data['uid'] as String? ?? doc.id;

        if (docUid == uid) continue;

        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        final role = data['role'] as String? ?? 'unknown';

        if (lat == null || lng == null) continue;

        final marker = Marker(
          markerId: MarkerId(docUid),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(title: role.toUpperCase(), snippet: data['manualAddress'] ?? ''),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        );

        newMarkers[docUid] = marker;
      }

      setState(() {
        _otherMarkers
          ..clear()
          ..addAll(newMarkers);
      });
    });
  }

  Set<Marker> _buildMarkers() {
    final set = <Marker>{};

    if (_myMarker != null) set.add(_myMarker!);
    set.addAll(_otherMarkers.values);

    if (_pickedMarker != null) set.add(_pickedMarker!);

    return set;
  }

  Future<void> _onMapLongPress(LatLng pos) async {
    if (!widget.pickMode) return;

    setState(() {
      _pickedMarker = Marker(
        markerId: const MarkerId('picked'),
        position: pos,
        infoWindow: const InfoWindow(title: 'Picked location'),
      );
    });

    String? addr;
    try {
      final p = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (p.isNotEmpty) {
        final pm = p.first;
        addr = '${pm.street ?? ''}, ${pm.locality ?? ''}, ${pm.administrativeArea ?? ''}, ${pm.postalCode ?? ''}'
            .replaceAll(RegExp(r'(^, |, ,)'), '');
      }
    } catch (_) {}

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Picked location', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(addr ?? '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context, {
                      'lat': pos.latitude,
                      'lng': pos.longitude,
                      'address': addr,
                    });
                  },
                  child: const Text('Use this location'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.pickMode ? 'Pick location on map' : 'Live Locations')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCam,
            onMapCreated: (c) => _mapController = c,
            myLocationEnabled: true,
            myLocationButtonEnabled: false, // disable default button
            markers: _buildMarkers(),
            zoomControlsEnabled: false,
            onLongPress: _onMapLongPress,
            padding: const EdgeInsets.only(top: 50),
          ),
          Positioned(
            bottom: 80,
            right: 10,
            child: FloatingActionButton(
              heroTag: 'loc',
              child: const Icon(Icons.my_location),
              onPressed: () async {
                final my = _myMarker;
                if (my != null) {
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(my.position, 16),
                  );
                } else {
                  try {
                    final p = await Geolocator.getCurrentPosition();
                    _onPosition(p, animate: true);
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not get position')),
                      );
                    }
                  }
                }
              },
            ),
          ),
          if (widget.pickMode && _pickedMarker != null)
            Positioned(
              bottom: 20,
              right: 10,
              child: FloatingActionButton(
                heroTag: 'ok',
                backgroundColor: Colors.green,
                child: const Icon(Icons.check),
                onPressed: () {
                  final p = _pickedMarker!.position;
                  Navigator.pop(context, {
                    'lat': p.latitude,
                    'lng': p.longitude,
                    'address': null,
                  });
                },
              ),
            ),
        ],
      ),
    );
  }
}
