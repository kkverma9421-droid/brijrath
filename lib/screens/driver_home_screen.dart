import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/booking_service.dart';
import '../services/fleet_service.dart';
import 'auth_screen.dart';
import 'driver_ride_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _isOnline        = false;
  bool _isConnecting    = false;  // true until the first searching stream emission
  bool _isAcceptingRide = false;

  List<Map<String, dynamic>> _bookings       = [];
  Map<String, dynamic>?      _activeRide;
  List<Map<String, dynamic>> _completedRides = [];

  // Pre-computed so build() never iterates the completed-rides list
  int _cachedTodayEarnings = 0;
  int _cachedTotalEarnings = 0;

  // Realtime stream subscriptions — replace the old 10-second Timer.periodic
  StreamSubscription<List<Map<String, dynamic>>>? _searchingSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _driverSubscription;
  String? _driverId;

  static const String _driverName = 'Ramesh Sharma';

  // ── Helpers ───────────────────────────────────────────────────────────────────

  // Strips "₹" and any non-digit characters, returns the integer value.
  int _parsePrice(String price) {
    final digits = price.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  // Formats an ISO-8601 timestamp to a simple human string, e.g. "26 Apr, 3:45 PM".
  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return 'N/A';
    final dt = DateTime.tryParse(isoDate)?.toLocal();
    if (dt == null) return 'N/A';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                     'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h  = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m  = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month - 1]}, $h:$m $ap';
  }

  // Called once after _completedRides is updated — never inside build().
  void _recomputeEarnings() {
    final today = DateTime.now();
    int todaySum = 0;
    int totalSum = 0;
    for (final r in _completedRides) {
      final paid = (r['paid_amount'] as num?)?.toInt() ?? 0;
      final amount = paid > 0 ? paid : _parsePrice(r['price'] ?? '');
      totalSum += amount;
      final dt = DateTime.tryParse(r['created_at'] ?? '')?.toLocal();
      if (dt != null &&
          dt.year == today.year &&
          dt.month == today.month &&
          dt.day == today.day) {
        todaySum += amount;
      }
    }
    _cachedTodayEarnings = todaySum;
    _cachedTotalEarnings = totalSum;
  }

  // Fixed driver location (Mathura area)
  static const double _driverLat = 27.5000;
  static const double _driverLng = 77.6800;
  // Widened to 50 km for debugging — tighten back to 5.0 once rides appear
  static const double _radiusKm  = 50.0;

  // Haversine formula — returns distance in kilometres between two coordinates
  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthR = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLng / 2) * sin(dLng / 2);
    return earthR * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Resolve driver UUID first, then load history with the right query
    _loadDriverId().then((_) => _loadHistory());
  }

  Future<void> _loadDriverId() async {
    try {
      final rows = await Supabase.instance.client
          .from('drivers')
          .select('id')
          .eq('name', _driverName)
          .limit(1);
      if (rows.isNotEmpty && mounted) {
        setState(() => _driverId = rows.first['id'] as String?);
        debugPrint('[DriverHome] Driver ID resolved: $_driverId');
      } else {
        debugPrint('[DriverHome] No drivers row found for "$_driverName"');
      }
    } catch (e) {
      debugPrint('[DriverHome] _loadDriverId error: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final completed = _driverId != null
          ? await BookingService().fetchCompletedRidesByDriverId(_driverId!)
          : await BookingService().fetchCompletedRides(_driverName);
      if (mounted) {
        setState(() => _completedRides = completed);
        _recomputeEarnings();
      }
    } catch (e) {
      debugPrint('[DriverHome] History load error: $e');
    }
  }

  // ── Online / Offline logic ────────────────────────────────────────────────────

  Future<void> _goOnline() async {
    if (_driverId != null) {
      try {
        await FleetService().toggleDriverOnline(_driverId!, isOnline: true);
      } catch (e) {
        debugPrint('[DriverHome] toggleOnline error: $e');
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Driver profile not found in fleet — online status not synced to server.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    _startStreams();
  }

  Future<void> _goOffline() async {
    _stopStreams();
    if (_driverId != null) {
      try {
        await FleetService().toggleDriverOnline(_driverId!, isOnline: false);
      } catch (e) {
        debugPrint('[DriverHome] toggleOffline error: $e');
      }
    }
    // Clear live rides — history stays visible
    setState(() {
      _bookings   = [];
      _activeRide = null;
    });
  }

  // ── Realtime stream management ────────────────────────────────────────────────

  void _startStreams() {
    _stopStreams(); // cancel any existing subscriptions before creating new ones
    setState(() => _isConnecting = true);

    // ── Stream 1: all bookings with status = 'searching' ──────────────────────
    // Emits the full updated list whenever any searching booking changes.
    _searchingSubscription = Supabase.instance.client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('status', 'searching')
        .order('created_at', ascending: false)
        .listen(
      (rows) {
        if (!mounted) return;

        // Apply nearby distance filter on the client side
        final nearby = <Map<String, dynamic>>[];
        for (final booking in rows) {
          final lat = (booking['pickup_lat'] as num?)?.toDouble();
          final lng = (booking['pickup_lng'] as num?)?.toDouble();
          if (lat == null || lng == null) {
            nearby.add({...booking, '_distance': null});
            continue;
          }
          final dist = _distanceKm(_driverLat, _driverLng, lat, lng);
          if (dist <= _radiusKm) nearby.add({...booking, '_distance': dist});
        }

        debugPrint('[DriverHome] searching stream: '
            '${rows.length} total → ${nearby.length} nearby');

        setState(() {
          _bookings     = nearby;
          _isConnecting = false; // first emission received — hide spinner
        });
      },
      onError: (e) {
        debugPrint('[DriverHome] searching stream error: $e');
        if (mounted) setState(() => _isConnecting = false);
      },
    );

    // ── Stream 2: this driver's bookings (active + history) ───────────────────
    // Filtered by assigned_driver_id so the active ride appears the instant
    // any booking is assigned — whether by autoAssign or manual accept.
    if (_driverId != null) {
      _driverSubscription = Supabase.instance.client
          .from('bookings')
          .stream(primaryKey: ['id'])
          .eq('assigned_driver_id', _driverId!)
          .order('created_at', ascending: false)
          .listen(
        (rows) {
          if (!mounted) return;

          Map<String, dynamic>? active;
          final completed = <Map<String, dynamic>>[];

          for (final row in rows) {
            final status = row['status'] as String? ?? '';
            if (status == 'assigned' || status == 'started') {
              active ??= row; // most recent active ride (list is desc)
            } else if (status == 'completed') {
              completed.add(row);
            }
          }

          debugPrint('[DriverHome] driver stream: '
              'active=${active?['id'] ?? 'none'} | '
              'completed=${completed.length}');

          setState(() {
            _activeRide     = active;
            _completedRides = completed;
          });
          _recomputeEarnings();
        },
        onError: (e) {
          debugPrint('[DriverHome] driver stream error: $e');
        },
      );
    } else {
      debugPrint('[DriverHome] _driverId null — driver stream skipped');
    }
  }

  void _stopStreams() {
    _searchingSubscription?.cancel();
    _driverSubscription?.cancel();
    _searchingSubscription = null;
    _driverSubscription    = null;
  }

  // Used by the RefreshIndicator and AppBar refresh button.
  // Re-subscribing to the streams immediately re-fetches fresh server data.
  Future<void> _onManualRefresh() async {
    if (!_isOnline) return;
    _startStreams();
    // Minimum spinner duration — streams emit within milliseconds on local network
    await Future.delayed(const Duration(milliseconds: 700));
  }

  Future<void> _acceptRide(Map<String, dynamic> booking) async {
    if (_isAcceptingRide) return;
    final bookingId = booking['id'] as String;
    setState(() => _isAcceptingRide = true);

    try {
      await BookingService().acceptRide(bookingId, driverId: _driverId);
      if (!mounted) return;

      setState(() {
        _bookings.removeWhere((b) => b['id'] == bookingId);
        _isAcceptingRide = false;
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DriverRideScreen(
            bookingId:     bookingId,
            pickup:        booking['pickup'] ?? '',
            drop:          booking['drop_location'] ?? '',
            price:         booking['price'] ?? '',
            cabType:       booking['cab_type'] ?? '',
            paymentMethod: booking['payment_method'] ?? 'cash',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isAcceptingRide = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to accept ride. Try again.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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

  @override
  void dispose() {
    _stopStreams();
    super.dispose();
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
          'Driver Dashboard',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        actions: [
          if (_isOnline)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: _isConnecting ? null : _onManualRefresh,
            ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFFE8741A),
          onRefresh: _onManualRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
            children: [
              _driverCard(),
              const SizedBox(height: 16),
              _statsRow(),
              const SizedBox(height: 16),
              _onlineToggleRow(),
              const SizedBox(height: 16),
              ..._bodyChildren(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────────

  // Driver identity card at the top
  Widget _driverCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8A3F08), Color(0xFFE8741A)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            height: 60,
            width: 60,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 34),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ramesh Sharma',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Swift Dzire  •  UP85 AB 1234',
                  style: TextStyle(
                    color: Color(0xFFFFE8C8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Status badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _isOnline
                  ? Colors.green.shade600
                  : Colors.grey.shade600,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _isOnline ? '● Online' : '● Offline',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Online / Offline toggle row
  Widget _onlineToggleRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isOnline
              ? Colors.green.shade200
              : const Color(0xFFFFD7A8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            _isOnline ? Icons.wifi : Icons.wifi_off,
            color: _isOnline ? Colors.green.shade600 : Colors.grey,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isOnline ? 'You are Online' : 'You are Offline',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _isOnline
                        ? Colors.green.shade700
                        : const Color(0xFF4A2508),
                  ),
                ),
                Text(
                  _isOnline
                      ? 'Receiving new ride requests'
                      : 'Toggle to start accepting rides',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),
          Switch(
            value: _isOnline,
            activeColor: Colors.green.shade600,
            onChanged: (val) {
              setState(() => _isOnline = val);
              val ? _goOnline() : _goOffline();
            },
          ),
        ],
      ),
    );
  }

  // Returns the dynamic body widgets as a flat list so the parent ListView
  // can own the one and only scroll axis — no nested scrollables.
  List<Widget> _bodyChildren() {
    final hasActive    = _activeRide != null;
    final hasSearching = _bookings.isNotEmpty;
    final hasHistory   = _completedRides.isNotEmpty;

    final items = <Widget>[];

    if (!_isOnline) {
      // ── Offline ─────────────────────────────────────────────────────────
      items.add(_inlineNotice(
        icon: Icons.drive_eta_rounded,
        iconColor: Colors.grey.shade400,
        title: 'You are Offline',
        subtitle: 'Go online to start receiving ride requests.',
      ));
    } else if (_isConnecting && !hasActive && !hasSearching) {
      // ── First-load spinner ───────────────────────────────────────────────
      items.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE8741A)),
          ),
        ),
      ));
    } else if (hasActive) {
      // ── Active ride (driver already on a job) ────────────────────────────
      items.add(_sectionLabel(
        icon: Icons.directions_car,
        label: 'Active Ride',
        color: Colors.green.shade700,
      ));
      items.add(const SizedBox(height: 10));
      items.add(_activeRideCard(_activeRide!));
      items.add(const SizedBox(height: 20));
    } else if (hasSearching) {
      // ── Available rides ──────────────────────────────────────────────────
      items.add(_sectionLabel(
        icon: Icons.search_rounded,
        label: 'Available Rides',
        color: const Color(0xFF4A2508),
        count: _bookings.length,
      ));
      items.add(const SizedBox(height: 10));
      for (final booking in _bookings) {
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _bookingCard(booking),
        ));
      }
    } else {
      // ── No rides ─────────────────────────────────────────────────────────
      items.add(_inlineNotice(
        icon: Icons.search_off_rounded,
        iconColor: const Color(0xFFFFD7A8),
        title: 'No Rides Available',
        subtitle: 'Waiting for passengers... You will be notified instantly.',
      ));
    }

    // ── Ride History (always appended below the live section) ───────────────
    if (hasHistory) {
      items.add(const SizedBox(height: 8));
      items.add(const Divider(color: Color(0xFFFFE8C8), thickness: 1));
      items.add(const SizedBox(height: 12));
      items.add(_sectionLabel(
        icon: Icons.history_rounded,
        label: 'Ride History',
        color: const Color(0xFF4A2508),
        count: _completedRides.length,
      ));
      items.add(const SizedBox(height: 10));
      for (final ride in _completedRides) {
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _rideHistoryCard(ride),
        ));
      }
      items.add(const SizedBox(height: 8));
    }

    return items;
  }

  // Inline empty-state notice (used inside a ListView, not as a full-screen fill)
  Widget _inlineNotice({
    required IconData icon,
    required String title,
    required String subtitle,
    Color iconColor = const Color(0xFFFFD7A8),
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 60, color: iconColor),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A2508),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  // Small section header with optional count badge
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

  Widget _centeredMessage({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: iconColor),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A2508),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  // Three-box stats bar: Today's Earnings, Completed Rides, Active Rides
  Widget _statsRow() {
    return Row(
      children: [
        _statBox(
          label: "Today's\nEarnings",
          value: '₹$_cachedTodayEarnings',
          icon: Icons.today_rounded,
          bgColor: const Color(0xFFFFF0DC),
          valueColor: const Color(0xFFE8741A),
        ),
        const SizedBox(width: 10),
        _statBox(
          label: 'Total\nEarnings',
          value: '₹$_cachedTotalEarnings',
          icon: Icons.account_balance_wallet_rounded,
          bgColor: const Color(0xFFEEFAEE),
          valueColor: Colors.green.shade700,
        ),
        const SizedBox(width: 10),
        _statBox(
          label: 'Completed\nRides',
          value: '${_completedRides.length}',
          icon: Icons.check_circle_outline_rounded,
          bgColor: const Color(0xFFE8F4FD),
          valueColor: Colors.blue.shade700,
        ),
      ],
    );
  }

  Widget _statBox({
    required String label,
    required String value,
    required IconData icon,
    required Color bgColor,
    required Color valueColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: valueColor.withOpacity(0.20)),
        ),
        child: Column(
          children: [
            Icon(icon, color: valueColor, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.black45,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Compact card for a completed ride in the history list
  Widget _rideHistoryCard(Map<String, dynamic> ride) {
    final pickup     = ride['pickup']        ?? 'N/A';
    final drop       = ride['drop_location'] ?? 'N/A';
    final cabType    = ride['cab_type']      ?? '';
    final price      = ride['price']         ?? 'N/A';
    final dateStr    = _formatDate(ride['created_at'] as String?);
    final paidAmount = (ride['paid_amount'] as num?)?.toInt() ?? 0;
    final payMethod  = (ride['payment_method'] as String? ?? 'cash').toUpperCase();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFE8C8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Green check circle
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle_rounded,
                color: Colors.green.shade600, size: 22),
          ),
          const SizedBox(width: 12),

          // Route + meta
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
                  children: const [
                    Icon(Icons.arrow_downward_rounded,
                        size: 11, color: Colors.black38),
                  ],
                ),
                // Drop
                Text(
                  drop,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4A2508),
                  ),
                ),
                const SizedBox(height: 6),
                // Cab type + date
                Text(
                  '$cabType  •  $dateStr',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Paid amount + payment method badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                paidAmount > 0 ? '₹$paidAmount' : price,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFE8741A),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0DC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFFD7A8)),
                ),
                child: Text(
                  payMethod,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A3F08),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activeRideCard(Map<String, dynamic> booking) {
    final pickup  = booking['pickup']        ?? 'N/A';
    final drop    = booking['drop_location'] ?? 'N/A';
    final price   = booking['price']         ?? 'N/A';
    final status  = booking['status']        ?? 'assigned';

    // Status chip colour: green for assigned, blue for started
    final isStarted  = status == 'started';
    final chipColor  = isStarted ? Colors.blue.shade600 : Colors.green.shade600;
    final chipLabel  = isStarted ? 'Ride Started' : 'Ride Assigned';
    final chipIcon   = isStarted ? Icons.directions_car : Icons.person_pin_circle;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isStarted ? Colors.blue.shade200 : Colors.green.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isStarted ? Colors.blue : Colors.green).withOpacity(0.10),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: chipColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(chipIcon, color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Text(
                  chipLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Pickup / Drop
          _locationRow(Icons.my_location, Colors.green.shade600, 'Pickup', pickup),
          const Padding(
            padding: EdgeInsets.only(left: 10),
            child: Icon(Icons.more_vert, color: Color(0xFFE8741A), size: 16),
          ),
          _locationRow(Icons.location_on, const Color(0xFFE8741A), 'Drop', drop),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFFFFE8C8), height: 1),
          const SizedBox(height: 14),

          // Price + Continue Ride button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0DC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD7A8)),
                ),
                child: Text(
                  price,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFE8741A),
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: const Text(
                  'Continue Ride',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isStarted
                      ? Colors.blue.shade600
                      : Colors.green.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DriverRideScreen(
                      bookingId:     booking['id'] as String,
                      pickup:        pickup,
                      drop:          drop,
                      price:         price,
                      cabType:       booking['cab_type'] ?? '',
                      paymentMethod: booking['payment_method'] ?? 'cash',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bookingCard(Map<String, dynamic> booking) {
    final pickup = booking['pickup'] ?? 'N/A';
    final drop = booking['drop_location'] ?? 'N/A';
    final price = booking['price'] ?? 'N/A';
    final cabType = booking['cab_type'] ?? 'N/A';
    final distKm = booking['_distance'] as double?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD7A8)),
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pickup row
          _locationRow(
              Icons.my_location, Colors.green.shade600, 'Pickup', pickup),
          const Padding(
            padding: EdgeInsets.only(left: 10),
            child: Icon(Icons.more_vert, color: Color(0xFFE8741A), size: 16),
          ),
          // Drop row
          _locationRow(
              Icons.location_on, const Color(0xFFE8741A), 'Drop', drop),
          const SizedBox(height: 10),

          // Distance chip
          if (distKm != null)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F4FD),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.near_me_rounded,
                          size: 13, color: Colors.blue.shade600),
                      const SizedBox(width: 4),
                      Text(
                        '${distKm.toStringAsFixed(1)} km away',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          const Divider(color: Color(0xFFFFE8C8), height: 1),
          const SizedBox(height: 14),

          // Price + cab type + Accept button
          Row(
            children: [
              // Price badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0DC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD7A8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFE8741A),
                      ),
                    ),
                    Text(
                      cabType,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black45),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Accept button
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text(
                  'Accept Ride',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8741A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isAcceptingRide ? null : () => _acceptRide(booking),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _locationRow(
      IconData icon, Color color, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 10, color: Colors.black45)),
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
