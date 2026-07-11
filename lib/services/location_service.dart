import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Timer? _timer;
  bool _isTracking = false;
  int _intervalSeconds = 10; // Default fallback

  bool get isTracking => _isTracking;

  // Initialize service, fetch interval, and auto-resume if configured
  Future<void> init() async {
    // Fetch update interval from settings
    try {
      final res = await ApiService.getLocationInterval();
      if (res['success'] == true && res['location_update_interval_seconds'] != null) {
        _intervalSeconds = res['location_update_interval_seconds'];
      }
    } catch (e) {
      // Fallback to default 10 seconds
    }

    // Check if user is sharing with any group on start
    try {
      final res = await ApiService.getGroups();
      if (res['success'] == true && res['groups'] != null) {
        final groups = res['groups'] as List<dynamic>;
        await updateTrackingStateBasedOnGroups(groups);
      }
    } catch (e) {
      // If network fails on start, fallback to persisted state
      final prefs = await SharedPreferences.getInstance();
      _isTracking = prefs.getBool('location_sharing_on') ?? false;
      if (_isTracking) {
        await startTracking();
      }
    }
  }

  // Updates tracking state based on group-specific sharing settings
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

  // Request permissions and start tracking
  Future<bool> startTracking() async {
    // 1. Request foreground location permission
    var status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      _setTrackingState(false);
      return false;
    }

    // 2. Request background location permission
    var bgStatus = await Permission.locationAlways.request();
    if (!bgStatus.isGranted) {
      // Background location permission is highly recommended for keeping tracking alive,
      // but if the OS doesn't grant 'Always', we fall back to 'WhenInUse'
    }

    // 3. Make sure location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _setTrackingState(false);
      return false;
    }

    // Cancel existing timer if any
    _timer?.cancel();

    _setTrackingState(true);

    // Initial position fetch and update
    await _fetchAndSendLocation();

    // Start periodic timer
    _timer = Timer.periodic(Duration(seconds: _intervalSeconds), (timer) async {
      await _fetchAndSendLocation();
    });

    return true;
  }

  // Stop tracking and toggle off on server
  Future<void> stopTracking() async {
    _timer?.cancel();
    _setTrackingState(false);

    try {
      // Inform the server that sharing is disabled
      await ApiService.updateLocation(0, 0, false);
    } catch (e) {
      // Ignore network errors on stop
    }
  }

  // Set local state and persist to SharedPreferences
  Future<void> _setTrackingState(bool tracking) async {
    _isTracking = tracking;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('location_sharing_on', tracking);
  }

  // Core tracking execution
  Future<void> _fetchAndSendLocation() async {
    if (!_isTracking) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      );

      await ApiService.updateLocation(
        position.latitude,
        position.longitude,
        true,
      );
    } catch (e) {
      // Ignore background errors (e.g. timeout or disabled GPS temporary states)
    }
  }
}
