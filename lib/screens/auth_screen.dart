import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'driver_home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl     = TextEditingController();

  bool _isLogin         = true;   // toggle between Login / Sign Up
  bool _isLoading       = false;
  bool _obscurePassword = true;
  String _role          = 'customer'; // 'customer' or 'driver'

  final _supabase = Supabase.instance.client;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── Auth actions ──────────────────────────────────────────────────────────────

  Future<void> _login() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter email and password.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final res = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.user == null) {
        _showError('Login failed. Please try again.');
        return;
      }
      await _routeByProfile(res.user!.id);
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Something went wrong. Check your connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signup() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final name     = _nameCtrl.text.trim();
    if (email.isEmpty || password.isEmpty || name.isEmpty) {
      _showError('Please fill in all fields.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final res = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      final user = res.user;
      // Email confirmation is required when user is null after signUp
      if (user == null) {
        _showInfo('Check your email to confirm your account, then log in.');
        setState(() => _isLogin = true);
        return;
      }
      // Insert profile row
      await _supabase.from('profiles').insert({
        'id':         user.id,
        'email':      email,
        'role':       _role,
        'full_name':  name,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      _navigateTo(_role);
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Something went wrong. Check your connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Fetch profile role then route to the correct home screen
  Future<void> _routeByProfile(String userId) async {
    try {
      final data = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      final role = (data?['role'] as String?) ?? 'customer';
      _navigateTo(role);
    } catch (_) {
      _navigateTo('customer');
    }
  }

  void _navigateTo(String role) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            role == 'driver' ? const DriverHomeScreen() : const HomeScreen(),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.blue.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7EA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 32),
              _formCard(),
              const SizedBox(height: 18),
              _toggleModeButton(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────────

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // App logo strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8A3F08), Color(0xFFE8741A)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Text(
            'Brijरथ 🚕',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _isLogin ? 'Welcome back!' : 'Create your account',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF4A2508),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Mathura • Vrindavan • Braj Yatra',
          style: TextStyle(fontSize: 13, color: Colors.black45),
        ),
      ],
    );
  }

  Widget _formCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Full name — signup only
          if (!_isLogin) ...[
            _inputField(
              controller: _nameCtrl,
              hint: 'Full Name',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 14),
          ],

          _inputField(
            controller: _emailCtrl,
            hint: 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),

          _inputField(
            controller: _passwordCtrl,
            hint: 'Password',
            icon: Icons.lock_outline,
            obscure: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.black38,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),

          // Role selector — signup only
          if (!_isLogin) ...[
            const SizedBox(height: 20),
            const Text(
              'I want to:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4A2508),
              ),
            ),
            const SizedBox(height: 10),
            _roleSelector(),
          ],

          const SizedBox(height: 22),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : (_isLogin ? _login : _signup),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8741A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(
                      _isLogin ? 'Login' : 'Create Account',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFFE8741A)),
        hintText: hint,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFFFF7EA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _roleSelector() {
    return Row(
      children: [
        _roleChip(label: 'Book a Ride', icon: Icons.person_rounded,    value: 'customer'),
        const SizedBox(width: 12),
        _roleChip(label: 'Drive & Earn', icon: Icons.drive_eta_rounded, value: 'driver'),
      ],
    );
  }

  Widget _roleChip({
    required String label,
    required IconData icon,
    required String value,
  }) {
    final selected = _role == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _role = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE8741A) : const Color(0xFFFFF7EA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFFE8741A)
                  : const Color(0xFFFFD7A8),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? Colors.white : const Color(0xFF8A3F08),
                  size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF4A2508),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleModeButton() {
    return Center(
      child: TextButton(
        onPressed: () {
          setState(() {
            _isLogin = !_isLogin;
            _emailCtrl.clear();
            _passwordCtrl.clear();
            _nameCtrl.clear();
          });
        },
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 14, color: Colors.black54),
            children: [
              TextSpan(
                text: _isLogin
                    ? "Don't have an account? "
                    : 'Already have an account? ',
              ),
              TextSpan(
                text: _isLogin ? 'Sign Up' : 'Login',
                style: const TextStyle(
                  color: Color(0xFFE8741A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
