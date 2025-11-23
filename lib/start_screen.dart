// lib/start_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'login_screen.dart';
import 'donor_home.dart';
import 'ngo_home.dart';
import 'services/auth_service.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final AuthService _auth = AuthService();
  double _logoOpacity = 0.0;
  StreamSubscription<User?>? _authSub;
  bool _checking = false;
  bool _navigated = false;
  bool _getStartedLoading = false;

  @override
  void initState() {
    super.initState();

    // Start logo fade-in
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _logoOpacity = 1.0);
    });

    // Listen to auth state and auto-route if user signed in
    _authSub = _auth.userChanges.listen((user) {
      if (user != null && !_navigated) {
        _routeSignedInUser(user);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _routeSignedInUser(User user) async {
    if (_navigated) return;
    _navigated = true;

    if (!mounted) return;
    setState(() => _checking = true);

    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final roleStr = snap.data()?['role'] as String?;
      if (!mounted) return;

      if (roleStr == 'ngo') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const NgoHomeScreen()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DonorHomeScreen()));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _onGetStarted() {
    if (_navigated || _getStartedLoading) return;
    setState(() => _getStartedLoading = true);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())).then((_) {
      if (mounted) setState(() => _getStartedLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isSmall = media.size.height < 700;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromARGB(255, 110, 201, 228), Color.fromARGB(255, 37, 180, 252)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: _checking
                ? const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Colors.white, Colors.white],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: const Text(
                            'ANNDAAN',
                            style: TextStyle(
                              fontSize: 52,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 3.0,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                         Text(
                          'From your plate to their smile',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontStyle: FontStyle.italic,
                            color: Color.fromARGB(255, 10, 10, 10),
                          ),
                        ),
                        const SizedBox(height: 22),
                        AnimatedOpacity(
                          opacity: _logoOpacity,
                          duration: const Duration(seconds: 2),
                          child: Image.asset(
                            'assets/anndaan_logo2.png',
                            width: isSmall ? 180 : 240,
                            height: isSmall ? 170 : 235,
                            semanticLabel: 'AnnDaan logo',
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Ann Daan-Sabse bada Daan!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontStyle: FontStyle.italic,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Get Started Button
                        ElevatedButton(
                          onPressed: _getStartedLoading ? null : _onGetStarted,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                          child: Ink(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color.fromARGB(255, 75, 232, 98),
                                  Color.fromARGB(255, 18, 218, 31),
                                  Color.fromARGB(255, 60, 199, 78)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.all(Radius.circular(30)),
                            ),
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 180, minHeight: 48),
                              alignment: Alignment.center,
                              child: _getStartedLoading
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text(
                                      'Get Started',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // small footer
                        Padding(
                          padding: const EdgeInsets.only(top: 18.0),
                          child: Text(
                            'Version 1.0.0',
                            style: TextStyle(color: Colors.white.withOpacity(0.85)),
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
