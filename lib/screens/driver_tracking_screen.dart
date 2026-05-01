import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/booking_service.dart';

class DriverTrackingScreen extends StatefulWidget {
  final String bookingId;
  final String pickup;
  final String drop;
  final String currentStatus;

  const DriverTrackingScreen({
    super.key,
    required this.bookingId,
    required this.pickup,
    required this.drop,
    required this.currentStatus,
  });

  @override
  State<DriverTrackingScreen> createState() => _DriverTrackingScreenState();
}

class _DriverTrackingScreenState extends State<DriverTrackingScreen> {
  static const LatLng _pickupLatLng = LatLng(27.4924, 77.6737);
  static const LatLng _dropLatLng   = LatLng(27.5706, 77.7006);
  static const LatLng _driverStart  = LatLng(27.5000, 77.6800);

  LatLng _driverPos = _driverStart;
  String _liveStatus = '';
  bool _mapReady = false;

  StreamSubscription<Map<String, dynamic>?>? _sub;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _liveStatus = widget.currentStatus;
    if (widget.bookingId.isNotEmpty) {
      _sub = BookingService().watchBooking(widget.bookingId).listen((row) {
        if (row == null || !mounted) return;
        final lat = (row['driver_lat'] as num?)?.toDouble();
        final lng = (row['driver_lng'] as num?)?.toDouble();
        final status = row['status'] as String?;
        setState(() {
          if (lat != null && lng != null) {
            _driverPos = LatLng(lat, lng);
            if (_mapReady) {
              _mapController.move(_driverPos, 14.0);
            }
          }
          if (status != null) _liveStatus = _statusLabel(status);
        });
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'assigned':  return 'Driver Assigned — On the way';
      case 'started':   return 'Ride in Progress';
      case 'completed': return 'Ride Completed';
      default:          return 'Searching for driver...';
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
          'Track Your Driver',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: Column(
        children: [
          // ── Real OSM map ──────────────────────────────────────────────────────
          SizedBox(
            height: 280,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _driverStart,
                  initialZoom: 13.5,
                  onMapReady: () => setState(() => _mapReady = true),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.brijrath',
                  ),
                  // Route: pickup → driver → drop
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [_pickupLatLng, _driverPos, _dropLatLng],
                        color: const Color(0xFFE8741A),
                        strokeWidth: 4,
                      ),
                    ],
                  ),
                  // Pickup, drop and driver markers
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _pickupLatLng,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.green,
                          size: 36,
                        ),
                      ),
                      Marker(
                        point: _dropLatLng,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_on,
                          color: Color(0xFFE8741A),
                          size: 36,
                        ),
                      ),
                      Marker(
                        point: _driverPos,
                        width: 44,
                        height: 44,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF8A3F08),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.brown.withOpacity(0.45),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.directions_car,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // OSM attribution (required by usage policy)
                  SimpleAttributionWidget(
                    source: const Text('OpenStreetMap contributors'),
                    backgroundColor: Colors.white70,
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom info panel ─────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                children: [
                  _routeInfoCard(),
                  const SizedBox(height: 10),
                  _driverInfoCard(),
                  const SizedBox(height: 10),
                  _statusBanner(),
                  const SizedBox(height: 14),
                  _actionButtons(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Info panels ───────────────────────────────────────────────────────────────

  Widget _routeInfoCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD7A8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _routePoint(
              Icons.my_location,
              Colors.green.shade600,
              'Pickup',
              widget.pickup.isEmpty ? 'Not specified' : widget.pickup,
            ),
          ),
          Container(
            height: 36,
            width: 1,
            color: const Color(0xFFFFD7A8),
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          Expanded(
            child: _routePoint(
              Icons.location_on,
              const Color(0xFFE8741A),
              'Drop',
              widget.drop.isEmpty ? 'Not specified' : widget.drop,
            ),
          ),
        ],
      ),
    );
  }

  Widget _routePoint(
      IconData icon, Color color, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 10, color: Colors.black45)),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4A2508),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _driverInfoCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      child: Row(
        children: [
          // Avatar
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE1BD),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE8741A), width: 2),
            ),
            child: const Icon(Icons.person, color: Color(0xFFE8741A), size: 28),
          ),
          const SizedBox(width: 14),

          // Name + vehicle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ramesh Sharma',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4A2508),
                  ),
                ),
                const SizedBox(height: 2),
                const Text('Swift Dzire  •  White',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7EA),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFFD7A8)),
                  ),
                  child: const Text(
                    'UP85 AB 1234',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: Color(0xFF4A2508),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Live indicator
          Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      height: 7,
                      width: 7,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text('Tracking',
                  style: TextStyle(fontSize: 10, color: Colors.black45)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0DC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD7A8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.navigation_rounded,
              color: Color(0xFFE8741A), size: 17),
          const SizedBox(width: 8),
          Text(
            _liveStatus.isEmpty ? widget.currentStatus : _liveStatus,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A2508),
            ),
          ),
        ],
      ),
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────────────

  Widget _actionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.phone_rounded, size: 20),
            label: const Text(
              'Call Driver',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE8741A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Calling Ramesh Sharma...',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: const Color(0xFF8A3F08),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
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
            onPressed: () =>
                Navigator.popUntil(context, (route) => route.isFirst),
          ),
        ),
      ],
    );
  }
}
