import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import 'add_member_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final int groupId;
  final String groupName;

  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _group;
  List<dynamic> _members = [];
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;
  MapController? _mapController;

  // Selected member to show on map details overlay
  Map<String, dynamic>? _selectedMemberOnMap;

  // Track location update interval from setting
  int _refreshIntervalSeconds = 10;
  Map<String, dynamic>? _currentUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _mapController = MapController();
    _fetchDetails();
    _loadIntervalAndSetupTimer();
    _loadCurrentUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadIntervalAndSetupTimer() async {
    try {
      final res = await ApiService.getLocationInterval();
      if (res['success'] == true && res['location_update_interval_seconds'] != null) {
        _refreshIntervalSeconds = res['location_update_interval_seconds'];
      }
    } catch (_) {}

    // Setup periodic polling for real-time location updates
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(Duration(seconds: _refreshIntervalSeconds), (_) {
      if (mounted && !_isLoading) {
        _fetchDetails(silent: true);
      }
    });
  }

  Future<void> _loadCurrentUser() async {
    final user = await ApiService.getUser();
    if (mounted) {
      setState(() {
        _currentUser = user;
      });
    }
  }

  bool get _isSharingLocationWithThisGroup {
    if (_currentUser == null || _members.isEmpty) return false;
    final me = _members.firstWhere(
      (m) => m['id'] == _currentUser!['id'],
      orElse: () => null,
    );
    return me?['location_sharing_enabled'] == true;
  }

  Future<void> _toggleGroupSharing(bool val) async {
    if (val) {
      final success = await LocationService().startTracking();
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not request location permission. Please enable GPS.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    final res = await ApiService.toggleGroupLocationSharing(widget.groupId, val);

    if (mounted) {
      if (res['success'] == true) {
        await _fetchDetails(silent: true);
        
        // Update background service state based on all groups
        final groupsRes = await ApiService.getGroups();
        if (groupsRes['success'] == true && groupsRes['groups'] != null) {
          await LocationService().updateTrackingStateBasedOnGroups(groupsRes['groups']);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Failed to update sharing setting.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _fetchDetails({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final res = await ApiService.getGroupDetail(widget.groupId);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res['success'] == true) {
          _group = res['group'];
          _members = res['members'] ?? [];
        } else {
          _error = res['message'] ?? 'Failed to load group details.';
        }
      });
    }
  }

  Future<void> _removeMember(int userId, String memberName) async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Are you sure you want to remove $memberName from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final res = await ApiService.removeGroupMember(widget.groupId, userId);
      if (mounted) {
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Member removed successfully.'), backgroundColor: Colors.green),
          );
          _fetchDetails();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Failed to remove member.'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _toggleRole(int userId, String currentRole) async {
    final nextRole = currentRole == 'admin' ? 'member' : 'admin';
    final res = await ApiService.updateMemberRole(widget.groupId, userId, nextRole);

    if (mounted) {
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Role updated successfully.'), backgroundColor: Colors.green),
        );
        _fetchDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Failed to update role.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _leaveGroup() async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Find current user's ID
      final myUser = await ApiService.getUser();
      if (myUser != null && myUser['id'] != null) {
        final myId = myUser['id'];
        final res = await ApiService.removeGroupMember(widget.groupId, myId);
        if (mounted) {
          if (res['success'] == true) {
            Navigator.pop(context, true);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(res['message'] ?? 'Failed to leave group.'), backgroundColor: Colors.red),
            );
          }
        }
      }
    }
  }

  void _centerMapOnUser(double lat, double lng) {
    _mapController?.move(LatLng(lat, lng), 15.0);
  }

  Widget _buildSharingToggleCard(ThemeData theme) {
    final isSharing = _isSharingLocationWithThisGroup;
    return Container(
      color: theme.colorScheme.primary.withOpacity(0.04),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: isSharing ? Colors.green.shade100 : Colors.grey.shade200,
                child: Icon(
                  isSharing ? Icons.location_on_rounded : Icons.location_off_rounded,
                  size: 20,
                  color: isSharing
                      ? (theme.brightness == Brightness.dark ? Colors.green.shade400 : Colors.green.shade800)
                      : (theme.brightness == Brightness.dark ? Colors.grey.shade400 : Colors.grey.shade600),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Share Location with this Group',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      isSharing ? 'Other members can see your live position.' : 'Your location is hidden from this group.',
                      style: TextStyle(color: theme.brightness == Brightness.dark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isSharing,
                onChanged: _toggleGroupSharing,
                activeColor: Colors.green.shade700,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = _group?['is_admin'] ?? false;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        iconTheme: IconThemeData(color: theme.colorScheme.onPrimary),
        title: Text(
          widget.groupName,
          style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _fetchDetails(),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: theme.colorScheme.onPrimary),
            onSelected: (value) {
              if (value == 'leave') {
                _leaveGroup();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app_rounded, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Leave Group', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.onPrimary,
          unselectedLabelColor: theme.colorScheme.onPrimary.withOpacity(0.6),
          indicatorColor: theme.colorScheme.onPrimary,
          tabs: const [
            Tab(icon: Icon(Icons.people_alt_rounded), text: 'Members'),
            Tab(icon: Icon(Icons.map_rounded), text: 'Real-Time Map'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 64, color: theme.colorScheme.error),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _fetchDetails(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    _buildSharingToggleCard(theme),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildMembersTab(theme, isAdmin),
                          _buildMapTab(theme),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildMembersTab(ThemeData theme, bool isGroupAdmin) {
    return ListView(
      padding: const EdgeInsets.all(20.0),
      children: [
        if (isGroupAdmin)
          ElevatedButton.icon(
            onPressed: () async {
              final added = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AddMemberScreen(groupId: widget.groupId)),
              );
              if (added == true) {
                _fetchDetails();
              }
            },
            icon: const Icon(Icons.person_add_rounded),
            label: const Text('Add Member', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary.withOpacity(0.08),
              foregroundColor: theme.colorScheme.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          'Group Members (${_members.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._members.map((member) {
          final isSharing = member['location_sharing_enabled'] == true;
          final role = member['role'] == 'admin' ? 'Admin' : 'Member';
          final email = member['email'] ?? '';

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Stack(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                    backgroundImage: member['profile_photo'] != null && member['profile_photo'].toString().startsWith('http')
                        ? NetworkImage(member['profile_photo'])
                        : null,
                    child: member['profile_photo'] == null
                        ? Text(
                            member['name'].toString().isNotEmpty ? member['name'].toString()[0].toUpperCase() : 'M',
                            style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isSharing ? Colors.green : Colors.grey.shade400,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              title: Row(
                children: [
                  Text(member['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: member['role'] == 'admin'
                          ? theme.colorScheme.primary.withOpacity(0.12)
                          : (theme.brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      role,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: member['role'] == 'admin'
                            ? theme.colorScheme.primary
                            : (theme.brightness == Brightness.dark ? Colors.grey.shade300 : Colors.grey.shade600),
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(email, style: TextStyle(color: theme.brightness == Brightness.dark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 13)),
                  if (isSharing && member['latitude'] != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        const Text(
                          'Sharing location',
                          style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              trailing: isGroupAdmin
                  ? PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'role') {
                          _toggleRole(member['id'], member['role']);
                        } else if (value == 'remove') {
                          _removeMember(member['id'], member['name']);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'role',
                          child: Text(member['role'] == 'admin' ? 'Demote to Member' : 'Promote to Admin'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove from Group', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    )
                  : (isSharing && member['latitude'] != null
                      ? IconButton(
                          icon: Icon(Icons.my_location_rounded, color: theme.colorScheme.primary),
                          onPressed: () {
                            _tabController.animateTo(1);
                            Future.delayed(const Duration(milliseconds: 300), () {
                              _centerMapOnUser(
                                (member['latitude'] as num).toDouble(),
                                (member['longitude'] as num).toDouble(),
                              );
                              setState(() {
                                _selectedMemberOnMap = member;
                              });
                            });
                          },
                        )
                      : null),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMapTab(ThemeData theme) {
    // Collect members that have active location sharing
    final activeMembers = _members.where((m) => m['location_sharing_enabled'] == true && m['latitude'] != null).toList();

    // Default center if no coordinates available (Ahmedabad coordinates as project center)
    LatLng mapCenter = const LatLng(23.0225, 72.5714);
    if (activeMembers.isNotEmpty) {
      mapCenter = LatLng(
        (activeMembers.first['latitude'] as num).toDouble(),
        (activeMembers.first['longitude'] as num).toDouble(),
      );
    }

    final markers = activeMembers.map((member) {
      final lat = (member['latitude'] as num).toDouble();
      final lng = (member['longitude'] as num).toDouble();

      return Marker(
        point: LatLng(lat, lng),
        width: 60,
        height: 60,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedMemberOnMap = member;
            });
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    )
                  ],
                  border: Border.all(
                    color: _selectedMemberOnMap?['id'] == member['id']
                        ? Colors.green
                        : theme.colorScheme.primary,
                    width: 3,
                  ),
                ),
                child: ClipOval(
                  child: member['profile_photo'] != null && member['profile_photo'].toString().startsWith('http')
                      ? Image.network(member['profile_photo'], fit: BoxFit.cover)
                      : Center(
                          child: Text(
                            member['name'].toString().isNotEmpty ? member['name'].toString()[0].toUpperCase() : 'M',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: mapCenter,
            initialZoom: 14.0,
            onTap: (position, point) {
              setState(() {
                _selectedMemberOnMap = null;
              });
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.fleetfind.app',
            ),
            MarkerLayer(markers: markers),
          ],
        ),

        // Map selection details card overlay
        if (_selectedMemberOnMap != null)
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                      backgroundImage: _selectedMemberOnMap!['profile_photo'] != null
                          ? NetworkImage(_selectedMemberOnMap!['profile_photo'])
                          : null,
                      child: _selectedMemberOnMap!['profile_photo'] == null
                          ? Text(
                              _selectedMemberOnMap!['name'].toString()[0].toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedMemberOnMap!['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Active Role: ${_selectedMemberOnMap!['role'] == 'admin' ? 'Admin' : 'Member'}',
                            style: TextStyle(color: theme.brightness == Brightness.dark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.my_location_rounded, color: theme.colorScheme.primary),
                      onPressed: () {
                        _centerMapOnUser(
                          (_selectedMemberOnMap!['latitude'] as num).toDouble(),
                          (_selectedMemberOnMap!['longitude'] as num).toDouble(),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        setState(() {
                          _selectedMemberOnMap = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
