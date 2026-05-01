import 'package:flutter/material.dart';
import 'booking_confirmation_screen.dart';

class CabSelectionScreen extends StatefulWidget {
  final String pickup;
  final String drop;

  const CabSelectionScreen({
    super.key,
    required this.pickup,
    required this.drop,
  });

  @override
  State<CabSelectionScreen> createState() => _CabSelectionScreenState();
}

class _CabSelectionScreenState extends State<CabSelectionScreen> {
  int _selectedIndex    = -1;
  String _paymentMethod = 'cash'; // default payment method

  final List<Map<String, dynamic>> _cabs = [
    {
      'name': 'Mini',
      'icon': Icons.directions_car,
      'seats': '4 Seats',
      'price': '₹299',
      'desc': 'Compact & affordable for short trips',
    },
    {
      'name': 'Sedan',
      'icon': Icons.directions_car_filled,
      'seats': '4 Seats',
      'price': '₹499',
      'desc': 'Comfortable ride for families',
    },
    {
      'name': 'SUV',
      'icon': Icons.airport_shuttle,
      'seats': '6 Seats',
      'price': '₹799',
      'desc': 'Spacious for groups & luggage',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7EA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8A3F08),
        foregroundColor: Colors.white,
        title: const Text(
          'Choose Your Ride',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _routeSummary(),
            const SizedBox(height: 22),
            const Text(
              'Select Cab Type',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF4A2508),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: _cabs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) => _cabCard(index),
              ),
            ),
            const SizedBox(height: 14),
            _paymentSection(),
            const SizedBox(height: 14),
            _confirmButton(context),
          ],
        ),
      ),
    );
  }

  Widget _routeSummary() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD7A8)),
      ),
      child: Column(
        children: [
          _routeRow(Icons.my_location, const Color(0xFF4CAF50), 'From', widget.pickup),
          const Padding(
            padding: EdgeInsets.only(left: 10),
            child: Icon(Icons.more_vert, color: Color(0xFFE8741A), size: 18),
          ),
          _routeRow(Icons.location_on, const Color(0xFFE8741A), 'To', widget.drop),
        ],
      ),
    );
  }

  Widget _routeRow(IconData icon, Color color, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.black45)),
            Text(
              value.isEmpty ? 'Not specified' : value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4A2508),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cabCard(int index) {
    final cab = _cabs[index];
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF0DC) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? const Color(0xFFE8741A) : const Color(0xFFFFD7A8),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.15),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              height: 60,
              width: 60,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFE8741A)
                    : const Color(0xFFFFE1BD),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                cab['icon'] as IconData,
                color: isSelected ? Colors.white : const Color(0xFFE8741A),
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        cab['name'] as String,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF4A2508),
                        ),
                      ),
                      Text(
                        cab['price'] as String,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: isSelected
                              ? const Color(0xFFE8741A)
                              : const Color(0xFF4A2508),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.people, size: 14, color: Colors.black45),
                      const SizedBox(width: 4),
                      Text(
                        cab['seats'] as String,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black45),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cab['desc'] as String,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isSelected)
              const Icon(Icons.check_circle,
                  color: Color(0xFFE8741A), size: 24),
          ],
        ),
      ),
    );
  }

  // ── Payment method selector ───────────────────────────────────────────────────

  Widget _paymentSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD7A8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pay with',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4A2508),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _payChip('cash', Icons.account_balance_wallet_rounded, 'Cash'),
              const SizedBox(width: 10),
              _payChip('upi',  Icons.phone_android_rounded,           'UPI'),
              const SizedBox(width: 10),
              _payChip('card', Icons.credit_card_rounded,             'Card'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payChip(String value, IconData icon, String label) {
    final selected = _paymentMethod == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _paymentMethod = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFE8741A)
                : const Color(0xFFFFF7EA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFFE8741A)
                  : const Color(0xFFFFD7A8),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: selected ? Colors.white : const Color(0xFF8A3F08),
                  size: 20),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
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

  Widget _confirmButton(BuildContext context) {
    final isEnabled = _selectedIndex != -1;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isEnabled ? const Color(0xFFE8741A) : const Color(0xFFD0B89A),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: isEnabled
            ? () {
                final selected = _cabs[_selectedIndex];
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookingConfirmationScreen(
                      pickup:        widget.pickup,
                      drop:          widget.drop,
                      cabName:       selected['name'] as String,
                      price:         selected['price'] as String,
                      paymentMethod: _paymentMethod,
                    ),
                  ),
                );
              }
            : null,
        child: Text(
          isEnabled
              ? 'Confirm ${_cabs[_selectedIndex]['name']} — ${_cabs[_selectedIndex]['price']}'
              : 'Select a Cab to Continue',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
