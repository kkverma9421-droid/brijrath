import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/driver_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  runApp(const BrijRathApp());
}

class BrijRathApp extends StatelessWidget {
  const BrijRathApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brijरथ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE8741A),
        ),
        useMaterial3: true,
      ),
      home: const _StartupScreen(),
    );
  }
}

// Checks for an existing session on launch and routes to the right screen.
// Shows a loading spinner while the check runs.
class _StartupScreen extends StatefulWidget {
  const _StartupScreen();

  @override
  State<_StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<_StartupScreen> {
  @override
  void initState() {
    super.initState();
    // addPostFrameCallback ensures navigation runs after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSession());
  }

  Future<void> _checkSession() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (!mounted) return;

    if (user == null) {
      // Not logged in → show auth screen
      _go(const AuthScreen());
      return;
    }

    // Already logged in → fetch role and route
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      final role = (data?['role'] as String?) ?? 'customer';
      if (!mounted) return;
      _go(role == 'driver' ? const DriverHomeScreen() : const HomeScreen());
    } catch (_) {
      // If profile fetch fails, default to customer home
      if (mounted) _go(const HomeScreen());
    }
  }

  void _go(Widget screen) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFFF7EA),
      body: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE8741A)),
        ),
      ),
    );
  }
}
