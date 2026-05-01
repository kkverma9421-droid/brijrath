import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/booking_service.dart';

enum _RideState { assigned, started, completed }

class DriverRideScreen extends StatefulWidget {
  final String bookingId;
  final String pickup;
  final String drop;
  final String price;
  final String cabType;
  final String paymentMethod;

  const DriverRideScreen({
    super.key,
    required this.bookingId,
    required this.pickup,
    required this.drop,
    required this.price,
    required this.cabType,
    this.paymentMethod = 'cash',
  });

  @override
  State<DriverRideScreen> createState() => _DriverRideScreenState();
}

class _DriverRideScreenState extends State<DriverRideScreen> {
  _RideState _rideState = _RideState.assigned;
  bool _isLoading = false;

  // Fallback dummy waypoints used when GPS is unavailable
  static const _simLats = [27.5000, 27.5140, 27.5280, 27.5420, 27.5560, 27.5706];
  static const _simLngs = [77.6800, 77.6840, 77.6880, 77.6920, 77.6960, 77.7006];

  StreamSubscription<Position>? _positionStream;
  Timer? _fallbackTimer;
  int _fallbackStep = 0;

  // ── Start Ride ────────────────────────────────────────────────────────────────

  Future<void> _startRide() async {
    setState(() => _isLoading = true);
    try {
      await BookingService().updateBookingStatus(widget.bookingId, 'started');
      if (mounted) {
        setState(() => _rideState = _RideState.started);
        await _startGpsTracking();
      }
    } catch (e) {
      _showError('Failed to start ride. Check connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startGpsTracking() async {
    // Guard: don't start a second stream if one is already running
    if (_positionStream != null) return;

    // Step 1: Check if device GPS is switched on
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showInfo('GPS is turned off. Using demo tracking.');
      _startFallbackSimulation();
      return;
    }

    // Step 2: Check and request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showError('Location permission denied. Using demo tracking.');
      _startFallbackSimulation();
      return;
    }

    // Step 3: Start real GPS stream
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // emit update every 10 metres of movement
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position pos) async {
        // Guard: discard updates that arrive after the ride has ended
        if (_rideState != _RideState.started || !mounted) return;
        try {
          await BookingService().updateDriverLocation(
            widget.bookingId,
            pos.latitude,
            pos.longitude,
          );
        } catch (_) {
          // best-effort — ignore individual upload failures
        }
      },
      onError: (_) {
        _showInfo('GPS error. Switched to demo tracking.');
        _positionStream?.cancel();
        _positionStream = null;
        if (_rideState == _RideState.started) _startFallbackSimulation();
      },
      onDone: () => _positionStream = null,
      cancelOnError: false,
    );
  }

  // Used when real GPS is unavailable — steps through hardcoded waypoints
  void _startFallbackSimulation() {
    // Guard: don't start a second timer if one is already running
    if (_fallbackTimer != null) return;
    _fallbackStep = 0;
    _fallbackTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      // Stop if ride ended or widget unmounted
      if (_rideState != _RideState.started || !mounted) {
        _fallbackTimer?.cancel();
        _fallbackTimer = null;
        return;
      }
      if (_fallbackStep >= _simLats.length) {
        _fallbackTimer?.cancel();
        _fallbackTimer = null;
        return;
      }
      try {
        await BookingService().updateDriverLocation(
          widget.bookingId,
          _simLats[_fallbackStep],
          _simLngs[_fallbackStep],
        );
      } catch (_) {}
      _fallbackStep++;
    });
  }

  // ── Complete Ride ─────────────────────────────────────────────────────────────

  Future<void> _completeRide() async {
    _positionStream?.cancel();
    _positionStream = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    setState(() => _isLoading = true);
    try {
      // Parse numeric rupee amount from price string (e.g. "₹299" → 299)
      final amount = int.tryParse(
            widget.price.replaceAll(RegExp(r'[^0-9]'), ''),
          ) ?? 0;
      await BookingService()
          .completeRideWithPayment(widget.bookingId, amount);
      if (mounted) setState(() => _rideState = _RideState.completed);
    } catch (e) {
      _showError('Failed to complete ride. Check connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _fallbackTimer?.cancel();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  // Shown when driver tries to back out while GPS is actively streaming
  Future<void> _confirmExitDuringRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave active ride?'),
        content: const Text(
          'GPS tracking will stop and the customer will no longer see your location. '
          'The booking will stay assigned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) Navigator.pop(context);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block the system back gesture only while GPS is actively streaming
      canPop: _rideState != _RideState.started,
      onPopInvoked: (didPop) {
        if (!didPop) _confirmExitDuringRide();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF7EA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF8A3F08),
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: const Text(
            'Your Ride',
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
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _rideIconBadge(),
                      const SizedBox(height: 24),
                      _rideDetailsCard(),
                      const SizedBox(height: 16),
                      _statusCard(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _actionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────────

  Widget _rideIconBadge() {
    final color = _rideState == _RideState.completed
        ? Colors.green.shade600
        : const Color(0xFFE8741A);
    final icon = _rideState == _RideState.completed
        ? Icons.check_circle_outline
        : Icons.directions_car;

    return Container(
      height: 90,
      width: 90,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _rideState == _RideState.completed
              ? [const Color(0xFF2E7D32), Colors.green.shade500]
              : [const Color(0xFF8A3F08), const Color(0xFFE8741A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 44),
    );
  }

  Widget _rideDetailsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFD7A8)),
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ride Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4A2508),
            ),
          ),
          const SizedBox(height: 16),
          _detailRow(Icons.my_location, Colors.green.shade600, 'Pickup',
              widget.pickup.isEmpty ? 'Not specified' : widget.pickup),
          _divider(),
          _detailRow(Icons.location_on, const Color(0xFFE8741A), 'Drop',
              widget.drop.isEmpty ? 'Not specified' : widget.drop),
          _divider(),
          _detailRow(Icons.directions_car_filled, const Color(0xFF8A3F08),
              'Cab Type',
              widget.cabType.isEmpty ? 'Not specified' : widget.cabType),
          _divider(),
          _detailRow(Icons.currency_rupee, const Color(0xFFE8741A), 'Fare',
              widget.price.isEmpty ? 'Not specified' : widget.price),
          _divider(),
          _detailRow(Icons.person_pin_circle, const Color(0xFFE8741A),
              'Driver', 'Ramesh Sharma'),
          _divider(),
          _detailRow(Icons.directions_car, const Color(0xFF8A3F08),
              'Vehicle', 'Swift Dzire  •  UP85 AB 1234'),
          _divider(),
          _detailRow(
            _paymentIcon(widget.paymentMethod),
            const Color(0xFF8A3F08),
            'Payment',
            _paymentLabel(widget.paymentMethod),
          ),
        ],
      ),
    );
  }

  IconData _paymentIcon(String method) {
    switch (method) {
      case 'upi':  return Icons.phone_android_rounded;
      case 'card': return Icons.credit_card_rounded;
      default:     return Icons.account_balance_wallet_rounded;
    }
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'upi':  return 'Collect via UPI';
      case 'card': return 'Collect via Card';
      default:     return 'Collect Cash';
    }
  }

  Widget _detailRow(
      IconData icon, Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.black45)),
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
      ),
    );
  }

  Widget _divider() =>
      const Divider(color: Color(0xFFFFE8C8), thickness: 1, height: 4);

  Widget _statusCard() {
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final IconData icon;
    final String title;
    final String subtitle;

    switch (_rideState) {
      case _RideState.assigned:
        bgColor = const Color(0xFFFFF0DC);
        borderColor = const Color(0xFFFFD7A8);
        textColor = const Color(0xFF4A2508);
        icon = Icons.hourglass_empty_rounded;
        title = 'Ride Assigned';
        subtitle = 'Tap Start Ride when you have reached the passenger.';
        break;
      case _RideState.started:
        bgColor = const Color(0xFFE8F4FD);
        borderColor = Colors.blue.shade200;
        textColor = Colors.blue.shade700;
        icon = Icons.directions_car;
        title = 'Ride in Progress';
        subtitle = 'GPS is sending your live location. Tap Complete Ride at destination.';
        break;
      case _RideState.completed:
        bgColor = const Color(0xFFEEFAEE);
        borderColor = Colors.green.shade200;
        textColor = Colors.green.shade700;
        icon = Icons.check_circle;
        title = 'Ride Completed!';
        subtitle = 'Great job! The passenger has been dropped off.';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(color: textColor, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButtons() {
    return Column(
      children: [
        // Start Ride button — visible only when assigned
        if (_rideState == _RideState.assigned)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_circle_outline, size: 22),
                label: const Text(
                  'Start Ride',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8741A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isLoading ? null : _startRide,
              ),
            ),
          ),

        // Complete Ride button — visible only when started
        if (_rideState == _RideState.started)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.flag_rounded, size: 22),
                label: const Text(
                  'Complete Ride',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isLoading ? null : _completeRide,
              ),
            ),
          ),

        // Loading indicator while Supabase call is in progress
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation<Color>(Color(0xFFE8741A)),
            ),
          ),

        // Back to Dashboard — always visible
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.dashboard_rounded, size: 20),
            label: const Text(
              'Back to Dashboard',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8A3F08),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }
}
