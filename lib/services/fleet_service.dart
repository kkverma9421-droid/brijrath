import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// FleetService owns all operations that go beyond a single booking:
///
///  • Driver CRUD — admin creates and manages their driver network
///  • Admin management — super_admin controls fleet partners
///  • Ride assignment — manual or automatic, with commission splitting
///  • Earnings queries — per-driver and per-admin summaries
///
/// The existing BookingService is NOT modified; this service extends the
/// model without touching the customer-facing booking flow.
class FleetService {
  final _client = Supabase.instance.client;

  // ── Driver management ─────────────────────────────────────────────────────────

  /// All drivers registered under [adminId], sorted by priority (highest first).
  Future<List<Map<String, dynamic>>> fetchDriversByAdmin(
      String adminId) async {
    final rows = await _client
        .from('drivers')
        .select()
        .eq('admin_id', adminId)
        .order('priority_score', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Every driver on the platform — super_admin view.
  /// Joins the owning admin's full_name for display.
  Future<List<Map<String, dynamic>>> fetchAllDrivers() async {
    final rows = await _client
        .from('drivers')
        .select('*, admin:profiles!admin_id(full_name, email)')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Fetch a single driver row by its UUID.
  Future<Map<String, dynamic>?> fetchDriver(String driverId) async {
    return await _client
        .from('drivers')
        .select()
        .eq('id', driverId)
        .maybeSingle();
  }

  /// Create a new driver record under [adminId].
  /// Returns the new driver's UUID.
  Future<String> createDriver({
    required String adminId,
    required String name,
    String? phone,
    String? vehicle,
    String? vehicleNumber,
    String? profileId,           // link to auth user if driver has an account
    double commissionPercent = 80.0,
  }) async {
    try {
      final row = await _client
          .from('drivers')
          .insert({
            'admin_id':           adminId,
            'profile_id':         profileId,
            'name':               name,
            'phone':              phone,
            'vehicle':            vehicle,
            'vehicle_number':     vehicleNumber,
            'commission_percent': commissionPercent,
            'is_online':          false,
            'is_active':          true,
            'priority_score':     0,
          })
          .select('id')
          .single();
      return row['id'] as String;
    } on PostgrestException catch (e, st) {
      _logError('createDriver', e, st);
      rethrow;
    }
  }

  /// Overwrite arbitrary fields on a driver row (admin / super_admin use).
  Future<void> updateDriver(
      String driverId, Map<String, dynamic> fields) async {
    try {
      await _client.from('drivers').update(fields).eq('id', driverId);
    } on PostgrestException catch (e, st) {
      _logError('updateDriver', e, st);
      rethrow;
    }
  }

  /// Switch a driver's online / offline status.
  Future<void> toggleDriverOnline(String driverId,
      {required bool isOnline}) async {
    await _client
        .from('drivers')
        .update({'is_online': isOnline})
        .eq('id', driverId);
  }

  /// Soft-delete (deactivate) or re-activate a driver.
  Future<void> toggleDriverActive(String driverId,
      {required bool isActive}) async {
    await _client
        .from('drivers')
        .update({'is_active': isActive})
        .eq('id', driverId);
  }

  /// Set the booking priority score.
  /// Higher score → the driver is offered rides before lower-score peers.
  Future<void> setDriverPriority(String driverId, int score) async {
    await _client
        .from('drivers')
        .update({'priority_score': score})
        .eq('id', driverId);
  }

  /// Set the % of each fare the driver keeps.
  Future<void> setDriverCommission(String driverId, double percent) async {
    await _client
        .from('drivers')
        .update({'commission_percent': percent})
        .eq('id', driverId);
  }

  // ── Admin / Fleet-partner management  (super_admin only) ─────────────────────

  /// All profiles with role = 'admin', newest first.
  Future<List<Map<String, dynamic>>> fetchAllAdmins() async {
    final rows = await _client
        .from('profiles')
        .select()
        .eq('role', 'admin')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Activate or deactivate a fleet partner account.
  Future<void> toggleAdminActive(String adminProfileId,
      {required bool isActive}) async {
    await _client
        .from('profiles')
        .update({'is_active': isActive})
        .eq('id', adminProfileId);
  }

  /// Set the % of each fare the admin earns on their driver network's rides.
  Future<void> setAdminCommission(
      String adminProfileId, double percent) async {
    await _client
        .from('profiles')
        .update({'commission_percent': percent})
        .eq('id', adminProfileId);
  }

  // ── Ride assignment ───────────────────────────────────────────────────────────

  /// Manually assign a booking to a specific driver.
  ///
  /// Looks up the driver's admin_id and both commission rates, then writes:
  ///  • status = 'assigned'
  ///  • assigned_driver_id / assigned_admin_id / assignment_mode
  ///  • driver_earning / admin_commission / platform_commission
  Future<void> assignRide({
    required String bookingId,
    required String driverId,
    String assignmentMode = 'manual',
  }) async {
    try {
      // ── 1. Load driver details ──────────────────────────────────────────────
      final driverRow = await _client
          .from('drivers')
          .select('admin_id, commission_percent, name, vehicle, vehicle_number')
          .eq('id', driverId)
          .single();

      final adminId          = driverRow['admin_id']          as String?;
      final driverCommPct    = (driverRow['commission_percent'] as num).toDouble();
      final driverName       = (driverRow['name']             as String?) ?? '';
      final vehicle          = (driverRow['vehicle']          as String?) ?? '';

      // ── 2. Load booking fare ────────────────────────────────────────────────
      final bookingRow = await _client
          .from('bookings')
          .select('paid_amount, price')
          .eq('id', bookingId)
          .single();

      // Use paid_amount if already set (ride already completed); else parse price.
      final rawPaid  = bookingRow['paid_amount'] as num?;
      final priceStr = (bookingRow['price'] as String?) ?? '';
      final fare     = (rawPaid != null && rawPaid > 0)
          ? rawPaid.toDouble()
          : double.tryParse(priceStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;

      // ── 3. Load admin commission rate ───────────────────────────────────────
      double adminCommPct = 0;
      if (adminId != null) {
        final adminRow = await _client
            .from('profiles')
            .select('commission_percent')
            .eq('id', adminId)
            .maybeSingle();
        adminCommPct =
            (adminRow?['commission_percent'] as num?)?.toDouble() ?? 0;
      }

      // ── 4. Calculate split ──────────────────────────────────────────────────
      // Driver earns driverCommPct% of fare.
      // Admin earns adminCommPct% of fare.
      // Platform keeps the remainder.
      final driverEarning      = double.parse((fare * driverCommPct / 100).toStringAsFixed(2));
      final adminCommAmount    = double.parse((fare * adminCommPct  / 100).toStringAsFixed(2));
      final platformCommAmount = double.parse((fare - driverEarning - adminCommAmount).toStringAsFixed(2));

      // ── 5. Write back to bookings ───────────────────────────────────────────
      await _client.from('bookings').update({
        'status':              'assigned',
        'assigned_driver_id':  driverId,
        'assigned_admin_id':   adminId,
        'assignment_mode':     assignmentMode,
        'driver_name':         driverName,   // keep legacy field in sync
        'vehicle':             vehicle,
        'driver_earning':      driverEarning,
        'admin_commission':    adminCommAmount,
        'platform_commission': platformCommAmount,
      }).eq('id', bookingId);
    } on PostgrestException catch (e, st) {
      _logError('assignRide', e, st);
      rethrow;
    }
  }

  /// Automatically assign the best nearby driver to a booking.
  ///
  /// Selection rules (in order):
  ///  1. Driver must be is_online=true AND is_active=true
  ///  2. Driver must have lat/lng recorded in the drivers table
  ///  3. Distance to booking pickup must be ≤ 10 km (Haversine)
  ///  4. Score = priority_score + nearby_bonus
  ///     nearby_bonus = (10 − distance_km) / 10 × 10  →  max +10 at 0 km
  ///  5. Highest scorer wins; ties broken by whichever comes first in the list
  ///
  /// If [adminId] is provided only that admin's drivers are considered.
  /// If the booking has no pickup coordinates, falls back to priority_score only
  /// (no distance filtering).
  ///
  /// Manual driver acceptance (acceptRide) is NOT affected by this method.
  Future<void> autoAssignRide({
    required String bookingId,
    String? adminId,
  }) async {
    try {
      // ── 1. Fetch booking pickup location ───────────────────────────────────
      final bookingRow = await _client
          .from('bookings')
          .select('pickup_lat, pickup_lng')
          .eq('id', bookingId)
          .single();

      final pickupLat = (bookingRow['pickup_lat'] as num?)?.toDouble();
      final pickupLng = (bookingRow['pickup_lng'] as num?)?.toDouble();

      debugPrint('[FleetService] autoAssign ▶ booking $bookingId  '
          'pickup=(${pickupLat?.toStringAsFixed(4)}, '
          '${pickupLng?.toStringAsFixed(4)})');

      // ── 2. Fetch all online + active drivers with their GPS ─────────────────
      var query = _client
          .from('drivers')
          .select('id, name, vehicle, priority_score, lat, lng')
          .eq('is_online', true)
          .eq('is_active', true);

      if (adminId != null) query = query.eq('admin_id', adminId);

      final allDrivers = List<Map<String, dynamic>>.from(await query);
      debugPrint('[FleetService] autoAssign – online+active drivers: '
          '${allDrivers.length}');

      if (allDrivers.isEmpty) {
        debugPrint('[FleetService] autoAssign – no online/active drivers; '
            'booking stays searching');
        return;
      }

      // ── 3. Score every driver and pick the best one ─────────────────────────
      const double maxRadiusKm = 10.0;
      Map<String, dynamic>? bestDriver;
      double bestScore = double.negativeInfinity;

      for (final driver in allDrivers) {
        final name     = (driver['name'] as String?) ?? 'Unknown';
        final priority = (driver['priority_score'] as num?)?.toDouble() ?? 0.0;
        final driverLat = (driver['lat'] as num?)?.toDouble();
        final driverLng = (driver['lng'] as num?)?.toDouble();

        if (pickupLat != null && pickupLng != null) {
          // Booking has coordinates → apply distance filter
          if (driverLat == null || driverLng == null) {
            debugPrint('[FleetService] autoAssign   skip "$name" – '
                'no GPS location on file');
            continue;
          }

          final dist = _haversineKm(driverLat, driverLng, pickupLat, pickupLng);
          debugPrint('[FleetService] autoAssign   "$name" '
              '– dist=${dist.toStringAsFixed(2)} km  '
              'priority=${priority.toStringAsFixed(0)}');

          if (dist > maxRadiusKm) {
            debugPrint('[FleetService] autoAssign   skip "$name" – '
                '${dist.toStringAsFixed(2)} km > ${maxRadiusKm.toStringAsFixed(0)} km');
            continue;
          }

          // Nearby bonus: 0 km → +10 pts, 10 km → 0 pts (linear)
          final nearbyBonus = (maxRadiusKm - dist) / maxRadiusKm * 10.0;
          final score = priority + nearbyBonus;
          debugPrint('[FleetService] autoAssign   "$name" score='
              '${score.toStringAsFixed(2)} '
              '(priority=$priority + nearby=${nearbyBonus.toStringAsFixed(2)})');

          if (score > bestScore) {
            bestScore  = score;
            bestDriver = driver;
          }
        } else {
          // No pickup coordinates → rank by priority only (no distance filter)
          if (priority > bestScore) {
            bestScore  = priority;
            bestDriver = driver;
          }
        }
      }

      if (bestDriver == null) {
        debugPrint('[FleetService] autoAssign – FAILED: no driver within '
            '${maxRadiusKm.toStringAsFixed(0)} km; booking stays searching');
        return;
      }

      final selectedName = (bestDriver['name'] as String?) ?? '';
      debugPrint('[FleetService] autoAssign – selected: "$selectedName"  '
          'score=${bestScore.toStringAsFixed(2)}');

      await assignRide(
        bookingId:      bookingId,
        driverId:       bestDriver['id'] as String,
        assignmentMode: 'auto',
      );

      debugPrint('[FleetService] autoAssign – SUCCESS  '
          'booking=$bookingId → driver="$selectedName"');
    } on PostgrestException catch (e, st) {
      _logError('autoAssignRide', e, st);
      rethrow;
    }
  }

  // ── Booking queries ───────────────────────────────────────────────────────────

  /// All bookings handled by a specific admin's driver network.
  Future<List<Map<String, dynamic>>> fetchBookingsByAdmin(
      String adminId) async {
    final rows = await _client
        .from('bookings')
        .select()
        .eq('assigned_admin_id', adminId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Every booking on the platform — super_admin view.
  Future<List<Map<String, dynamic>>> fetchAllBookings() async {
    final rows = await _client
        .from('bookings')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  // ── Earnings queries ──────────────────────────────────────────────────────────

  /// Total amount a driver has earned across all paid rides.
  Future<double> fetchDriverTotalEarnings(String driverId) async {
    final rows = await _client
        .from('bookings')
        .select('driver_earning')
        .eq('assigned_driver_id', driverId)
        .eq('payment_status', 'paid');

    return List<Map<String, dynamic>>.from(rows).fold<double>(
      0,
      (sum, r) => sum + ((r['driver_earning'] as num?)?.toDouble() ?? 0),
    );
  }

  /// Total commission a fleet partner has earned across all paid rides.
  Future<double> fetchAdminTotalCommission(String adminId) async {
    final rows = await _client
        .from('bookings')
        .select('admin_commission')
        .eq('assigned_admin_id', adminId)
        .eq('payment_status', 'paid');

    return List<Map<String, dynamic>>.from(rows).fold<double>(
      0,
      (sum, r) => sum + ((r['admin_commission'] as num?)?.toDouble() ?? 0),
    );
  }

  /// Platform-level revenue summary — super_admin use.
  /// Returns { total_fare, platform_commission, admin_commission, driver_earning }
  Future<Map<String, double>> fetchPlatformEarningsSummary() async {
    final rows = await _client
        .from('bookings')
        .select('paid_amount, platform_commission, admin_commission, driver_earning')
        .eq('payment_status', 'paid');

    final list = List<Map<String, dynamic>>.from(rows);
    double totalFare     = 0;
    double platformComm  = 0;
    double adminComm     = 0;
    double driverEarning = 0;

    for (final r in list) {
      totalFare     += (r['paid_amount']        as num?)?.toDouble() ?? 0;
      platformComm  += (r['platform_commission'] as num?)?.toDouble() ?? 0;
      adminComm     += (r['admin_commission']    as num?)?.toDouble() ?? 0;
      driverEarning += (r['driver_earning']      as num?)?.toDouble() ?? 0;
    }

    return {
      'total_fare':          totalFare,
      'platform_commission': platformComm,
      'admin_commission':    adminComm,
      'driver_earning':      driverEarning,
    };
  }

  // ── Geometry helpers ──────────────────────────────────────────────────────────

  /// Haversine great-circle distance in kilometres.
  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const earthR = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return earthR * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ── Error logging ─────────────────────────────────────────────────────────────

  void _logError(String method, PostgrestException e, StackTrace st) {
    debugPrint('─── FLEET ERROR [$method] ────────────────────────────');
    debugPrint('  message : ${e.message}');
    debugPrint('  code    : ${e.code}');
    debugPrint('  details : ${e.details}');
    debugPrint('  hint    : ${e.hint}');
    debugPrint('  stack   : $st');
    debugPrint('──────────────────────────────────────────────────────');
  }
}
