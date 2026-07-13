import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../services/location_service.dart';

class TripDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> trip;

  const TripDetailsScreen({super.key, required this.trip});

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  bool _isTracking = false;
  bool _isLoading = false;
  double? _currentLat;
  double? _currentLng;
  double? _currentSpeed;
  DateTime? _lastUpdated;
  StreamSubscription? _updateSubscription;

  @override
  void initState() {
    super.initState();
    final tripId = widget.trip['id'] as int?;
    if (tripId != null) {
      _isTracking = LocationService().isTracking && LocationService().activeTripId == tripId;
    }

    // Start listening to background location updates
    _updateSubscription = FlutterBackgroundService().on('update').listen((event) {
      if (event != null && mounted) {
        setState(() {
          _currentLat = event['latitude'] as double?;
          _currentLng = event['longitude'] as double?;
          _currentSpeed = event['speed'] as double?;
          _lastUpdated = DateTime.tryParse(event['time'] ?? '');
        });
      }
    });
  }

  @override
  void dispose() {
    _updateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _makeCall(String number) async {
    if (number.isEmpty) return;
    final Uri url = Uri.parse('tel:$number');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _toggleTracking() async {
    final tripId = widget.trip['id'] as int?;
    if (tripId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isTracking) {
        await LocationService().stopTripTracking(tripId);
        setState(() {
          _isTracking = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Live location sharing stopped.')),
          );
        }
      } else {
        final success = await LocationService().startTripTracking(tripId);
        if (success) {
          setState(() {
            _isTracking = true;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Live location sharing started successfully!')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to start live location sharing. Verify location permissions.')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tripName = widget.trip['name'] ?? 'Trip Details';
    final orgName = widget.trip['organization'] ?? 'N/A';
    final vehicle = widget.trip['vehicle'] as Map<String, dynamic>?;
    final driver = widget.trip['driver'] as Map<String, dynamic>?;
    final assistant = widget.trip['assistant'] as Map<String, dynamic>?;
    final stops = (widget.trip['stops'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tripName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 0. Live Tracking Dashboard Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: _isTracking 
                      ? Colors.green.withOpacity(0.4) 
                      : theme.colorScheme.outlineVariant.withOpacity(0.4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.sensors_rounded,
                              color: _isTracking ? Colors.green : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Live Location Sharing',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isTracking ? Colors.green.shade700 : Colors.black87,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        if (_isLoading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Switch.adaptive(
                            value: _isTracking,
                            activeColor: Colors.green,
                            onChanged: _isLoading ? null : (_) => _toggleTracking(),
                          ),
                      ],
                    ),
                    if (_isTracking) ...[
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildDashboardItem(
                            context,
                            Icons.my_location_rounded,
                            'Coordinates',
                            _currentLat != null && _currentLng != null
                                ? '${_currentLat!.toStringAsFixed(4)}, ${_currentLng!.toStringAsFixed(4)}'
                                : 'Fetching...',
                          ),
                          _buildDashboardItem(
                            context,
                            Icons.speed_rounded,
                            'Speed',
                            _currentSpeed != null
                                ? '${(_currentSpeed! * 3.6).toStringAsFixed(1)} km/h'
                                : '0.0 km/h',
                          ),
                          _buildDashboardItem(
                            context,
                            Icons.access_time_rounded,
                            'Last Update',
                            _lastUpdated != null
                                ? '${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}:${_lastUpdated!.second.toString().padLeft(2, '0')}'
                                : 'Just now',
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 1. Trip Summary Header Card
            Card(
              elevation: 3,
              shadowColor: theme.colorScheme.shadow.withOpacity(0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            orgName,
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Active Service',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    
                    // Vehicle details
                    Row(
                      children: [
                        Icon(Icons.directions_bus_rounded, color: Colors.blue.shade300, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Vehicle Description', style: TextStyle(color: Colors.grey, fontSize: 11)),
                              Text(
                                vehicle != null 
                                    ? '${vehicle['registration_number'] ?? 'N/A'} (${vehicle['model'] ?? 'N/A'})'
                                    : 'N/A',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    // Crew Info (Driver & Attendant)
                    if (driver != null || assistant != null) ...[
                      const SizedBox(height: 16),
                      Column(
                        children: [
                          // Driver
                          if (driver != null)
                            Row(
                              children: [
                                Icon(Icons.badge_rounded, color: Colors.teal.shade300, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Driver', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                      Text(
                                        driver['name'] ?? 'N/A',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                                if (driver['mobile'] != null && driver['mobile'].toString().isNotEmpty)
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.phone_rounded, color: Colors.teal, size: 18),
                                    onPressed: () => _makeCall(driver['mobile'].toString()),
                                  ),
                              ],
                            ),
                          if (driver != null && assistant != null) const SizedBox(height: 12),
                          // Attendant/Assistant
                          if (assistant != null)
                            Row(
                              children: [
                                Icon(Icons.support_agent_rounded, color: Colors.orange.shade300, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Attendant', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                      Text(
                                        assistant['name'] ?? 'N/A',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                                if (assistant['mobile'] != null && assistant['mobile'].toString().isNotEmpty)
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.phone_rounded, color: Colors.teal, size: 18),
                                    onPressed: () => _makeCall(assistant['mobile'].toString()),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            const SizedBox(height: 24),

            // Section Title
            Row(
              children: [
                Icon(Icons.timeline_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Stops & Enrolled Children',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Timeline List of Stops
            if (stops.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text('No stops found for this route.', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: stops.length,
                itemBuilder: (context, index) {
                  final stop = stops[index];
                  final stopName = stop['name'] ?? 'N/A';
                  final stopTime = stop['time'] ?? 'N/A';
                  final displayTime = stopTime.toString().split(':').take(2).join(':');
                  final children = (stop['children'] as List?) ?? [];

                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left Timeline indicator
                        Column(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: index == 0 ? theme.colorScheme.primary : theme.colorScheme.secondary,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.shadow.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ],
                              ),
                            ),
                            Expanded(
                              child: Container(
                                width: 2,
                                color: index == stops.length - 1 
                                    ? Colors.transparent 
                                    : Colors.grey.shade300,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        // Stop content
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Stop Name & Scheduled Time Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        stopName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      displayTime,
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Children List at this Stop
                                if (children.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                                    child: Text(
                                      'No children enrolled for this stop.',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  )
                                else
                                  ...children.map((dynamic child) {
                                    final childName = child['name'] ?? 'N/A';
                                    final status = child['status'] ?? 'N/A';
                                    final grade = child['grade'] ?? 'N/A';
                                    final division = child['division'] ?? 'N/A';
                                    final isPickup = child['is_pickup'] == true;
                                    final isDrop = child['is_drop'] == true;

                                    final parentPhone = child['parent_phone'] ?? '';
                                    final parentName = child['parent_name'] ?? 'Parent';

                                    // Color coding status
                                    Color statusBgColor = Colors.grey.shade100;
                                    Color statusTextColor = Colors.grey.shade600;
                                    if (status.toString().toLowerCase() == 'active') {
                                      statusBgColor = Colors.green.withOpacity(0.1);
                                      statusTextColor = Colors.green.shade700;
                                    } else if (status.toString().toLowerCase() == 'pending') {
                                      statusBgColor = Colors.orange.withOpacity(0.1);
                                      statusTextColor = Colors.orange.shade700;
                                    } else if (status.toString().toLowerCase() == 'hold' || status.toString().toLowerCase() == 'pending_hold') {
                                      statusBgColor = Colors.red.withOpacity(0.1);
                                      statusTextColor = Colors.red.shade700;
                                    }

                                    return Container(
                                      margin: const EdgeInsets.only(top: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: theme.colorScheme.secondaryContainer,
                                            child: Icon(
                                              Icons.person_rounded,
                                              size: 18,
                                              color: theme.colorScheme.onSecondaryContainer,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  childName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Grade: $grade - Div: $division',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    // Status badge
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: statusBgColor,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        status.toString().toUpperCase(),
                                                        style: TextStyle(
                                                          color: statusTextColor,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 9,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    // Stop Type (Pickup/Drop) Badge
                                                    if (isPickup)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.blue.withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: const Text(
                                                          'PICKUP',
                                                          style: TextStyle(
                                                            color: Colors.blue,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 8,
                                                          ),
                                                        ),
                                                      )
                                                    else if (isDrop)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.purple.withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: const Text(
                                                          'DROP',
                                                          style: TextStyle(
                                                            color: Colors.purple,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 8,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (parentPhone.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.phone_rounded, color: Colors.teal),
                                              tooltip: 'Call Parent ($parentName)',
                                              onPressed: () => _makeCall(parentPhone),
                                            ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardItem(BuildContext context, IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
