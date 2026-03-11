// lib/login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'services/auth_service.dart';
import 'donor_home.dart';
import 'ngo_home.dart';

enum Role { donor, ngo }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  bool _isLogin = true;
  bool _showPassword = false;
  Role _selectedRole = Role.donor;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _goToHomeFor(User user) async {
    try {
      final snap = await FirebaseDatabase.instance.ref('users/${user.uid}').get();
      final roleStr = snap.exists ? ((snap.value as Map?)?['role'] as String?) : null;
      final role = roleStr == 'ngo' ? Role.ngo : Role.donor;

      if (!mounted) return;

      if (role == Role.donor) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DonorHomeScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const NgoHomeScreen()),
        );
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DonorHomeScreen()),
      );
    }
  }

  Future<void> _saveUserRoleToRealtimeDb(User user) async {
    final isNgo = _selectedRole == Role.ngo;
    await FirebaseDatabase.instance.ref('users/${user.uid}').set({
      'role': isNgo ? 'ngo' : 'donor',
      'email': user.email,
      'displayName': user.displayName,
      'updatedAt': ServerValue.timestamp,
    });
    // Keep a flat list of NGO UIDs so donors can broadcast notifications to all NGOs.
    if (isNgo) {
      await FirebaseDatabase.instance.ref('ngo_list/${user.uid}').set(true);
    }
  }

  void _setLoading(bool v) => setState(() => _loading = v);

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email required';
    if (!RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$').hasMatch(v.trim())) {
      return 'Enter a valid email';
    }
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.trim().isEmpty) return 'Password required';
    if (v.trim().length < 6) return 'Min 6 characters';
    return null;
  }

  Future<void> _emailAuth() async {
    if (!_formKey.currentState!.validate()) return;

    _setLoading(true);
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    try {
      UserCredential cred;

      if (_isLogin) {
        cred = await _auth.signInWithEmail(email, pass);
      } else {
        cred = await _auth.signUpWithEmail(email, pass);
      }

      final user = cred.user;
      if (user != null) {
        if (!_isLogin) {
          // Only save role on account creation, not on every login
          await _saveUserRoleToRealtimeDb(user);
        }
        await _goToHomeFor(user);
      }
    } on FirebaseAuthException catch (e) {
      _showMessage('${e.code}: ${e.message}');
    } catch (e) {
      _showMessage('Error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _googleSignIn() async {
    _setLoading(true);
    try {
      final cred = await _auth.signInWithGoogle();
      if (cred == null) {
        _setLoading(false);
        return;
      }

      final user = cred.user;
      if (user != null) {
        if (cred.additionalUserInfo?.isNewUser == true) {
          // Only save role for brand new Google accounts
          await _saveUserRoleToRealtimeDb(user);
        }
        await _goToHomeFor(user);
      }
    } on FirebaseAuthException catch (e) {
      _showMessage('${e.code}: ${e.message}');
    } catch (e) {
      _showMessage('Google sign-in error: $e');
    } finally {
      _setLoading(false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Widget _roleToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('Donor'),
          selected: _selectedRole == Role.donor,
          onSelected: (_) => setState(() => _selectedRole = Role.donor),
          selectedColor: Colors.green.shade600,
        ),
        const SizedBox(width: 10),
        ChoiceChip(
          label: const Text('NGO'),
          selected: _selectedRole == Role.ngo,
          onSelected: (_) => setState(() => _selectedRole = Role.ngo),
          selectedColor: Colors.purple.shade600,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromARGB(255, 110, 201, 228), Color.fromARGB(255, 37, 180, 252)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),

        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),

            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Login',
                  style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2.0),
                ),

                const SizedBox(height: 14),
                _roleToggle(),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _isLogin = true),
                      child: Text(
                        'Existing',
                        style: TextStyle(
                          color: _isLogin ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                    const Text('|', style: TextStyle(color: Colors.white70)),
                    TextButton(
                      onPressed: () => setState(() => _isLogin = false),
                      child: Text(
                        'Create',
                        style: TextStyle(
                          color: !_isLogin ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        validator: _validateEmail,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          hintText: 'name@example.com',
                          prefixIcon: const Icon(Icons.email),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _passCtrl,
                        obscureText: !_showPassword,
                        validator: _validatePassword,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          hintText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                                _showPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _emailAuth,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            backgroundColor:
                                _isLogin ? Colors.blueAccent : Colors.deepPurpleAccent,
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _isLogin ? 'Login' : 'Create account',
                                  style: const TextStyle(fontSize: 16),
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: const [
                          Expanded(child: Divider(color: Colors.white70)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('or', style: TextStyle(color: Colors.white70)),
                          ),
                          Expanded(child: Divider(color: Colors.white70)),
                        ],
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _googleSignIn,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          icon: Image.asset(
                            'assets/google_logo.png',
                            height: 20,
                            errorBuilder: (_, _, _) => const Icon(Icons.login),
                          ),
                          label: Text(_loading ? 'Please wait...' : 'Continue with Google'),
                        ),
                      ),

                      const SizedBox(height: 8),

                      TextButton(
                        onPressed: () {
                          if (_selectedRole == Role.donor) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const DonorHomeScreen()),
                            );
                          } else {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const NgoHomeScreen()),
                            );
                          }
                        },
                        child: const Text(
                          'Continue as Guest',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
