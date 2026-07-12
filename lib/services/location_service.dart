import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'api_service.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Timer? _timer;
  bool _isTracking = false;
  int _intervalSeconds = 10; // Default fallback
  int? _activeTripId;

  bool get isTracking => _isTracking;
  int? get activeTripId => _activeTripId;

  // Initialize service, fetch interval, and auto-resume if configured
  Future<void> init() async {
    // 1. Initialize background service configurations
    await initializeService();

    // 2. Fetch update interval from settings
    try {
      final res = await ApiService.getLocationInterval();
      if (res['success'] == true && res['location_update_interval_seconds'] != null) {
        _intervalSeconds = res['location_update_interval_seconds'];
      }
    } catch (e) {
      // Fallback to default 10 seconds
    }

    // 3. Check if user was tracking a trip previously
    final prefs = await SharedPreferences.getInstance();
    _activeTripId = prefs.getInt('active_trip_id');
    
    // Check if background service is running
    final isRunning = await FlutterBackgroundService().isRunning();
    _isTracking = isRunning && _activeTripId != null;
  }

  // Request permissions and start tracking a specific trip
  Future<bool> startTripTracking(int tripId) async {
    // 1. Request foreground location permission
    var status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      return false;
    }

    // 2. Request background location permission
    var bgStatus = await Permission.locationAlways.request();
    if (!bgStatus.isGranted) {
      // Background location permission is recommended for keeping tracking alive
    }

    // 3. Make sure location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    // 4. Toggle tracking on backend first
    final toggleRes = await ApiService.toggleTripTracking(tripId, true);
    if (toggleRes['success'] != true) {
      return false;
    }

    _activeTripId = tripId;
    _isTracking = true;

    // 5. Save config parameters to SharedPreferences for the background isolate
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('active_trip_id', tripId);
    await prefs.setInt('location_update_interval_seconds', _intervalSeconds);
    
    final token = await ApiService.getToken();
    if (token != null) {
      await prefs.setString('auth_token', token);
    }
    await prefs.setString('api_base_url', ApiService.baseUrl);

    // 6. Start the background service
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    } else {
      // If already running, notify service about new trip ID
      service.invoke('updateTripId', {'tripId': tripId});
    }

    return true;
  }

  // Stop tracking the active trip
  Future<void> stopTripTracking(int tripId) async {
    _isTracking = false;
    _activeTripId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_trip_id');

    // 1. Stop background service
    final service = FlutterBackgroundService();
    service.invoke('stopService');

    // 2. Inform the server that sharing is disabled (which will null the coordinates)
    try {
      await ApiService.toggleTripTracking(tripId, false);
    } catch (e) {
      // Ignore network errors on stop
    }
  }

  // Updates tracking state based on group-specific sharing settings (legacy compatibility)
  Future<void> updateTrackingStateBasedOnGroups(List<dynamic> groups) async {
    final anySharing = groups.any((g) => g['user_sharing_enabled'] == true);
    if (anySharing) {
      if (!_isTracking) {
        await startTracking();
      }
    } else {
      if (_isTracking) {
        await stopTracking();
      }
    }
  }

  // Request permissions and start tracking (legacy compatibility)
  Future<bool> startTracking() async {
    var status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) return false;
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    _timer?.cancel();
    _isTracking = true;

    // Initial position fetch and update
    await _fetchAndSendLocation();

    // Start periodic timer
    _timer = Timer.periodic(Duration(seconds: _intervalSeconds), (timer) async {
      await _fetchAndSendLocation();
    });

    return true;
  }

  // Stop tracking and toggle off on server (legacy compatibility)
  Future<void> stopTracking() async {
    _timer?.cancel();
    _isTracking = false;
    try {
      await ApiService.updateLocation(0, 0, false);
    } catch (e) {
      // Ignore network errors
    }
  }

  // Core tracking execution (legacy compatibility)
  Future<void> _fetchAndSendLocation() async {
    if (!_isTracking) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      );
      await ApiService.updateLocation(position.latitude, position.longitude, true);
    } catch (e) {
      // Ignore background errors
    }
  }
}

// Global function to initialize FlutterBackgroundService configurations
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'trip_tracking_channel',
      initialNotificationTitle: 'FleetFind Live Route Tracking',
      initialNotificationContent: 'Starting live location sharing...',
      foregroundServiceNotificationId: 991,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Pull local persisted parameters
  final prefs = await SharedPreferences.getInstance();
  int tripId = prefs.getInt('active_trip_id') ?? 0;
  final interval = prefs.getInt('location_update_interval_seconds') ?? 10;
  final token = prefs.getString('auth_token') ?? '';
  final baseUrl = prefs.getString('api_base_url') ?? '';

  // Listener to support updating tripId on the fly
  service.on('updateTripId').listen((event) {
    if (event != null && event['tripId'] != null) {
      tripId = event['tripId'] as int;
    }
  });

  // Periodically fetch and push coordinates
  Timer.periodic(Duration(seconds: interval), (timer) async {
    final isRunning = await FlutterBackgroundService().isRunning();
    if (!isRunning || tripId == 0) {
      timer.cancel();
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      );

      if (baseUrl.isNotEmpty && token.isNotEmpty) {
        final url = Uri.parse('$baseUrl/trip/$tripId/location');
        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'latitude': position.latitude,
            'longitude': position.longitude,
            'speed': position.speed,
          }),
        );

        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'FleetFind Live Route Tracking',
            content: 'Sending updates (Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)})',
          );
        }
      }
    } catch (e) {
      // Ignore background errors
    }
  });
}
