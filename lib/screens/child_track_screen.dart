import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';

class ChildTrackScreen extends StatefulWidget {
  const ChildTrackScreen({super.key});

  @override
  State<ChildTrackScreen> createState() => _ChildTrackScreenState();
}

class _ChildTrackScreenState extends State<ChildTrackScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _child;
  bool _isAdminMode = false;
  int? _adminOrgId;
  int? _adminTripId;
  int? _adminRouteId;
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
  List<LatLng> _routedPath = [];
  List<LatLng> _routedBusToStopPath = [];
  bool _isFetchingRoute = false;
  double _busRotation = 0.0;
  int _nextStopIndex = -1;
  double? _estimatedDurationSeconds;
  double? _estimatedDistanceMeters;
  int? _currentTripId;

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
    if (_child == null && !_isAdminMode) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        if (args['is_admin_mode'] == true) {
          _isAdminMode = true;
          _adminOrgId = args['org_id'] as int?;
          _adminTripId = args['trip_id'] as int?;
          _adminRouteId = args['route_id'] as int?;
          _childName = args['route_name'] ?? 'Route';
          _fetchTracking(isFirstTime: true);
          _startTimer();
        } else {
          _child = args;
          _childName = _child!['name'] ?? 'Child';
          _fetchTracking(isFirstTime: true);
          _startTimer();
        }
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
    if (_child == null && !_isAdminMode) return;

    try {
      final Map<String, dynamic> res;
      if (_isAdminMode) {
        if (_adminOrgId == null || _adminTripId == null || _adminRouteId == null) return;
        res = await ApiService.getRouteTracking(_adminOrgId!, _adminTripId!, _adminRouteId!);
      } else {
        final childId = _child!['id'] as int?;
        if (childId == null) return;
        res = await ApiService.getChildTracking(childId);
      }
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

        final newTripId = res['trip_id'] as int?;
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

          if (_currentTripId != newTripId) {
            _currentTripId = newTripId;
            _nextStopIndex = -1;
            _routedPath = [];
            _routedBusToStopPath = [];
            _estimatedDurationSeconds = null;
            _estimatedDistanceMeters = null;
            _targetBusPosition = null;
            _animatedBusPosition = null;
            _oldBusPosition = null;
          }
        });

        // Update visited stops progress dynamically
        if (newBusPos != null && parsedStops.isNotEmpty) {
          if (_nextStopIndex == -1) {
            int closestIdx = 0;
            double minDst = double.maxFinite;
            for (int i = 0; i < parsedStops.length; i++) {
              final dst = _calculateDistance(newBusPos, parsedStops[i]);
              if (dst < minDst) {
                minDst = dst;
                closestIdx = i;
              }
            }

            // If close to this stop (within 600m), assume mid-route starting point
            if (minDst < 600) {
              _nextStopIndex = closestIdx;
            } else {
              // Otherwise, assume starting from depot before first stop
              _nextStopIndex = 0;
            }
          } else {
            // Arrived/passed the next expected stop in sequence
            if (_nextStopIndex < parsedStops.length) {
              final dst = _calculateDistance(newBusPos, parsedStops[_nextStopIndex]);
              if (dst < 250) {
                _nextStopIndex++;
              }
            }
          }
        }

        _fetchRoutes();

        // Trigger smooth bus movement animation
        if (newBusPos != null) {
          if (_targetBusPosition == null) {
            // First time loading location, place marker directly
            setState(() {
              _targetBusPosition = newBusPos;
              _animatedBusPosition = newBusPos;
              _busRotation = _determineInitialBearing(newBusPos!);
            });
            _centerMap(newBusPos);
          } else if (_targetBusPosition != newBusPos) {
            // Location changed, animate from previous animated position to new position
            final bearing = _calculateBearing(_targetBusPosition!, newBusPos);
            _oldBusPosition = _animatedBusPosition ?? _targetBusPosition;
            _targetBusPosition = newBusPos;
            setState(() {
              _busRotation = bearing;
            });
            _animationController!.forward(from: 0.0);
          }

          // Auto-adjust zoom level to show both the bus and the child's stop
          final targetStop = _pickupStop ?? _dropStop;
          if (targetStop != null) {
            final stopLat = (targetStop['latitude'] as num?)?.toDouble();
            final stopLng = (targetStop['longitude'] as num?)?.toDouble();
            if (stopLat != null && stopLng != null) {
              final pointsToFit = [newBusPos, LatLng(stopLat, stopLng)];
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _mapController.fitCamera(
                    CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(pointsToFit),
                      padding: const EdgeInsets.only(top: 80, bottom: 80, left: 60, right: 60),
                    ),
                  );
                }
              });
            }
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

  Future<void> _fetchRoutes() async {
    if (_isFetchingRoute) return;
    _isFetchingRoute = true;

    try {
      // 1. Fetch main route connecting all stops
      if (_stopsPoints.length >= 2) {
        final coordString = _stopsPoints.map((p) => '${p.longitude},${p.latitude}').join(';');
        final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/$coordString?overview=full&geometries=geojson');
        final response = await http.get(url).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final routes = data['routes'] as List?;
          if (routes != null && routes.isNotEmpty) {
            final geometry = routes[0]['geometry'] as Map<String, dynamic>?;
            final coords = geometry?['coordinates'] as List?;
            if (coords != null) {
              final List<LatLng> path = [];
              for (var c in coords) {
                final lng = (c[0] as num).toDouble();
                final lat = (c[1] as num).toDouble();
                path.add(LatLng(lat, lng));
              }
              setState(() {
                _routedPath = path;
              });
            }
          }
        }
      }

      // 2. Fetch highlight path from bus to target stop along the sequence of the route
      final targetStop = _pickupStop ?? _dropStop;
      if (_animatedBusPosition != null && targetStop != null && _isTracking) {
        final stopLat = (targetStop['latitude'] as num?)?.toDouble();
        final stopLng = (targetStop['longitude'] as num?)?.toDouble();
        if (stopLat != null && stopLng != null) {
          final busPos = _animatedBusPosition!;

          // Find the closest point in _stopsPoints to the bus position
          int closestStopIndex = 0;
          double minDistance = double.maxFinite;
          for (int i = 0; i < _stopsPoints.length; i++) {
            final p = _stopsPoints[i];
            final dist = math.pow(p.latitude - busPos.latitude, 2) +
                math.pow(p.longitude - busPos.longitude, 2);
            if (dist < minDistance) {
              minDistance = dist.toDouble();
              closestStopIndex = i;
            }
          }

          int targetStopIndex = -1;
          for (int i = 0; i < _stopsPoints.length; i++) {
            if ((_stopsPoints[i].latitude - stopLat).abs() < 0.0001 &&
                (_stopsPoints[i].longitude - stopLng).abs() < 0.0001) {
              targetStopIndex = i;
              break;
            }
          }

          final List<LatLng> pointsToRoute = [busPos];
          final startIndex = (_nextStopIndex >= 0) ? _nextStopIndex : closestStopIndex;

          if (targetStopIndex != -1 && startIndex <= targetStopIndex) {
            // Route from bus, through the next expected stop, up to target stop
            pointsToRoute.addAll(_stopsPoints.sublist(startIndex, targetStopIndex + 1));
          } else {
            // Fallback or bus has passed target stop
            pointsToRoute.add(LatLng(stopLat, stopLng));
          }

          try {
            final coordString = pointsToRoute.map((p) => '${p.longitude},${p.latitude}').join(';');
            final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/$coordString?overview=full&geometries=geojson');
            final response = await http.get(url).timeout(const Duration(seconds: 4));
            if (response.statusCode == 200) {
              final data = json.decode(response.body);
              final routes = data['routes'] as List?;
              if (routes != null && routes.isNotEmpty) {
                final duration = (routes[0]['duration'] as num?)?.toDouble();
                final distance = (routes[0]['distance'] as num?)?.toDouble();
                final geometry = routes[0]['geometry'] as Map<String, dynamic>?;
                final coords = geometry?['coordinates'] as List?;
                if (coords != null) {
                  final List<LatLng> path = [];
                  for (var c in coords) {
                    final lng = (c[0] as num).toDouble();
                    final lat = (c[1] as num).toDouble();
                    path.add(LatLng(lat, lng));
                  }
                  setState(() {
                    _routedBusToStopPath = path;
                    _estimatedDurationSeconds = duration;
                    _estimatedDistanceMeters = distance;
                  });
                }
              }
            } else {
              throw Exception('OSRM error');
            }
          } catch (_) {
            // Fallback: estimate based on straight-line distance
            double totalDist = 0.0;
            for (int i = 0; i < pointsToRoute.length - 1; i++) {
              totalDist += _calculateDistance(pointsToRoute[i], pointsToRoute[i + 1]);
            }
            // Average speed of 30 km/h is 8.33 m/s
            final duration = totalDist / 8.33;
            setState(() {
              _routedBusToStopPath = [];
              _estimatedDurationSeconds = duration;
              _estimatedDistanceMeters = totalDist;
            });
          }
        }
      }
    } catch (_) {
      // Fallback silently
    } finally {
      _isFetchingRoute = false;
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
      final dateTime = DateTime.parse(timeStr).toLocal();
      final hour = dateTime.hour > 12 ? dateTime.hour - 12 : (dateTime.hour == 0 ? 12 : dateTime.hour);
      final min = dateTime.minute < 10 ? '0${dateTime.minute}' : '${dateTime.minute}';
      final sec = dateTime.second < 10 ? '0${dateTime.second}' : '${dateTime.second}';
      final period = dateTime.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$min:$sec $period';
    } catch (_) {
      return 'Offline';
    }
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    const double earthRadius = 6371000; // in meters
    final double lat1 = p1.latitude * math.pi / 180;
    final double lat2 = p2.latitude * math.pi / 180;
    final double lon1 = p1.longitude * math.pi / 180;
    final double lon2 = p2.longitude * math.pi / 180;

    final double dLat = lat2 - lat1;
    final double dLon = lon2 - lon1;

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * math.pi / 180.0;
    final lon1 = start.longitude * math.pi / 180.0;
    final lat2 = end.latitude * math.pi / 180.0;
    final lon2 = end.longitude * math.pi / 180.0;

    final dLon = lon2 - lon1;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final radians = math.atan2(y, x);
    return radians;
  }

  double _determineInitialBearing(LatLng busPos) {
    if (_stopsPoints.isEmpty) return 0.0;

    int closestIndex = 0;
    double minDistance = double.maxFinite;
    for (int i = 0; i < _stopsPoints.length; i++) {
      final p = _stopsPoints[i];
      final dist = math.pow(p.latitude - busPos.latitude, 2) +
          math.pow(p.longitude - busPos.longitude, 2);
      if (dist < minDistance) {
        minDistance = dist.toDouble();
        closestIndex = i;
      }
    }

    if (closestIndex < _stopsPoints.length - 1) {
      return _calculateBearing(busPos, _stopsPoints[closestIndex + 1]);
    } else if (closestIndex > 0) {
      return _calculateBearing(_stopsPoints[closestIndex - 1], busPos);
    }

    return 0.0;
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).round();
    if (mins <= 0) return 'Arriving now';
    if (mins == 1) return '1 min';
    return '$mins mins';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
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
      final isSchool = s['is_school'] == true;

      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 50,
          height: 55,
          child: Column(
            children: [
              Icon(
                isSchool
                    ? Icons.school_rounded
                    : isPickup
                        ? Icons.location_on_rounded
                        : isDrop
                            ? Icons.location_on_rounded
                            : Icons.trip_origin_rounded,
                color: isSchool
                    ? Colors.purple
                    : isPickup
                        ? Colors.green
                        : isDrop
                            ? Colors.red
                            : Colors.blue.shade400,
                size: isSchool || isPickup || isDrop ? 28 : 16,
              ),
              if (isSchool || isPickup || isDrop)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
                  ),
                  child: Text(
                    isSchool
                        ? 'School'
                        : isPickup
                            ? 'Pickup'
                            : 'Dropoff',
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
            child: Transform.rotate(
              angle: _busRotation,
              child: const Icon(
                Icons.directions_bus_rounded,
                color: Colors.amber,
                size: 32,
              ),
            ),
          ),
        ),
      );
    }

    // Create polyline segments
    final List<Polyline> polylines = [];
    if (_routedPath.isNotEmpty) {
      polylines.add(
        Polyline(
          points: _routedPath,
          color: Colors.black87,
          strokeWidth: 4.5,
        ),
      );
    } else if (_stopsPoints.isNotEmpty) {
      // Fallback to straight line stops sequence (black)
      polylines.add(
        Polyline(
          points: _stopsPoints,
          color: Colors.black87,
          strokeWidth: 4.5,
        ),
      );
    }

    // Highlight path between current bus location and child's pickup/dropoff stop
    final targetStop = _pickupStop ?? _dropStop;
    if (_animatedBusPosition != null && targetStop != null && _isTracking) {
      final stopLat = (targetStop['latitude'] as num?)?.toDouble();
      final stopLng = (targetStop['longitude'] as num?)?.toDouble();
      if (stopLat != null && stopLng != null) {
        if (_routedBusToStopPath.isNotEmpty) {
          polylines.add(
            Polyline(
              points: _routedBusToStopPath,
              color: Colors.orange.shade800,
              strokeWidth: 4.0,
            ),
          );
        } else {
          // Fallback to straight line
          polylines.add(
            Polyline(
              points: [_animatedBusPosition!, LatLng(stopLat, stopLng)],
              color: Colors.orange.shade800,
              strokeWidth: 4.0,
            ),
          );
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Track $_childName'),
        centerTitle: false,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: _isAdminMode ? [] : [
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
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
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
                                userAgentPackageName: 'com.infoleena.wheelstracker',
                              ),
                              PolylineLayer(polylines: polylines),
                              MarkerLayer(markers: markers),
                            ],
                          ),
                          // Floating ETA Card
                          if (_isTracking && _estimatedDurationSeconds != null)
                            Positioned(
                              top: 16,
                              left: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    )
                                  ],
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.directions_bus_rounded, color: Colors.orange.shade800, size: 20),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'ETA: ${_formatDuration(_estimatedDurationSeconds!)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          'Distance: ${_formatDistance(_estimatedDistanceMeters!)}',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
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
                            final isSchool = stop['is_school'] == true;
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
                                        color: isSchool
                                            ? Colors.purple
                                            : isPickup
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
                                          fontWeight: isSchool || isPickup || isDrop ? FontWeight.bold : FontWeight.normal,
                                          fontSize: 14,
                                          color: isSchool || isPickup || isDrop ? Colors.black87 : Colors.black54,
                                        ),
                                      ),
                                      if (isSchool || isPickup || isDrop)
                                        Text(
                                          isSchool
                                              ? 'School Location'
                                              : isPickup
                                                  ? 'Your Pickup Stop'
                                                  : 'Your Dropoff Stop',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isSchool
                                                ? Colors.purple
                                                : isPickup
                                                    ? Colors.green
                                                    : Colors.red,
                                          ),
                                        ),
                                      const SizedBox(height: 12),
                                    ],
                                  ),
                                ),
                                // Scheduled Time
                                Text(
                                  isSchool ? '' : scheduledTime,
                                  style: TextStyle(
                                    fontWeight: isSchool || isPickup || isDrop ? FontWeight.bold : FontWeight.normal,
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
