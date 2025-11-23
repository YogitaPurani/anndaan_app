// lib/donor_home.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'map_screen.dart';
import 'login_screen.dart';
import 'services/auth_service.dart';

class DonorHomeScreen extends StatefulWidget {
  const DonorHomeScreen({super.key});

  @override
  State<DonorHomeScreen> createState() => _DonorHomeScreenState();
}

class _DonorHomeScreenState extends State<DonorHomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _expiryHoursCtrl = TextEditingController(text: '3');
  final _notesCtrl = TextEditingController();
  final _manualAddressCtrl = TextEditingController();

  File? _imageFile;
  bool _submitting = false;
  double _uploadProgress = 0.0;

  LatLng? _selectedLatLng;
  String? _selectedAddress;
  bool _loadingLocation = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _qtyCtrl.dispose();
    _expiryHoursCtrl.dispose();
    _notesCtrl.dispose();
    _manualAddressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    setState(() => _imageFile = File(x.path));
  }

  Future<String?> _uploadImageIfAny() async {
    if (_imageFile == null) return null;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    final path = 'food_images/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance.ref(path);

    final uploadTask = ref.putFile(_imageFile!);
    uploadTask.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) {
        setState(() => _uploadProgress = s.bytesTransferred / s.totalBytes);
      }
    });

    await uploadTask;
    return ref.getDownloadURL();
  }

  Future<void> _useMyLocation() async {
    setState(() => _loadingLocation = true);

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _loadingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enable location services')));
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _loadingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission denied')));
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _loadingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions permanently denied')));
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      _selectedLatLng = LatLng(pos.latitude, pos.longitude);

      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final pm = placemarks.first;
        final address = [
          pm.street,
          pm.subLocality ?? pm.locality,
          pm.administrativeArea,
          pm.postalCode
        ].where((e) => e != null && e.trim().isNotEmpty).join(', ');
        _selectedAddress = address;
        _manualAddressCtrl.text = address;
      }

      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      setState(() => _loadingLocation = false);
    }
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MapScreen(pickMode: true),
      ),
    );

    if (result != null) {
      final lat = result['lat'];
      final lng = result['lng'];
      final addr = result['address'];

      setState(() {
        _selectedLatLng = LatLng(lat, lng);
        _selectedAddress = addr;
        if (addr != null) _manualAddressCtrl.text = addr;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _uploadProgress = 0.0;
    });

    try {
      final photoUrl = await _uploadImageIfAny();

      final expiryHours = int.tryParse(_expiryHoursCtrl.text) ?? 3;
      final expiresAt = DateTime.now().add(Duration(hours: expiryHours));

      final uid = FirebaseAuth.instance.currentUser?.uid;

      final data = {
        'title': _titleCtrl.text.trim(),
        'quantity': int.parse(_qtyCtrl.text.trim()),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'status': 'Pending',
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'photoUrl': photoUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'donorUid': uid,
        if (_selectedLatLng != null)
          'geo': GeoPoint(_selectedLatLng!.latitude, _selectedLatLng!.longitude),
        if (_manualAddressCtrl.text.trim().isNotEmpty)
          'manualAddress': _manualAddressCtrl.text.trim(),
      };

      await FirebaseFirestore.instance.collection('donations').add(data);

      // Reset form
      _formKey.currentState!.reset();
      _titleCtrl.clear();
      _qtyCtrl.clear();
      _expiryHoursCtrl.text = '3';
      _notesCtrl.clear();
      _manualAddressCtrl.clear();
      setState(() {
        _imageFile = null;
        _selectedLatLng = null;
        _selectedAddress = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Donation listed successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      await FirebaseFirestore.instance.collection('locations').doc(uid).delete().catchError((_) {});
    }

    await AuthService().signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🍲 AnnDaan — Donate Food',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color.fromARGB(255, 212, 226, 99),
        foregroundColor: Colors.black87,
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Center(
                child: Text(user.displayName ?? user.email ?? "",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.black)),
              ),
            ),
         IconButton(
  tooltip: 'Go to Login',
  icon: const Icon(Icons.login),
  onPressed: () {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  },
),

        ],
      ),

      // Body UI (same as your working version)
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.fromARGB(255, 122, 210, 104),
              Color.fromARGB(255, 137, 236, 113)
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),

        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Image picker
                  GestureDetector(
                    onTap: _submitting ? null : _pickImage,
                    child: Container(
                      height: 170,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black38),
                      ),
                      child: _imageFile == null
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo_outlined, size: 40),
                                  SizedBox(height: 8),
                                  Text('📸 Add a photo (optional)'),
                                ],
                              ),
                            )
                          : Image.file(_imageFile!, fit: BoxFit.cover),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _loadingLocation ? null : _useMyLocation,
                          icon: const Icon(Icons.my_location),
                          label: const Text('Use my location'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _pickOnMap,
                        icon: const Icon(Icons.map),
                        label: const Text('Pick on map'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  if (_selectedLatLng != null)
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Selected: ${_selectedLatLng!.latitude}, '
                            '${_selectedLatLng!.longitude}',
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _selectedLatLng = null;
                              _manualAddressCtrl.clear();
                            });
                          },
                          icon: const Icon(Icons.close),
                        )
                      ],
                    ),

                  TextFormField(
                    controller: _manualAddressCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '📍 Manual address',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _titleCtrl,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Title required' : null,
                    decoration: const InputDecoration(
                      labelText: '🍛 Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _qtyCtrl,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter valid quantity';
                      return null;
                    },
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '🍽 Quantity',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _expiryHoursCtrl,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 1 || n > 48) return '1–48 hours only';
                      return null;
                    },
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '⏳ Expires in (hours)',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '📝 Notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : const Icon(Icons.check_circle_outline),
                      label:
                          Text(_submitting ? 'Submitting...' : 'List Donation'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
