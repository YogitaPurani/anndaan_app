// lib/ngo_home.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'map_screen.dart';
import 'login_screen.dart';
import 'services/notification_service.dart';
import 'widgets/notification_bell.dart';

class NgoHomeScreen extends StatefulWidget {
  const NgoHomeScreen({super.key});

  @override
  State<NgoHomeScreen> createState() => _NgoHomeScreenState();
}

class _NgoHomeScreenState extends State<NgoHomeScreen> {
  List<MapEntry<String, Map<String, dynamic>>> _availableList = [];
  List<MapEntry<String, Map<String, dynamic>>> _acceptedList = [];
  bool _availableLoading = true;
  bool _acceptedLoading = true;

  StreamSubscription? _availableSub;
  StreamSubscription? _acceptedSub;

  @override
  void initState() {
    super.initState();
    _availableSub = _buildAvailableStream().listen((data) {
      if (mounted) setState(() { _availableList = data; _availableLoading = false; });
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _acceptedSub = _buildAcceptedStream(uid).listen((data) {
        if (mounted) setState(() { _acceptedList = data; _acceptedLoading = false; });
      });
    } else {
      _acceptedLoading = false;
    }
  }

  @override
  void dispose() {
    _availableSub?.cancel();
    _acceptedSub?.cancel();
    super.dispose();
  }

  Stream<List<MapEntry<String, Map<String, dynamic>>>> _buildAvailableStream() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return FirebaseDatabase.instance.ref('donations').onValue.map((event) {
      final map = event.snapshot.value;
      if (map == null || map is! Map) return <MapEntry<String, Map<String, dynamic>>>[];
      final list = <MapEntry<String, Map<String, dynamic>>>[];
      for (final e in map.entries) {
        if (e.value is! Map) continue;
        final m = Map<String, dynamic>.from(Map<dynamic, dynamic>.from(e.value as Map));
        final status = (m['status'] ?? '').toString();
        if (status != 'Pending') continue;
        final exp = m['expiresAt'];
        final expMs = exp is int ? exp : (exp is num ? exp.toInt() : 0);
        if (expMs <= nowMs) continue;
        list.add(MapEntry(e.key.toString(), m));
      }
      list.sort((a, b) {
        final ta = a.value['expiresAt'];
        final tb = b.value['expiresAt'];
        final ia = ta is int ? ta : (ta is num ? ta.toInt() : 0);
        final ib = tb is int ? tb : (tb is num ? tb.toInt() : 0);
        return ia.compareTo(ib);
      });
      return list;
    });
  }

  Stream<List<MapEntry<String, Map<String, dynamic>>>> _buildAcceptedStream(String uid) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return FirebaseDatabase.instance.ref('donations').onValue.map((event) {
      final map = event.snapshot.value;
      if (map == null || map is! Map) return <MapEntry<String, Map<String, dynamic>>>[];
      final list = <MapEntry<String, Map<String, dynamic>>>[];
      for (final e in map.entries) {
        if (e.value is! Map) continue;
        final m = Map<String, dynamic>.from(Map<dynamic, dynamic>.from(e.value as Map));
        if (m['status'] != 'Accepted' || m['acceptedByUid'] != uid) continue;
        final exp = m['expiresAt'];
        final expMs = exp is int ? exp : (exp is num ? exp.toInt() : 0);
        if (expMs <= nowMs) continue;
        list.add(MapEntry(e.key.toString(), m));
      }
      list.sort((a, b) {
        final ta = a.value['expiresAt'];
        final tb = b.value['expiresAt'];
        final ia = ta is int ? ta : (ta is num ? ta.toInt() : 0);
        final ib = tb is int ? tb : (tb is num ? tb.toInt() : 0);
        return ia.compareTo(ib);
      });
      return list;
    });
  }

  Future<void> _accept(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseDatabase.instance.ref('donations/$id');
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.value;
    if (data is! Map) return;
    final m = Map<String, dynamic>.from(Map<dynamic, dynamic>.from(data));
    if ((m['status'] ?? '') != 'Pending') return;

    await ref.update({
      'status': 'Accepted',
      'acceptedByUid': uid,
      'acceptedAt': ServerValue.timestamp,
    });

    // Notify the donor that their donation was accepted.
    final donorUid = m['donorUid'] as String?;
    if (donorUid != null) {
      await NotificationService.notify(
        uid: donorUid,
        type: 'donation_accepted',
        title: '🎉 Donation Accepted!',
        body: 'An NGO has accepted your donation "${m['title'] ?? 'Food'}". They will pick it up soon!',
        donationId: id,
      );
    }
  }

  Future<void> _markCompleted(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseDatabase.instance.ref('donations/$id');
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.value;
    if (data is! Map) return;
    final m = Map<String, dynamic>.from(Map<dynamic, dynamic>.from(data));
    if ((m['status'] ?? '') != 'Accepted' || m['acceptedByUid'] != uid) return;

    await ref.update({
      'status': 'Completed',
      'completedAt': ServerValue.timestamp,
    });

    // Notify the donor that their donation was picked up.
    final donorUid = m['donorUid'] as String?;
    if (donorUid != null) {
      await NotificationService.notify(
        uid: donorUid,
        type: 'donation_completed',
        title: '✅ Donation Picked Up!',
        body: 'Your donation "${m['title'] ?? 'Food'}" was successfully picked up by the NGO. Thank you! 🙏',
        donationId: id,
      );
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      await FirebaseDatabase.instance.ref('locations/$uid').remove().catchError((_) {});
    }

    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _donationList(List<MapEntry<String, Map<String, dynamic>>> list, bool isLoading) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (list.isEmpty) {
      return const Center(
        child: Text(
          '📭 No food requests available right now.',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
      );
    }

    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final entry = list[i];
        final id = entry.key;
        final data = entry.value;

        final title = data['title'] ?? 'Food';
        final qty = data['quantity'] ?? 0;
        final url = data['photoUrl'] as String?;
        DateTime? exp;
        DateTime? pickup;
        final ea = data['expiresAt'];
        final pa = data['pickupAt'];
        if (ea != null && ea is int) exp = DateTime.fromMillisecondsSinceEpoch(ea);
        if (pa != null && pa is int) pickup = DateTime.fromMillisecondsSinceEpoch(pa);
        final status = (data['status'] ?? 'Pending').toString();
        LatLng? geo;
        final g = data['geo'];
        if (g is Map && g['lat'] != null && g['lng'] != null) {
          geo = LatLng((g['lat'] as num).toDouble(), (g['lng'] as num).toDouble());
        }
        final manual = data['manualAddress'] as String?;
        final acceptedBy = (data['acceptedByUid'] as String?)?.trim();

        final canAccept = status == 'Pending';
        final canComplete = status == 'Accepted' && acceptedBy != null && acceptedBy == myUid;

        String subtitle = '';
        if (pickup != null) {
          subtitle +=
              '🕒 Pickup: ${pickup.day}/${pickup.month} ${pickup.hour}:${pickup.minute.toString().padLeft(2, '0')}\n';
        }
        subtitle += exp == null
            ? '⏳ Expires: —'
            : '⏳ Expires: ${exp.day}/${exp.month} ${exp.hour}:${exp.minute.toString().padLeft(2, '0')}';

        return Card(
          color: Colors.white.withValues(alpha: 0.9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: url == null
                ? const Icon(Icons.fastfood, size: 40, color: Colors.orange)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(url, width: 56, height: 56, fit: BoxFit.cover),
                  ),
            title: Text('$title • $qty servings',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(subtitle),
            onTap: () {
              if (geo != null) {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => MapScreen(initialLatLng: geo)));
              } else if (manual != null && manual.isNotEmpty) {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => MapScreen(searchAddress: manual)));
              }
            },
            trailing: canAccept
                ? ElevatedButton.icon(
                    onPressed: () => _accept(id),
                    icon: const Icon(Icons.check),
                    label: const Text('Accept'),
                  )
                : canComplete
                    ? ElevatedButton.icon(
                        onPressed: () => _markCompleted(id),
                        icon: const Icon(Icons.done_all),
                        label: const Text('Complete'),
                      )
                    : const Icon(Icons.check_circle, color: Colors.green, size: 30),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

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
          title: const Text('NGO Dashboard'),
          backgroundColor: const Color.fromARGB(255, 164, 215, 147),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.list_alt), text: 'Available'),
              Tab(icon: Icon(Icons.assignment_turned_in), text: 'Accepted'),
            ],
          ),
          actions: [
            if (uid != null)
              NotificationBell(uid: uid, iconColor: Colors.white),
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => _signOut(context),
            ),
          ],
        ),

        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color.fromARGB(255, 138, 181, 222), Color.fromARGB(255, 136, 168, 222)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: TabBarView(
            children: [
              _donationList(_availableList, _availableLoading),
              uid == null
                  ? const Center(
                      child: Text(
                        'Please login to see accepted pickups.',
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  : _donationList(_acceptedList, _acceptedLoading),
            ],
          ),
        ),
      ),
    );
  }
}
