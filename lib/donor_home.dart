// lib/donor_home.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'map_screen.dart';
import 'login_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'widgets/notification_bell.dart';

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
  final _pickupCtrl = TextEditingController();

  File? _imageFile;
  bool _submitting = false;
  double _uploadProgress = 0.0;

  LatLng? _selectedLatLng;
  bool _loadingLocation = false;
  DateTime? _pickupAt;

  @override
  void initState() {
    super.initState();
    _pickupAt = DateTime.now().add(const Duration(hours: 1));
    _pickupCtrl.text = _formatDateTime(_pickupAt!);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _qtyCtrl.dispose();
    _expiryHoursCtrl.dispose();
    _notesCtrl.dispose();
    _manualAddressCtrl.dispose();
    _pickupCtrl.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  Future<void> _pickPickupDateTime() async {
    final now = DateTime.now();
    final base = _pickupAt ?? now.add(const Duration(hours: 1));

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (pickedTime == null) return;

    final dt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      _pickupAt = dt;
      _pickupCtrl.text = _formatDateTime(dt);
    });
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
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best));
      _selectedLatLng = LatLng(pos.latitude, pos.longitude);

      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final pm = placemarks.first;
        final address = [
          pm.street,
          pm.subLocality ?? pm.locality,
          pm.administrativeArea,
        ].where((e) => e != null && e.trim().isNotEmpty).join(', ');
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
        if (addr != null) _manualAddressCtrl.text = addr;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final pickupAt = _pickupAt;
    if (pickupAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a pickup time')),
      );
      return;
    }

    setState(() {
      _submitting = true;
      _uploadProgress = 0.0;
    });

    try {
      final photoUrl = await _uploadImageIfAny();

      final expiryHours = int.tryParse(_expiryHoursCtrl.text) ?? 3;
      final expiresAt = DateTime.now().add(Duration(hours: expiryHours));

      final uid = FirebaseAuth.instance.currentUser?.uid;

      final data = <String, Object?>{
        'title': _titleCtrl.text.trim(),
        'quantity': int.parse(_qtyCtrl.text.trim()),
        'pickupAt': pickupAt.millisecondsSinceEpoch,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'status': 'Pending',
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'photoUrl': photoUrl,
        'createdAt': ServerValue.timestamp,
        'donorUid': uid,
        if (_selectedLatLng != null)
          'geo': {'lat': _selectedLatLng!.latitude, 'lng': _selectedLatLng!.longitude},
        if (_manualAddressCtrl.text.trim().isNotEmpty)
          'manualAddress': _manualAddressCtrl.text.trim(),
      };

      // Store title/qty before submit for use in NGO notifications.
      final title = _titleCtrl.text.trim();
      final qty = _qtyCtrl.text.trim();

      // Push donation and capture its key for notifications.
      final donationRef = FirebaseDatabase.instance.ref('donations').push();
      await donationRef.set(data);
      final donationId = donationRef.key;

      // Notify all registered NGOs about the new donation.
      final ngoSnap = await FirebaseDatabase.instance.ref('ngo_list').get();
      if (ngoSnap.exists && ngoSnap.value is Map) {
        await Future.wait([
          for (final ngoUid in (ngoSnap.value as Map).keys)
            NotificationService.notify(
              uid: ngoUid.toString(),
              type: 'new_donation',
              title: '🍛 New Donation Available!',
              body: '$title • $qty servings',
              donationId: donationId,
            ),
        ]);
      }

      if (!mounted) return;

      // Stop loading state first so UI shows "done"
      setState(() {
        _submitting = false;
        _uploadProgress = 0.0;
        _imageFile = null;
        _selectedLatLng = null;
      });

      // Reset form
      _formKey.currentState!.reset();
      _titleCtrl.clear();
      _qtyCtrl.clear();
      _expiryHoursCtrl.text = '3';
      _notesCtrl.clear();
      _manualAddressCtrl.clear();
      _pickupAt = DateTime.now().add(const Duration(hours: 1));
      _pickupCtrl.text = _formatDateTime(_pickupAt!);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Submitted successfully!'),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _uploadProgress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _signOut() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      await FirebaseDatabase.instance.ref('locations/$uid').remove().catchError((_) {});
    }

    await AuthService().signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Stream<List<MapEntry<String, Map<String, dynamic>>>> _myDonationsStream(String uid) {
    return FirebaseDatabase.instance.ref('donations').onValue.map((event) {
      final map = event.snapshot.value;
      if (map == null || map is! Map) return <MapEntry<String, Map<String, dynamic>>>[];
      final List<MapEntry<String, Map<String, dynamic>>> list = [];
      for (final e in map.entries) {
        if (e.value is! Map) continue;
        final m = Map<String, dynamic>.from(Map<dynamic, dynamic>.from(e.value as Map));
        if (m['donorUid'] != uid) continue;
        list.add(MapEntry<String, Map<String, dynamic>>(e.key.toString(), m));
      }
      list.sort((a, b) {
        final ca = a.value['createdAt'];
        final cb = b.value['createdAt'];
        final ta = ca is int ? ca : (ca is num ? ca.toInt() : 0);
        final tb = cb is int ? cb : (cb is num ? cb.toInt() : 0);
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  Future<void> _cancelDonation(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel donation?'),
        content: const Text('This will mark the donation as cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, cancel')),
        ],
      ),
    );
    if (ok != true) return;

    await FirebaseDatabase.instance.ref('donations/$id').update({
      'status': 'Cancelled',
      'cancelledAt': ServerValue.timestamp,
    });
  }

  Widget _buildDonationForm() {
    return SingleChildScrollView(
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

            if (_submitting && _uploadProgress > 0 && _uploadProgress < 1) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: _uploadProgress),
            ],

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
              controller: _pickupCtrl,
              readOnly: true,
              onTap: _submitting ? null : _pickPickupDateTime,
              decoration: InputDecoration(
                labelText: '🕒 Pickup time',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Pick pickup time',
                  icon: const Icon(Icons.calendar_month),
                  onPressed: _submitting ? null : _pickPickupDateTime,
                ),
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
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_submitting ? 'Submitting...' : 'List Donation'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyDonationsTab(User? user) {
    final uid = user?.uid;
    if (uid == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Login to track your donations.'),
        ),
      );
    }

    return StreamBuilder<List<MapEntry<String, Map<String, dynamic>>>>(
      stream: _myDonationsStream(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }

        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const Center(child: Text('No donations yet.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final entry = list[i];
            final id = entry.key;
            final data = entry.value;
            final title = (data['title'] ?? 'Food').toString();
            final qty = data['quantity'] ?? 0;
            final status = (data['status'] ?? 'Pending').toString();
            DateTime? pickupAt;
            DateTime? expiresAt;
            final pa = data['pickupAt'];
            final ea = data['expiresAt'];
            if (pa != null && pa is int) pickupAt = DateTime.fromMillisecondsSinceEpoch(pa);
            if (ea != null && ea is int) expiresAt = DateTime.fromMillisecondsSinceEpoch(ea);

            return Card(
              child: ListTile(
                title: Text('$title • $qty servings'),
                subtitle: Text(
                  [
                    'Status: $status',
                    if (pickupAt != null) 'Pickup: ${_formatDateTime(pickupAt)}',
                    if (expiresAt != null) 'Expires: ${_formatDateTime(expiresAt)}',
                  ].join('\n'),
                ),
                isThreeLine: true,
                trailing: status == 'Pending'
                    ? TextButton(
                        onPressed: () => _cancelDonation(id),
                        child: const Text('Cancel'),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to Login',
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            ),
          ),
          title: const Text('AnnDaan',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color.fromARGB(255, 101, 114, 225),
          foregroundColor: Colors.black87,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.add_circle_outline), text: 'New donation'),
              Tab(icon: Icon(Icons.track_changes), text: 'My donations'),
            ],
          ),
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
            if (user != null)
              NotificationBell(uid: user.uid, iconColor: Colors.black87),
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: _submitting ? null : _signOut,
            ),
          ],
        ),

        // Body UI (same as your working version)
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.fromARGB(255, 180, 157, 199),
                Color.fromARGB(255, 185, 132, 210)
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),

          child: SafeArea(
            child: TabBarView(
              children: [
                _buildDonationForm(),
                _buildMyDonationsTab(user),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



