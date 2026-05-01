import 'package:flutter/material.dart';
import '../services/booking_service.dart';
import 'driver_tracking_screen.dart';

class MyRidesScreen extends StatefulWidget {
  const MyRidesScreen({super.key});

  @override
  State<MyRidesScreen> createState() => _MyRidesScreenState();
}

class _MyRidesScreenState extends State<MyRidesScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _allRides = [];

  // ── Derived lists ─────────────────────────────────────────────────────────────

  // The most recent booking that is still in progress (only one expected at a time)
  Map<String, dynamic>? get _activeRide {
    const activeStatuses = {'searching', 'assigned', 'started'};
    for (final ride in _allRides) {
      if (activeStatuses.contains(ride['status'])) return ride;
    }
    return null;
  }

  List<Map<String, dynamic>> get _pastRides =>
      _allRides.where((r) => r['status'] == 'completed').toList();

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    final dt = DateTime.tryParse(isoDate)?.toLocal();
    if (dt == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h  = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m  = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month - 1]}, $h:$m $ap';
  }

  // Human-readable label + colour for each status value
  ({String label, Color color, IconData icon}) _statusMeta(String status) {
    switch (status) {
      case 'assigned':
        return (
          label: 'Driver Assigned',
          color: Colors.green.shade600,
          icon: Icons.person_pin_circle,
        );
      case 'started':
        return (
          label: 'Ride Started',
          color: Colors.blue.shade600,
          icon: Icons.directions_car,
        );
      case 'completed':
        return (
          label: 'Completed',
          color: Colors.green.shade700,
          icon: Icons.check_circle,
        );
      default: // 'searching'
        return (
          label: 'Searching Driver',
          color: const Color(0xFFE8741A),
          icon: Icons.search_rounded,
        );
    }
  }

  // ── Data loading ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final rides = await BookingService().fetchAllRides();
      if (mounted) setState(() => _allRides = rides);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not load rides. Check connection.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7EA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8A3F08),
        foregroundColor: Colors.white,
        title: const Text(
          'My Rides',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: _isLoading && _allRides.isEmpty
          ? const Center(
              child: CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFFE8741A)),
              ),
            )
          : _allRides.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  color: const Color(0xFFE8741A),
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                    children: [
                      // ── Active Ride ───────────────────────────────────────
                      if (_activeRide != null) ...[
                        _sectionLabel(
                          icon: Icons.directions_car_rounded,
                          label: 'Active Ride',
                          color: Colors.green.shade700,
                        ),
                        const SizedBox(height: 10),
                        _activeRideCard(_activeRide!),
                        const SizedBox(height: 24),
                      ],

                      // ── Past Rides ────────────────────────────────────────
                      if (_pastRides.isNotEmpty) ...[
                        _sectionLabel(
                          icon: Icons.history_rounded,
                          label: 'Past Rides',
                          color: const Color(0xFF4A2508),
                          count: _pastRides.length,
                        ),
                        const SizedBox(height: 10),
                        ...List.generate(
                          _pastRides.length,
                          (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _pastRideCard(_pastRides[i]),
                          ),
                        ),
                      ],

                      // No completed rides yet (but active exists — already shown)
                      if (_activeRide != null && _pastRides.isEmpty)
                        _inlineNote('No past rides yet.'),
                    ],
                  ),
                ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────────

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_car_outlined,
              size: 80, color: Colors.orange.shade200),
          const SizedBox(height: 18),
          const Text(
            'No rides yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4A2508),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Book your first BrijRath ride\nfrom the home screen.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel({
    required IconData icon,
    required String label,
    required Color color,
    int? count,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE8741A),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _inlineNote(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: Colors.black38),
      ),
    );
  }

  // Highlighted card for an in-progress ride
  Widget _activeRideCard(Map<String, dynamic> ride) {
    final pickup   = ride['pickup']        ?? 'N/A';
    final drop     = ride['drop_location'] ?? 'N/A';
    final cabType  = ride['cab_type']      ?? '';
    final price    = ride['price']         ?? 'N/A';
    final status   = ride['status']        as String? ?? 'searching';
    final meta     = _statusMeta(status);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: meta.color.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: meta.color.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status chip
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: meta.color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(meta.icon, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      meta.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                price,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFE8741A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Pickup
          _routeRow(Icons.my_location, Colors.green.shade600, 'Pickup', pickup),
          Padding(
            padding: const EdgeInsets.only(left: 9),
            child: Icon(Icons.more_vert,
                color: Colors.orange.shade300, size: 16),
          ),
          // Drop
          _routeRow(
              Icons.location_on, const Color(0xFFE8741A), 'Drop', drop),

          const SizedBox(height: 12),
          const Divider(color: Color(0xFFFFE8C8), height: 1),
          const SizedBox(height: 12),

          // Cab type + Track button
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0DC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFD7A8)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_car_filled,
                        size: 14, color: Color(0xFF8A3F08)),
                    const SizedBox(width: 5),
                    Text(
                      cabType.isEmpty ? 'Cab' : cabType,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4A2508),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Track Ride — only makes sense once a driver is on the way
              if (status != 'searching')
                ElevatedButton.icon(
                  icon: const Icon(Icons.gps_fixed, size: 16),
                  label: const Text(
                    'Track Ride',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8741A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriverTrackingScreen(
                        bookingId: ride['id'] as String? ?? '',
                        pickup: pickup,
                        drop: drop,
                        currentStatus: meta.label,
                      ),
                    ),
                  ),
                )
              else
                // While searching, just show a quiet pulse indicator
                Row(
                  children: [
                    SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.orange.shade400),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Finding driver...',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade700),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // Compact card for a completed ride
  Widget _pastRideCard(Map<String, dynamic> ride) {
    final pickup  = ride['pickup']        ?? 'N/A';
    final drop    = ride['drop_location'] ?? 'N/A';
    final price   = ride['price']         ?? 'N/A';
    final dateStr = _formatDate(ride['created_at'] as String?);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFE8C8)),
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Green check circle on the left
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.green.shade100),
            ),
            child: Icon(Icons.check_circle_rounded,
                color: Colors.green.shade600, size: 24),
          ),
          const SizedBox(width: 12),

          // Route + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pickup
                Text(
                  pickup,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4A2508),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.arrow_downward_rounded,
                        size: 11, color: Colors.orange.shade300),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        drop,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4A2508),
                        ),
                      ),
                    ),
                  ],
                ),
                if (dateStr.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    dateStr,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black38),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Price + Completed badge stacked on the right
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFE8741A),
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  'Completed',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _routeRow(IconData icon, Color color, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.black45)),
            Text(
              value,
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
}
