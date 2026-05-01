import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'fleet_service.dart';

class BookingService {
  final _client = Supabase.instance.client;

  // Inserts a new booking and returns the generated UUID
  Future<String> saveBooking({
    required String pickup,
    required String drop,
    required String cabType,
    required String price,
    String paymentMethod = 'cash',
  }) async {
    try {
      final response = await _client
          .from('bookings')
          .insert({
            'pickup':          pickup,
            'drop_location':   drop,
            'cab_type':        cabType,
            'price':           price,
            'status':          'searching',
            'created_at':      DateTime.now().toIso8601String(),
            'pickup_lat':      27.4924,
            'pickup_lng':      77.6737,
            'payment_method':  paymentMethod,
            'payment_status':  'pending',
            'paid_amount':     0,
          })
          .select('id')
          .single();

      final id = response['id'] as String;

      // Non-crashing auto-assignment — booking stays valid even if no driver is available
      try {
        await FleetService().autoAssignRide(bookingId: id);
        debugPrint('[BookingService] autoAssign success for $id');
      } catch (e) {
        debugPrint('[BookingService] autoAssign failed (booking still valid): $e');
      }

      return id;
    } on PostgrestException catch (e, st) {
      debugPrint('─── BOOKING ERROR [PostgrestException] ───────────────');
      debugPrint('  message : ${e.message}');
      debugPrint('  code    : ${e.code}');
      debugPrint('  details : ${e.details}');
      debugPrint('  hint    : ${e.hint}');
      debugPrint('  stack   : $st');
      debugPrint('──────────────────────────────────────────────────────');
      rethrow;
    } catch (e, st) {
      debugPrint('─── BOOKING ERROR [${e.runtimeType}] ─────────────────');
      debugPrint('  error : $e');
      debugPrint('  stack : $st');
      debugPrint('──────────────────────────────────────────────────────');
      rethrow;
    }
  }

  // Updates the status column for a specific booking
  Future<void> updateBookingStatus(String bookingId, String status) async {
    await _client
        .from('bookings')
        .update({'status': status})
        .eq('id', bookingId);
  }

  // Marks a ride complete and records the payment in one atomic update
  Future<void> completeRideWithPayment(
      String bookingId, int paidAmount) async {
    await _client.from('bookings').update({
      'status':         'completed',
      'payment_status': 'paid',
      'paid_amount':    paidAmount,
    }).eq('id', bookingId);
  }

  // Fetch every booking (all statuses), newest first.
  // Used by MyRidesScreen — filtered on the client side once auth is added.
  Future<List<Map<String, dynamic>>> fetchAllRides() async {
    final response = await _client
        .from('bookings')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // Fetch all bookings waiting for a driver
  Future<List<Map<String, dynamic>>> fetchSearchingBookings() async {
    try {
      final response = await _client
          .from('bookings')
          .select()
          .eq('status', 'searching')
          .order('created_at', ascending: false);
      debugPrint('[BookingService] fetchSearching: ${response.length} rows');
      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('[BookingService] fetchSearching FAILED');
      debugPrint('  message : ${e.message}');
      debugPrint('  code    : ${e.code}');
      debugPrint('  details : ${e.details}');
      debugPrint('  hint    : ${e.hint}');
      rethrow;
    }
  }

  // Auto-assign the first available online driver to a booking.
  // If no driver is online, the booking stays 'searching' — no error is thrown.
  Future<void> assignDriverToBooking(String bookingId) async {
    // 1. Find one online driver
    final drivers = await _client
        .from('drivers')
        .select()
        .eq('is_online', true)
        .limit(1);

    if (drivers.isEmpty) return; // nobody online yet — stay 'searching'

    final driver = drivers.first as Map<String, dynamic>;

    // 2. Update the booking row with driver info + flip status to 'assigned'
    await _client.from('bookings').update({
      'driver_id':   driver['id'],
      'driver_name': driver['name'],
      'vehicle':     driver['vehicle'],
      'status':      'assigned',
    }).eq('id', bookingId);
  }

  // Fetch the driver's current active ride (assigned or started).
  // Returns null when there is no active ride.
  Future<Map<String, dynamic>?> fetchActiveRide(String driverName) async {
    final response = await _client
        .from('bookings')
        .select()
        .or('status.eq.assigned,status.eq.started')
        .eq('driver_name', driverName)
        .order('created_at', ascending: false)
        .limit(1);

    if (response.isEmpty) return null;
    return response.first as Map<String, dynamic>;
  }

  // Fetch all completed rides for a specific driver, newest first.
  Future<List<Map<String, dynamic>>> fetchCompletedRides(String driverName) async {
    final response = await _client
        .from('bookings')
        .select()
        .eq('status', 'completed')
        .eq('driver_name', driverName)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // Driver accepts a ride — sets status + driver details.
  // Pass driverId to also set assigned_driver_id so the realtime stream picks
  // it up immediately (the stream filters on assigned_driver_id, not driver_name).
  Future<void> acceptRide(String bookingId, {String? driverId}) async {
    await _client.from('bookings').update({
      'status':      'assigned',
      'driver_name': 'Ramesh Sharma',
      'vehicle':     'Swift Dzire',
      if (driverId != null) 'assigned_driver_id': driverId,
    }).eq('id', bookingId);
  }

  // Updates the driver's simulated GPS position on the booking row.
  // Requires driver_lat and driver_lng columns in the bookings table.
  Future<void> updateDriverLocation(
      String bookingId, double lat, double lng) async {
    await _client.from('bookings').update({
      'driver_lat': lat,
      'driver_lng': lng,
    }).eq('id', bookingId);
  }

  // Real-time stream for a single booking row.
  // Emits the full row map whenever the row changes in Supabase.
  // Requires Realtime enabled on the bookings table in Supabase Dashboard.
  Stream<Map<String, dynamic>?> watchBooking(String bookingId) {
    return _client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('id', bookingId)
        .map((rows) => rows.isNotEmpty ? rows.first : null);
  }

  // ── New-model queries (use drivers.id instead of driver_name string) ──────────

  // Active ride for a driver identified by their drivers-table UUID.
  // Use this once a driver has a proper row in the drivers table.
  Future<Map<String, dynamic>?> fetchActiveRideByDriverId(
      String driverId) async {
    try {
      final response = await _client
          .from('bookings')
          .select()
          .or('status.eq.assigned,status.eq.started')
          .eq('assigned_driver_id', driverId)
          .order('created_at', ascending: false)
          .limit(1);
      debugPrint('[BookingService] fetchActiveById($driverId): '
          '${response.isEmpty ? "none" : response.first['id']}');
      if (response.isEmpty) return null;
      return response.first as Map<String, dynamic>;
    } on PostgrestException catch (e) {
      debugPrint('[BookingService] fetchActiveById FAILED');
      debugPrint('  message : ${e.message}');
      debugPrint('  code    : ${e.code}');
      debugPrint('  details : ${e.details}');
      debugPrint('  hint    : ${e.hint}');
      rethrow;
    }
  }

  // Completed rides for a driver identified by their drivers-table UUID.
  Future<List<Map<String, dynamic>>> fetchCompletedRidesByDriverId(
      String driverId) async {
    try {
      final response = await _client
          .from('bookings')
          .select()
          .eq('status', 'completed')
          .eq('assigned_driver_id', driverId)
          .order('created_at', ascending: false);
      debugPrint('[BookingService] fetchCompletedById($driverId): '
          '${response.length} rows');
      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('[BookingService] fetchCompletedById FAILED');
      debugPrint('  message : ${e.message}');
      debugPrint('  code    : ${e.code}');
      debugPrint('  details : ${e.details}');
      debugPrint('  hint    : ${e.hint}');
      rethrow;
    }
  }
}
