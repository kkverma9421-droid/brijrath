import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/booking_service.dart';
import 'driver_tracking_screen.dart';

// Real statuses that actually exist in Supabase (driver app writes these).
// on_the_way / arrived were simulation-only and are now removed.
enum _BookingState { saving, searching, assigned, started, completed, error }

class BookingConfirmationScreen extends StatefulWidget {
  final String pickup;
  final String drop;
  final String cabName;
  final String price;
  final String paymentMethod;

  const BookingConfirmationScreen({
    super.key,
    required this.pickup,
    required this.drop,
    required this.cabName,
    required this.price,
    this.paymentMethod = 'cash',
  });

  @override
  State<BookingConfirmationScreen> createState() =>
      _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends State<BookingConfirmationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  _BookingState _bookingState = _BookingState.saving;
  String? _bookingId;

  // Populated from Supabase row once driver accepts
  String _driverName = 'Searching...';
  String _vehicleName = '';

  // Supabase Realtime stream subscription
  StreamSubscription<Map<String, dynamic>?>? _bookingSubscription;

  // ── Computed helpers ──────────────────────────────────────────────────────────

  // Maps the current state to which step dot should be active (0-based)
  int get _currentStepIndex {
    switch (_bookingState) {
      case _BookingState.saving:    return -1;
      case _BookingState.searching: return 0;
      case _BookingState.assigned:  return 1;
      case _BookingState.started:   return 2;
      case _BookingState.completed: return 3;
      case _BookingState.error:     return -1;
    }
  }

  bool get _isCompleted     => _bookingState == _BookingState.completed;
  bool get _isError         => _bookingState == _BookingState.error;

  // Show driver card once a driver is assigned
  bool get _isDriverVisible => {
        _BookingState.assigned,
        _BookingState.started,
        _BookingState.completed,
      }.contains(_bookingState);

  Color get _cardBgColor {
    switch (_bookingState) {
      case _BookingState.assigned:
      case _BookingState.completed: return const Color(0xFFEEFAEE);
      case _BookingState.started:   return const Color(0xFFE8F4FD);
      case _BookingState.error:     return const Color(0xFFFFF0F0);
      default:                      return const Color(0xFFFFF0DC);
    }
  }

  Color get _cardBorderColor {
    switch (_bookingState) {
      case _BookingState.assigned:
      case _BookingState.completed: return Colors.green.shade200;
      case _BookingState.started:   return Colors.blue.shade200;
      case _BookingState.error:     return Colors.red.shade200;
      default:                      return const Color(0xFFFFD7A8);
    }
  }

  Color get _statusTextColor {
    switch (_bookingState) {
      case _BookingState.assigned:
      case _BookingState.completed: return Colors.green.shade700;
      case _BookingState.started:   return Colors.blue.shade700;
      case _BookingState.error:     return Colors.red.shade700;
      default:                      return const Color(0xFF4A2508);
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _saveBooking();
  }

  @override
  void dispose() {
    _bookingSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Core logic ────────────────────────────────────────────────────────────────

  // Step 1: Insert booking → subscribe to realtime.
  // BookingService.saveBooking() calls autoAssignRide() internally — if a
  // driver is online the stream below will see the status flip to 'assigned'.
  Future<void> _saveBooking() async {
    try {
      final id = await BookingService().saveBooking(
        pickup:        widget.pickup,
        drop:          widget.drop,
        cabType:       widget.cabName,
        price:         widget.price,
        paymentMethod: widget.paymentMethod,
      );
      _bookingId = id;

      if (!mounted) return;
      setState(() => _bookingState = _BookingState.searching);

      // Stream watches for any status change the driver app writes (assigned /
      // started / completed) and updates the customer UI automatically.
      _startWatching(id);
    } on PostgrestException catch (e, st) {
      debugPrint('─── BOOKING SCREEN ERROR [PostgrestException] ────────');
      debugPrint('  message : ${e.message}');
      debugPrint('  code    : ${e.code}');
      debugPrint('  details : ${e.details}');
      debugPrint('  hint    : ${e.hint}');
      debugPrint('  stack   : $st');
      debugPrint('──────────────────────────────────────────────────────');
      if (mounted) setState(() => _bookingState = _BookingState.error);
    } catch (e, st) {
      debugPrint('─── BOOKING SCREEN ERROR [${e.runtimeType}] ──────────');
      debugPrint('  error : $e');
      debugPrint('  stack : $st');
      debugPrint('──────────────────────────────────────────────────────');
      if (mounted) setState(() => _bookingState = _BookingState.error);
    }
  }

  // Step 2: Subscribe to the Supabase row — UI updates whenever driver changes status
  void _startWatching(String id) {
    _bookingSubscription?.cancel(); // cancel any previous subscription first

    _bookingSubscription = BookingService().watchBooking(id).listen(
      (row) {
        if (row == null || !mounted) return;

        final status = row['status'] as String? ?? 'searching';
        final driverName = row['driver_name'] as String?;
        final vehicle = row['vehicle'] as String?;

        setState(() {
          _bookingState = _fromSupabaseStatus(status);
          if (driverName != null && driverName.isNotEmpty) {
            _driverName = driverName;
          }
          if (vehicle != null && vehicle.isNotEmpty) {
            _vehicleName = vehicle;
          }
        });
      },
      onError: (e, st) {
        debugPrint('─── BOOKING STREAM ERROR [${e.runtimeType}] ──────────');
        debugPrint('  error : $e');
        debugPrint('  stack : $st');
        if (e is PostgrestException) {
          debugPrint('  message : ${e.message}');
          debugPrint('  code    : ${e.code}');
          debugPrint('  details : ${e.details}');
          debugPrint('  hint    : ${e.hint}');
        }
        debugPrint('──────────────────────────────────────────────────────');
        if (mounted) setState(() => _bookingState = _BookingState.error);
      },
    );
  }

  // Maps a Supabase status string to a local enum value
  _BookingState _fromSupabaseStatus(String status) {
    switch (status) {
      case 'assigned':  return _BookingState.assigned;
      case 'started':   return _BookingState.started;
      case 'completed': return _BookingState.completed;
      default:          return _BookingState.searching;
    }
  }

  // ── Cancel / Home ─────────────────────────────────────────────────────────────

  void _cancelBooking() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Cancel Booking?',
          style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF4A2508)),
        ),
        content: const Text('Are you sure you want to cancel this ride?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE8741A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  void _backToHome() =>
      Navigator.popUntil(context, (route) => route.isFirst);

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7EA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8A3F08),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Text(
          _isCompleted ? 'Ride Completed!' : 'Booking Confirmed!',
          style: const TextStyle(fontWeight: FontWeight.w800),
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
                    _cabIconBadge(),
                    const SizedBox(height: 20),
                    _stepProgressBar(),
                    const SizedBox(height: 20),
                    _bookingSummaryCard(),
                    const SizedBox(height: 16),
                    _statusCard(),
                    if (_isDriverVisible) ...[
                      const SizedBox(height: 16),
                      _driverCard(),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _actionButtons(),
          ],
        ),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────────

  Widget _cabIconBadge() {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        height: 100,
        width: 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isCompleted
                ? [const Color(0xFF2E7D32), const Color(0xFF4CAF50)]
                : [const Color(0xFF8A3F08), const Color(0xFFE8741A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (_isCompleted ? Colors.green : Colors.orange)
                  .withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(
          _isCompleted ? Icons.check_circle_outline : Icons.directions_car,
          color: Colors.white,
          size: 48,
        ),
      ),
    );
  }

  // 4-dot progress bar: Search → Assigned → Started → Done
  Widget _stepProgressBar() {
    const labels = ['Search', 'Assigned', 'Started', 'Done'];
    final current = _currentStepIndex;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD7A8)),
      ),
      child: Row(
        children: List.generate(labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            final stepBefore = i ~/ 2;
            return Expanded(
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: stepBefore < current
                      ? const Color(0xFFE8741A)
                      : const Color(0xFFFFD7A8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }
          final step = i ~/ 2;
          final isDone = step <= current;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 22,
                width: 22,
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFFE8741A)
                      : const Color(0xFFFFE1BD),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDone
                        ? const Color(0xFFE8741A)
                        : const Color(0xFFFFD7A8),
                    width: 1.5,
                  ),
                ),
                child: isDone
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 5),
              Text(
                labels[step],
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isDone ? FontWeight.w700 : FontWeight.normal,
                  color: isDone ? const Color(0xFFE8741A) : Colors.black38,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _bookingSummaryCard() {
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
            'Booking Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4A2508),
            ),
          ),
          const SizedBox(height: 16),
          _summaryRow(Icons.my_location, const Color(0xFF4CAF50), 'Pickup',
              widget.pickup.isEmpty ? 'Not specified' : widget.pickup),
          _divider(),
          _summaryRow(Icons.location_on, const Color(0xFFE8741A), 'Drop',
              widget.drop.isEmpty ? 'Not specified' : widget.drop),
          _divider(),
          _summaryRow(Icons.directions_car_filled, const Color(0xFF8A3F08),
              'Cab Type', widget.cabName),
          _divider(),
          _summaryRow(Icons.currency_rupee, const Color(0xFFE8741A), 'Fare',
              widget.price),
          _divider(),
          _summaryRow(
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
      case 'upi':  return 'UPI';
      case 'card': return 'Card';
      default:     return 'Cash';
    }
  }

  Widget _summaryRow(IconData icon, Color color, String label, String value) {
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
                  style: const TextStyle(fontSize: 11, color: Colors.black45)),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: _cardBgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _cardBorderColor),
      ),
      child: Column(
        children: [
          _statusIcon(),
          const SizedBox(height: 16),
          Text(
            _statusTitle(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _statusTextColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _statusSubtitle(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          if (_isError) ...[
            const SizedBox(height: 14),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE8741A)),
              onPressed: () {
                setState(() => _bookingState = _BookingState.saving);
                // If booking was already saved, just restart the stream
                if (_bookingId != null) {
                  setState(() => _bookingState = _BookingState.searching);
                  _startWatching(_bookingId!);
                } else {
                  _saveBooking();
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusIcon() {
    switch (_bookingState) {
      case _BookingState.saving:
      case _BookingState.searching:
        return const SizedBox(
          height: 48,
          width: 48,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE8741A)),
            strokeWidth: 4,
            backgroundColor: Color(0xFFFFD7A8),
          ),
        );
      case _BookingState.assigned:
        return _iconCircle(Icons.person_pin_circle, Colors.green.shade600);
      case _BookingState.started:
        return _iconCircle(Icons.directions_car, Colors.blue.shade600);
      case _BookingState.completed:
        return _iconCircle(Icons.check_circle, Colors.green.shade600);
      case _BookingState.error:
        return _iconCircle(Icons.wifi_off, Colors.red.shade400);
    }
  }

  Widget _iconCircle(IconData icon, Color color) {
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 26),
    );
  }

  String _statusTitle() {
    switch (_bookingState) {
      case _BookingState.saving:    return 'Saving your booking...';
      case _BookingState.searching: return 'Searching for nearby driver...';
      case _BookingState.assigned:  return 'Driver Assigned!';
      case _BookingState.started:   return 'Ride Started';
      case _BookingState.completed: return 'Ride Completed!';
      case _BookingState.error:     return 'Something went wrong';
    }
  }

  String _statusSubtitle() {
    switch (_bookingState) {
      case _BookingState.saving:
        return 'Connecting to BrijRath servers.';
      case _BookingState.searching:
        return 'Waiting for a driver to accept your booking...';
      case _BookingState.assigned:
        return '$_driverName is heading to your pickup point.';
      case _BookingState.started:
        return 'Sit back and enjoy your BrijRath ride!';
      case _BookingState.completed:
        return 'Thank you for riding with BrijRath. Have a great day!';
      case _BookingState.error:
        return 'Check your connection and tap Retry.';
    }
  }

  Widget _driverCard() {
    // Chip label + colour change based on ride phase
    final String etaLabel;
    final Color etaColor;
    switch (_bookingState) {
      case _BookingState.assigned:
        etaLabel = 'On the way';
        etaColor = const Color(0xFFE8741A);
        break;
      case _BookingState.started:
        etaLabel = 'Ride started';
        etaColor = Colors.blue.shade600;
        break;
      case _BookingState.completed:
        etaLabel = 'Trip done';
        etaColor = Colors.green.shade600;
        break;
      default:
        etaLabel = 'Assigned';
        etaColor = const Color(0xFFE8741A);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFD7A8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + ETA chip
          Row(
            children: [
              const Icon(Icons.person_pin_circle,
                  color: Color(0xFFE8741A), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Your Driver',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF4A2508),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: etaColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time,
                        color: Colors.white, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      etaLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Avatar + real driver name from Supabase
          Row(
            children: [
              Container(
                height: 58,
                width: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE1BD),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color(0xFFE8741A), width: 2),
                ),
                child: const Icon(Icons.person,
                    color: Color(0xFFE8741A), size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _driverName, // real value from Supabase
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4A2508),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _vehicleName.isEmpty ? '—' : _vehicleName,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(color: Color(0xFFFFE8C8), thickness: 1),
          const SizedBox(height: 12),

          // Number plate
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7EA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFD7A8)),
                ),
                child: const Text(
                  'UP85 AB 1234',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF4A2508),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.directions_car,
                  color: Color(0xFFE8741A), size: 18),
              const SizedBox(width: 4),
              const Text(
                'White • Swift Dzire',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),

          // Track Driver button — hidden once completed
          if (!_isCompleted) ...[
            const SizedBox(height: 14),
            const Divider(color: Color(0xFFFFE8C8), thickness: 1),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.gps_fixed, size: 18),
                label: const Text(
                  'Track Driver',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8741A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriverTrackingScreen(
                        bookingId: _bookingId ?? '',
                        pickup: widget.pickup,
                        drop: widget.drop,
                        currentStatus: _statusTitle(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionButtons() {
    return Column(
      children: [
        if (!_isCompleted) ...[
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.cancel_outlined, size: 20),
              label: const Text(
                'Cancel Booking',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE8741A),
                side: const BorderSide(color: Color(0xFFE8741A), width: 2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _cancelBooking,
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.home_rounded, size: 20),
            label: const Text(
              'Back to Home',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8A3F08),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _backToHome,
          ),
        ),
      ],
    );
  }
}
