// lib/ngo_home.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'map_screen.dart';
import 'login_screen.dart';

class NgoHomeScreen extends StatefulWidget {
  const NgoHomeScreen({super.key});

  @override
  State<NgoHomeScreen> createState() => _NgoHomeScreenState();
}

class _NgoHomeScreenState extends State<NgoHomeScreen> {
  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    final now = Timestamp.fromDate(DateTime.now());
    return FirebaseFirestore.instance
        .collection('donations')
        .where('status', whereIn: ['Pending', 'Accepted'])
        .where('expiresAt', isGreaterThan: now)
        .orderBy('expiresAt')
        .snapshots();
  }

  Future<void> _accept(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await FirebaseFirestore.instance.collection('donations').doc(id).update({
      'status': 'Accepted',
      'acceptedByUid': uid,
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _markCompleted(String id) async {
    await FirebaseFirestore.instance.collection('donations').doc(id).update({
      'status': 'Completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _signOut(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      await FirebaseFirestore.instance
          .collection('locations')
          .doc(uid)
          .delete()
          .catchError((_) {});
    }

    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🤝 NGO Dashboard'),
        backgroundColor: const Color(0xFF6A11CB),
        actions: [
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

      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),

        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _stream(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snap.hasError) {
              return Center(child: Text('❌ Error: ${snap.error}'));
            }

            final docs = snap.data?.docs ?? [];

            if (docs.isEmpty) {
              return const Center(
                child: Text(
                  '📭 No food requests available right now.',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final data = docs[i].data();
                final id = docs[i].id;

                final title = data['title'] ?? 'Food';
                final qty = data['quantity'] ?? 0;
                final url = data['photoUrl'] as String?;
                final exp = (data['expiresAt'] as Timestamp?)?.toDate();
                final status = data['status'];
                final geo = data['geo'] as GeoPoint?;
                final manual = data['manualAddress'] as String?;

                return Card(
                  color: Colors.white.withOpacity(0.9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: url == null
                        ? const Icon(Icons.fastfood,
                            size: 40, color: Colors.orange)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              url,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),

                    title: Text(
                      '$title • $qty servings',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),

                    subtitle: Text(
                      exp == null
                          ? '⏳ Expires: —'
                          : '⏳ Expires: ${exp.day}/${exp.month} ${exp.hour}:${exp.minute.toString().padLeft(2, '0')}',
                    ),

                    onTap: () {
                      if (geo != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MapScreen(
                              initialLatLng:
                                  LatLng(geo.latitude, geo.longitude),
                            ),
                          ),
                        );
                      } else if (manual != null && manual.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MapScreen(
                              searchAddress: manual,
                            ),
                          ),
                        );
                      }
                    },

                    trailing: status == 'Pending'
                        ? ElevatedButton.icon(
                            onPressed: () => _accept(id),
                            icon: const Icon(Icons.check),
                            label: const Text('Accept'),
                          )
                        : status == 'Accepted'
                            ? ElevatedButton.icon(
                                onPressed: () => _markCompleted(id),
                                icon: const Icon(Icons.done_all),
                                label: const Text('Complete'),
                              )
                            : const Icon(Icons.check_circle,
                                color: Colors.green, size: 30),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
