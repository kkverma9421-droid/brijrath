import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen.dart';
import 'cab_selection_screen.dart';
import 'driver_home_screen.dart';
import 'my_rides_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController   = TextEditingController();

  final List<Map<String, String>> packages = const [
    {
      'title':    'Vrindavan Temple Tour',
      'subtitle': 'Banke Bihari • Prem Mandir • ISKCON',
      'price':    '₹799 onwards',
    },
    {
      'title':    'Mathura Darshan',
      'subtitle': 'Janmabhoomi • Dwarkadhish • Vishram Ghat',
      'price':    '₹999 onwards',
    },
    {
      'title':    'Braj Full Day Yatra',
      'subtitle': 'Gokul • Govardhan • Barsana • Nandgaon',
      'price':    '₹2499 onwards',
    },
  ];

  @override
  void dispose() {
    _pickupController.dispose();
    _dropController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  void _onBookRide() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CabSelectionScreen(
          pickup: _pickupController.text.trim(),
          drop:   _dropController.text.trim(),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7EA),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF8A3F08),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.drive_eta_rounded),
        label: const Text(
          'Driver Mode',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 24),
              _bookingCard(),
              const SizedBox(height: 14),
              _myRidesButton(),
              const SizedBox(height: 24),
              const Text(
                'Popular Braj Tours',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF4A2508),
                ),
              ),
              const SizedBox(height: 14),
              ...packages.map((item) => _packageCard(item)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────────

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 10, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8A3F08), Color(0xFFE8741A)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row with logout button
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Brijरथ 🚕',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.white),
                tooltip: 'Logout',
                onPressed: _logout,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Mathura • Vrindavan • Braj Yatra',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFFFFE8C8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Trusted local rides for pilgrims, families and tourists.',
            style: TextStyle(fontSize: 14, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _myRidesButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.history_rounded, size: 20),
        label: const Text(
          'My Rides',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF8A3F08),
          side: const BorderSide(color: Color(0xFFE8741A), width: 1.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18)),
          backgroundColor: Colors.white,
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyRidesScreen()),
        ),
      ),
    );
  }

  Widget _bookingCard() {
    return Container(
      padding: const EdgeInsets.all(18),
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
        children: [
          _inputField('Pickup Location', Icons.my_location,   _pickupController),
          const SizedBox(height: 12),
          _inputField('Drop Location',   Icons.location_on,   _dropController),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8741A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: _onBookRide,
              child: const Text(
                'Book Ride',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputField(
      String hint, IconData icon, TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFFE8741A)),
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFFFF7EA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _packageCard(Map<String, String> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFD7A8)),
      ),
      child: Row(
        children: [
          Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE1BD),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.temple_hindu,
                color: Color(0xFFE8741A), size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title']!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4A2508),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item['subtitle']!,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                Text(
                  item['price']!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE8741A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
