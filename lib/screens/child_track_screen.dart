import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';

class ChildTrackScreen extends StatefulWidget {
  const ChildTrackScreen({super.key});

  @override
  State<ChildTrackScreen> createState() => _ChildTrackScreenState();
}

class _ChildTrackScreenState extends State<ChildTrackScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _child;
  bool _isLoading = true;
  String _errorMsg = '';
  Timer? _timer;

  // Tracking data
  String _childName = '';
  String _tripName = '';
  bool _isTracking = false;
  double? _speed;
  String? _updatedAt;
  Map<String, dynamic>? _pickupStop;
  Map<String, dynamic>? _dropStop;
  List<LatLng> _stopsPoints = [];
  List<Map<String, dynamic>> _stopsRaw = [];

  // Map configuration
  String _mapProvider = 'leaflet';
  String _mapboxAccessToken = '';
  String _googleMapsApiKey = '';
  final MapController _mapController = MapController();

  // Bus Marker Smooth Animation
  LatLng? _oldBusPosition;
  LatLng? _targetBusPosition;
  LatLng? _animatedBusPosition;
  AnimationController? _animationController;
  Animation<double>? _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController!)
      ..addListener(() {
        if (_oldBusPosition != null && _targetBusPosition != null) {
          final t = _animation!.value;
          setState(() {
            _animatedBusPosition = LatLng(
              _oldBusPosition!.latitude + (_targetBusPosition!.latitude - _oldBusPosition!.latitude) * t,
              _oldBusPosition!.longitude + (_targetBusPosition!.longitude - _oldBusPosition!.longitude) * t,
            );
          });
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_child == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _child = args;
        _childName = _child!['name'] ?? 'Child';
        _fetchTracking(isFirstTime: true);
        _startTimer();
      } else {
        setState(() {
          _errorMsg = 'Invalid child arguments';
          _isLoading = false;
        });
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchTracking();
    });
  }

  Future<void> _fetchTracking({bool isFirstTime = false}) async {
    if (_child == null) return;
    final childId = _child!['id'] as int?;
    if (childId == null) return;

    try {
      final res = await ApiService.getChildTracking(childId);
      if (!mounted) return;

      if (res['success'] == true) {
        final List<LatLng> parsedStops = [];
        final rawStops = (res['stops'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        for (var s in rawStops) {
          final lat = (s['latitude'] as num?)?.toDouble();
          final lng = (s['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            parsedStops.add(LatLng(lat, lng));
          }
        }

        final busLat = (res['latitude'] as num?)?.toDouble();
        final busLng = (res['longitude'] as num?)?.toDouble();
        LatLng? newBusPos;
        if (busLat != null && busLng != null) {
          newBusPos = LatLng(busLat, busLng);
        }

        setState(() {
          _isLoading = false;
          _errorMsg = '';
          _tripName = res['trip_name'] ?? 'Transit Route';
          _isTracking = res['is_tracking'] ?? false;
          _speed = (res['speed'] as num?)?.toDouble();
          _updatedAt = res['updated_at'] as String?;
          _pickupStop = res['pickup_stop'] as Map<String, dynamic>?;
          _dropStop = res['drop_stop'] as Map<String, dynamic>?;
          _stopsPoints = parsedStops;
          _stopsRaw = rawStops;
          _mapProvider = res['map_provider'] ?? 'leaflet';
          _mapboxAccessToken = res['mapbox_access_token'] ?? '';
          _googleMapsApiKey = res['google_maps_api_key'] ?? '';
        });

        // Trigger smooth bus movement animation
        if (newBusPos != null) {
          if (_targetBusPosition == null) {
            // First time loading location, place marker directly
            setState(() {
              _targetBusPosition = newBusPos;
              _animatedBusPosition = newBusPos;
            });
            _centerMap(newBusPos);
          } else if (_targetBusPosition != newBusPos) {
            // Location changed, animate from previous animated position to new position
            _oldBusPosition = _animatedBusPosition ?? _targetBusPosition;
            _targetBusPosition = newBusPos;
            _animationController!.forward(from: 0.0);
          }
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMsg = res['message'] ?? 'Failed to load tracking updates.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = 'Error fetching live locations: $e';
        });
      }
    }
  }

  void _centerMap(LatLng center) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mapController.move(center, 15.0);
      }
    });
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 'Offline';
    try {
      final dateTime = DateTime.parse(timeStr);
      final hour = dateTime.hour > 12 ? dateTime.hour - 12 : (dateTime.hour == 0 ? 12 : dateTime.hour);
      final min = dateTime.minute < 10 ? '0${dateTime.minute}' : '${dateTime.minute}';
      final period = dateTime.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$min $period';
    } catch (_) {
      return 'Offline';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animationController?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine map URL template based on setting
    String tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    if (_mapProvider == 'mapbox' && _mapboxAccessToken.isNotEmpty) {
      tileUrl = 'https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/{z}/{x}/{y}?access_token=$_mapboxAccessToken';
    } else if (_mapProvider == 'google_maps') {
      tileUrl = 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
    }

    // Centering point setup
    LatLng initialCenter = const LatLng(19.18, 73.21);
    if (_animatedBusPosition != null) {
      initialCenter = _animatedBusPosition!;
    } else if (_stopsPoints.isNotEmpty) {
      initialCenter = _stopsPoints.first;
    }

    // Build map markers
    final List<Marker> markers = [];

    // 1. Add stops markers
    for (var s in _stopsRaw) {
      final lat = (s['latitude'] as num?)?.toDouble();
      final lng = (s['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final isPickup = _pickupStop != null && _pickupStop!['id'] == s['id'];
      final isDrop = _dropStop != null && _dropStop!['id'] == s['id'];

      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 50,
          height: 55,
          child: Column(
            children: [
              Icon(
                isPickup
                    ? Icons.location_on_rounded
                    : isDrop
                        ? Icons.location_on_rounded
                        : Icons.trip_origin_rounded,
                color: isPickup
                    ? Colors.green
                    : isDrop
                        ? Colors.red
                        : Colors.blue.shade400,
                size: isPickup || isDrop ? 28 : 16,
              ),
              if (isPickup || isDrop)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
                  ),
                  child: Text(
                    isPickup ? 'Pickup' : 'Dropoff',
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // 2. Add animated bus marker
    if (_animatedBusPosition != null && _isTracking) {
      markers.add(
        Marker(
          point: _animatedBusPosition!,
          width: 50,
          height: 50,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  spreadRadius: 2,
                )
              ],
            ),
            child: const Icon(
              Icons.directions_bus_rounded,
              color: Colors.amber,
              size: 32,
            ),
          ),
        ),
      );
    }

    // Create polyline segments
    final List<Polyline> polylines = [];
    if (_stopsPoints.isNotEmpty) {
      // General route stops sequence (blue)
      polylines.add(
        Polyline(
          points: _stopsPoints,
          color: Colors.blue.withOpacity(0.6),
          strokeWidth: 4.0,
        ),
      );
    }

    // Highlight path between current bus location and child's pickup/dropoff stop
    final targetStop = _pickupStop ?? _dropStop;
    if (_animatedBusPosition != null && targetStop != null && _isTracking) {
      final stopLat = (targetStop['latitude'] as num?)?.toDouble();
      final stopLng = (targetStop['longitude'] as num?)?.toDouble();
      if (stopLat != null && stopLng != null) {
        polylines.add(
          Polyline(
            points: [_animatedBusPosition!, LatLng(stopLat, stopLng)],
            color: Colors.amber.shade700,
            strokeWidth: 3.5,
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Track $_childName'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'View Details',
            onPressed: () {
              Navigator.pushNamed(
                context,
                '/child-detail',
                arguments: _child,
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMsg.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 64, color: theme.colorScheme.error),
                        const SizedBox(height: 16),
                        Text(
                          'Tracking Unavailable',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.error),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMsg,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                            });
                            _fetchTracking();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Top Dashboard Metrics View
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withOpacity(0.4),
                        border: Border(
                          bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Trip Name Card
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _tripName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _isTracking ? Colors.green : Colors.grey,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isTracking ? 'Active Service' : 'Offline',
                                      style: TextStyle(fontSize: 12, color: _isTracking ? Colors.green : Colors.grey),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Speed Card
                          Column(
                            children: [
                              const Text('SPEED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 4),
                              Text(
                                _isTracking && _speed != null ? '${(_speed! * 3.6).toStringAsFixed(1)} km/h' : '0.0 km/h',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(width: 24),
                          // Time Card
                          Column(
                            children: [
                              const Text('LAST UPDATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 4),
                              Text(
                                _isTracking ? _formatTime(_updatedAt) : 'Offline',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Map Section (65% Height)
                    Expanded(
                      flex: 65,
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: initialCenter,
                              initialZoom: 15.0,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: tileUrl,
                                userAgentPackageName: 'com.infoleena.fleetfind',
                              ),
                              PolylineLayer(polylines: polylines),
                              MarkerLayer(markers: markers),
                            ],
                          ),
                          // Floating Action Buttons to Center Map
                          if (_animatedBusPosition != null && _isTracking)
                            Positioned(
                              right: 16,
                              bottom: 16,
                              child: FloatingActionButton(
                                mini: true,
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                onPressed: () => _centerMap(_animatedBusPosition!),
                                child: const Icon(Icons.my_location_rounded),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Enrolled StopsManifest (35% Height)
                    Expanded(
                      flex: 35,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(top: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          itemCount: _stopsRaw.length,
                          itemBuilder: (context, index) {
                            final stop = _stopsRaw[index];
                            final isPickup = _pickupStop != null && _pickupStop!['id'] == stop['id'];
                            final isDrop = _dropStop != null && _dropStop!['id'] == stop['id'];
                            final scheduledTime = stop['time'] as String? ?? '--:--';

                            return Row(
                              children: [
                                // Timeline bullet
                                Column(
                                  children: [
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: isPickup
                                            ? Colors.green
                                            : isDrop
                                                ? Colors.red
                                                : Colors.blue.shade200,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                    ),
                                    if (index < _stopsRaw.length - 1)
                                      Container(
                                        width: 2,
                                        height: 35,
                                        color: Colors.grey.shade200,
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                // Stop Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stop['name'] ?? 'N/A',
                                        style: TextStyle(
                                          fontWeight: isPickup || isDrop ? FontWeight.bold : FontWeight.normal,
                                          fontSize: 14,
                                          color: isPickup || isDrop ? Colors.black87 : Colors.black54,
                                        ),
                                      ),
                                      if (isPickup || isDrop)
                                        Text(
                                          isPickup ? 'Your Pickup Stop' : 'Your Dropoff Stop',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isPickup ? Colors.green : Colors.red,
                                          ),
                                        ),
                                      const SizedBox(height: 12),
                                    ],
                                  ),
                                ),
                                // Scheduled Time
                                Text(
                                  scheduledTime,
                                  style: TextStyle(
                                    fontWeight: isPickup || isDrop ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 13,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
