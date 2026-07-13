import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'screens/login_screen.dart';
import 'screens/create_group_screen.dart';
import 'screens/group_detail_screen.dart';
import 'screens/child_detail_screen.dart';
import 'screens/organization_profile_screen.dart';
import 'screens/trip_details_screen.dart';
import 'screens/child_track_screen.dart';
import 'services/api_service.dart';
import 'services/location_service.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocationService().init();
  final loggedIn = await ApiService.isLoggedIn();
  runApp(MyApp(loggedIn: loggedIn));
}

class MyApp extends StatelessWidget {
  final bool loggedIn;

  const MyApp({super.key, required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wheels Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2C3E50),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF2C3E50),
          onPrimary: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2C3E50),
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFF5D9CEC),
          onPrimary: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E2A38),
          foregroundColor: Colors.white,
          iconTheme: IconThemeData(color: Colors.white),
          centerTitle: false,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      initialRoute: loggedIn ? '/home' : '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const MyHomePage(title: 'Wheels Tracker Operations Board'),
        '/child-detail': (context) => const ChildDetailScreen(),
        '/child-track': (context) => const ChildTrackScreen(),
        '/organization-profile': (context) => const OrganizationProfileScreen(),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with SingleTickerProviderStateMixin {

  Map<String, dynamic>? _user;
  int _currentIndex = 2; // Default to Home page in the center
  late AnimationController _rotationController;

  final TextEditingController _searchQueryController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  String _searchError = '';
  int? _selectedOrganizationId;
  int _activeOrgTabIndex = 0;

  // Search Pagination State
  int _searchPage = 1;
  bool _searchHasMore = true;
  bool _isLoadingMore = false;
  final ScrollController _searchScrollController = ScrollController();

  // Group Feature State Variables
  List<dynamic> _groups = [];
  bool _isGroupsLoading = true;
  String? _groupsError;
  bool _isLocationSharingOn = false;
  Timer? _groupsTimer;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    _searchScrollController.addListener(() {
      if (_searchScrollController.position.pixels >= _searchScrollController.position.maxScrollExtent - 200) {
        _loadMoreOrganizations();
      }
    });
    _performSearch('');
    _loadLocationSharingState();
    _fetchGroups();

    // Live update groups list periodically every 10 seconds in the background
    _groupsTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && _currentIndex == 0) {
        _fetchGroups(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _searchQueryController.dispose();
    _searchScrollController.dispose();
    _groupsTimer?.cancel();
    super.dispose();
  }

  void _performSearch(String query) async {
    setState(() {
      _isSearching = true;
      _searchError = '';
      _searchPage = 1;
      _searchHasMore = true;
      _searchResults = [];
    });
    try {
      final res = await ApiService.searchOrganizations(query, page: 1);
      if (res['success'] == true) {
        setState(() {
          _searchResults = res['organizations'] ?? [];
          final meta = res['meta'];
          if (meta != null) {
            _searchHasMore = meta['has_more'] == true;
          } else {
            _searchHasMore = false;
          }
        });
      } else {
        setState(() {
          _searchError = res['message'] ?? 'Failed to load search results.';
        });
      }
    } catch (e) {
      setState(() {
        _searchError = 'Error: $e';
      });
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _loadMoreOrganizations() async {
    if (_isSearching || _isLoadingMore || !_searchHasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = _searchPage + 1;
      final res = await ApiService.searchOrganizations(_searchQueryController.text, page: nextPage);
      if (res['success'] == true) {
        setState(() {
          final newItems = res['organizations'] ?? [];
          _searchResults.addAll(newItems);
          _searchPage = nextPage;
          final meta = res['meta'];
          if (meta != null) {
            _searchHasMore = meta['has_more'] == true;
          } else {
            _searchHasMore = false;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading more organizations: $e');
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) return;
    final Uri launchUri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  bool _isTripToggling = false;

  Future<void> _toggleTripTracking(int tripId, bool currentlyTracking) async {
    setState(() {
      _isTripToggling = true;
    });

    try {
      if (currentlyTracking) {
        await LocationService().stopTripTracking(tripId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Live location sharing stopped.')),
          );
        }
      } else {
        final success = await LocationService().startTripTracking(tripId);
        if (success) {
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
          _isTripToggling = false;
        });
      }
    }
  }

  Future<void> _loadUser() async {
    final cachedUser = await ApiService.getUser();
    if (cachedUser != null) {
      setState(() {
        _user = cachedUser;
      });
    }

    try {
      final response = await ApiService.fetchFreshUser();
      if (response['success'] == true && response['user'] != null) {
        final freshUser = response['user'] as Map<String, dynamic>;
        setState(() {
          _user = freshUser;
        });
      }
    } catch (e) {
      debugPrint('Error loading fresh user details: $e');
    }
  }

  void _loadLocationSharingState() {
    setState(() {
      _isLocationSharingOn = LocationService().isTracking;
    });
  }

  Future<void> _toggleLocationSharing(bool val) async {
    setState(() {
      _isLocationSharingOn = val;
    });
    if (val) {
      final success = await LocationService().startTracking();
      if (!success) {
        setState(() {
          _isLocationSharingOn = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to start location sharing. Please grant location permissions.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      await LocationService().stopTracking();
    }
  }

  Future<void> _fetchGroups({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isGroupsLoading = true;
        _groupsError = null;
      });
    }
    final res = await ApiService.getGroups();
    if (mounted) {
      setState(() {
        _isGroupsLoading = false;
        if (res['success'] == true) {
          _groups = res['groups'] ?? [];
        } else {
          if (!silent) {
            _groupsError = res['message'] ?? 'Failed to load groups.';
          }
        }
      });
    }
  }

  void _onTabChanged(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
    });
    if (index == 0) {
      _fetchGroups(silent: _groups.isNotEmpty);
    }
  }

  void _showEditProfileDialog(ThemeData theme) {
    final nameController = TextEditingController(text: _user?['name'] ?? '');
    final emailController = TextEditingController(text: _user?['email'] ?? '');
    final mobileController = TextEditingController(text: _user?['mobile'] ?? '');

    String? dialogError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Edit Profile Info',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (dialogError != null) ...[
                  Text(dialogError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mobileController,
                  decoration: const InputDecoration(labelText: 'Mobile Number'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        final response = await ApiService.updateProfile(
                          name: nameController.text.trim(),
                          email: emailController.text.trim(),
                          mobile: mobileController.text.trim(),
                        );
                        if (response['success'] == true) {
                          final freshUser = await ApiService.getUser();
                          setState(() {
                            _user = freshUser;
                          });
                          if (context.mounted) Navigator.pop(context);
                        } else {
                          setDialogState(() {
                            dialogError = response['message'];
                          });
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog(ThemeData theme) {
    final currentPasswordController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    String? dialogError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Change Password',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (dialogError != null) ...[
                  Text(dialogError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: currentPasswordController,
                  decoration: const InputDecoration(labelText: 'Current Password'),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: 'New Password'),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPasswordController,
                  decoration: const InputDecoration(labelText: 'Confirm New Password'),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (passwordController.text != confirmPasswordController.text) {
                          setDialogState(() {
                            dialogError = 'New passwords do not match.';
                          });
                          return;
                        }
                        final response = await ApiService.changePassword(
                          currentPassword: currentPasswordController.text,
                          password: passwordController.text,
                          confirmPassword: confirmPasswordController.text,
                        );
                        if (response['success'] == true) {
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Password updated successfully')),
                            );
                          }
                        } else {
                          setDialogState(() {
                            dialogError = response['message'];
                          });
                        }
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (file == null) return;

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );
      }

      final bytes = await file.readAsBytes();
      final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      final response = await ApiService.updateProfile(
        name: _user?['name'] ?? '',
        email: _user?['email'] ?? '',
        mobile: _user?['mobile'] ?? '',
        profilePhoto: base64String,
      );

      if (mounted) {
        Navigator.pop(context); // Dismiss loading dialog
      }

      if (response['success'] == true) {
        final freshUser = await ApiService.getUser();
        setState(() {
          _user = freshUser;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile photo updated successfully')),
          );
        }
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Error'),
              content: Text(response['message'] ?? 'Failed to update profile photo'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == '/home');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _showChangePhotoBottomSheet(ThemeData theme) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Upload Profile Photo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.camera_alt_rounded, color: theme.colorScheme.primary),
              ),
              title: const Text('Camera', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Take a new photo using device camera'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadImage(ImageSource.camera);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.photo_library_rounded, color: theme.colorScheme.primary),
              ),
              title: const Text('From Phone', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Choose an existing photo from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Delete Account?',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const Text(
                'Are you absolutely sure you want to delete your account?',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Warning: This action is permanent. All your registered child profiles, history logs, and settings will be permanently lost.',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );

                      final response = await ApiService.deleteAccount();
                      if (mounted) {
                        Navigator.pop(context);
                        Navigator.pushReplacementNamed(context, '/login');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Delete Account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }



  Future<void> _handleLogout() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    await ApiService.logout();

    if (mounted) {
      Navigator.pop(context); // Close loading dialog
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Widget _buildListCard({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      ),
    );
  }

  Widget _buildGroupPage() {
    final theme = Theme.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_group_page',
        onPressed: () async {
          final created = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateGroupScreen()),
          );
          if (created == true) {
            _fetchGroups();
          }
        },
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create Group', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchGroups,
        child: ListView(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 100),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'My Transit Groups',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if (!_isGroupsLoading)
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _fetchGroups,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isGroupsLoading)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (_groupsError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 12),
                      Text(_groupsError!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _fetchGroups, child: const Text('Retry')),
                    ],
                  ),
                ),
              )
            else if (_groups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48.0),
                child: Column(
                  children: [
                    Icon(Icons.group_work_outlined, size: 64, color: theme.colorScheme.primary.withOpacity(0.3)),
                    const SizedBox(height: 16),
                    const Text(
                      'No Transit Groups Yet',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a group or ask an admin to add you using your email/mobile.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              )
            else
              ..._groups.map((group) {
                final name = group['name'] ?? 'Unnamed Group';
                final desc = group['description'] ?? 'No description provided.';
                final membersCount = group['members_count'] ?? 0;
                final isSharing = group['user_sharing_enabled'] == true;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                      child: Icon(Icons.group_rounded, color: theme.colorScheme.primary),
                    ),
                    title: Row(
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSharing ? Colors.green.shade50 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isSharing ? 'Sharing' : 'Off',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSharing ? Colors.green.shade800 : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '$membersCount member${membersCount == 1 ? "" : "s"} • $desc',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                    onTap: () async {
                      final updated = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GroupDetailScreen(
                            groupId: group['id'],
                            groupName: name,
                          ),
                        ),
                      );
                      if (updated == true) {
                        _fetchGroups();
                      }
                    },
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildParentPage() {
    final theme = Theme.of(context);
    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: ApiService.getChildren(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || snapshot.data == null || snapshot.data!['success'] == false) {
            final errorMsg = snapshot.data?['message'] ?? 'Failed to load children.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 64, color: theme.colorScheme.error),
                    const SizedBox(height: 16),
                    Text(
                      'Error Loading Children',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      errorMsg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final childrenList = (snapshot.data!['children'] as List?) ?? [];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0, bottom: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Children',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Here parents add and manage their children for school transit.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.brightness == Brightness.dark ? Colors.grey.shade400 : Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: childrenList.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.child_care_rounded, size: 80, color: theme.colorScheme.primary.withOpacity(0.3)),
                              const SizedBox(height: 16),
                              const Text(
                                'No Children Registered',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Add your children to schedule their school bus trips and track transit statuses.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: _showAddChildBottomSheet,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add First Child'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 100),
                        itemCount: childrenList.length,
                        itemBuilder: (context, index) {
                          final child = childrenList[index];
                          final dobStr = child['dob'] as String?;
                          final gender = child['gender'] as String?;
                          final childPhoto = child['photo'] as String?;

                          // Age calculation helper
                          String ageInfo = '';
                          if (dobStr != null && dobStr.isNotEmpty) {
                            try {
                              final dob = DateTime.parse(dobStr);
                              final now = DateTime.now();
                              int age = now.year - dob.year;
                              if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
                                age--;
                              }
                              ageInfo = age > 0 ? '$age Years Old' : 'Infant';
                            } catch (_) {}
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                final result = await Navigator.pushNamed(
                                  context,
                                  '/child-detail',
                                  arguments: child,
                                );
                                if (result == true) {
                                  setState(() {});
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 26,
                                          backgroundColor: theme.colorScheme.primaryContainer,
                                          backgroundImage: childPhoto != null && childPhoto.isNotEmpty && childPhoto.startsWith('http')
                                              ? NetworkImage(childPhoto)
                                              : null,
                                          child: childPhoto == null || childPhoto.isEmpty || !childPhoto.startsWith('http')
                                              ? Icon(
                                                  Icons.face_rounded,
                                                  size: 28,
                                                  color: theme.colorScheme.primary,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                child['name'] ?? 'N/A',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  if (ageInfo.isNotEmpty) ...[
                                                    Text(
                                                      ageInfo,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey.shade600,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                  ],
                                                  if (gender != null && gender.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        gender,
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: theme.colorScheme.primary,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                                      ],
                                    ),
                                    if (dobStr != null && dobStr.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'DOB: $dobStr',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FutureBuilder<Map<String, dynamic>>(
        future: ApiService.getChildren(),
        builder: (context, snapshot) {
          final childrenList = (snapshot.data?['children'] as List?) ?? [];
          if (childrenList.isEmpty) return const SizedBox.shrink();
          return FloatingActionButton(
            heroTag: 'fab_children_tab',
            onPressed: _showAddChildBottomSheet,
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            child: const Icon(Icons.add_rounded),
          );
        },
      ),
    );
  }

  void _showAddChildBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AddChildBottomSheet(
        onSaved: () {
          setState(() {});
        },
      ),
    );
  }

  void _showEditChildBottomSheet(Map<String, dynamic> child) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AddChildBottomSheet(
        child: child,
        onSaved: () {
          setState(() {});
        },
      ),
    );
  }

  void _showDeleteChildDialog(Map<String, dynamic> child) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Child Profile?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete ${child['name']}\'s profile?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Warning: This will permanently remove this child\'s profile and all associated ride records.',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final response = await ApiService.deleteChild(child['id']);
              if (response['success'] == true) {
                setState(() {});
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(response['message'] ?? 'Profile deleted successfully.'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(response['message'] ?? 'Failed to delete profile.'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTripsSection(ThemeData theme, List<dynamic> trips, String roleName) {
    if (trips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$roleName Duty Control',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: LocationService().isTracking ? Colors.red.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: LocationService().isTracking ? Colors.red : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      LocationService().isTracking ? 'LIVE NOW' : 'OFFLINE',
                      style: TextStyle(
                        color: LocationService().isTracking ? Colors.red : Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...trips.map((dynamic t) {
            final tripId = t['id'] as int;
            final isCurrentTripTracking = LocationService().isTracking && LocationService().activeTripId == tripId;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isCurrentTripTracking
                      ? Colors.green.withOpacity(0.5)
                      : theme.colorScheme.outlineVariant.withOpacity(0.3),
                  width: isCurrentTripTracking ? 1.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: isCurrentTripTracking
                          ? Colors.green.withOpacity(0.1)
                          : theme.colorScheme.primaryContainer.withOpacity(0.3),
                      child: Icon(
                        Icons.directions_bus_rounded,
                        color: isCurrentTripTracking ? Colors.green : theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t['name'] ?? 'N/A',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t['organization'] ?? 'N/A',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _isTripToggling
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Switch.adaptive(
                            value: isCurrentTripTracking,
                            activeColor: Colors.green,
                            onChanged: (val) {
                              _toggleTripTracking(tripId, isCurrentTripTracking);
                            },
                          ),
                  ],
                ),
              ),
            );
          }).toList(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildHomePage(ThemeData theme, String userName, String userEmail) {
    final roles = _user != null && _user!['roles'] != null
        ? List<String>.from(_user!['roles'])
        : <String>[];
    final isDriver = roles.contains('Driver');
    final isAttendant = roles.contains('Attendant');

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        ApiService.getChildren(),
        isDriver ? ApiService.getDriverTrips() : Future.value(<String, dynamic>{'success': true, 'trips': []}),
        isAttendant ? ApiService.getAttendantTrips() : Future.value(<String, dynamic>{'success': true, 'trips': []}),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || snapshot.data == null) {
          final errorMsg = 'Failed to load dashboard details.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded, size: 64, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(
                    'Error Loading Dashboard',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    errorMsg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final childrenRes = snapshot.data![0] as Map<String, dynamic>;
        final driverRes = snapshot.data![1] as Map<String, dynamic>;
        final attendantRes = snapshot.data![2] as Map<String, dynamic>;

        final childrenList = (childrenRes['children'] as List?) ?? [];
        final driverTrips = (driverRes['trips'] as List?) ?? [];
        final attendantTrips = (attendantRes['trips'] as List?) ?? [];

        final bool hasAnyDutySection = (isDriver && driverTrips.isNotEmpty) || (isAttendant && attendantTrips.isNotEmpty);

        if (childrenList.isEmpty && !hasAnyDutySection) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.child_care_rounded, size: 100, color: theme.colorScheme.primary.withOpacity(0.3)),
                  const SizedBox(height: 24),
                  const Text(
                    'No Children Registered',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Please add your children to register for subscription plans, schedule trips, and track transit.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, height: 1.4),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _showAddChildBottomSheet,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add a Child'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (childrenList.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Text(
                      'My Children',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: childrenList.length,
                    itemBuilder: (context, index) {
                      final child = childrenList[index];
                      final dobStr = child['dob'] as String?;
                      final gender = child['gender'] as String?;
                      final childPhoto = child['photo'] as String?;

                      // Age calculation helper
                      String ageInfo = '';
                      if (dobStr != null && dobStr.isNotEmpty) {
                        try {
                          final dob = DateTime.parse(dobStr);
                          final now = DateTime.now();
                          int age = now.year - dob.year;
                          if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
                            age--;
                          }
                          ageInfo = age > 0 ? '$age Years Old' : 'Infant';
                        } catch (_) {}
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            final result = await Navigator.pushNamed(
                              context,
                              '/child-track',
                              arguments: child,
                            );
                            if (result == true) {
                              setState(() {});
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundColor: theme.colorScheme.primaryContainer,
                                      backgroundImage: childPhoto != null && childPhoto.isNotEmpty && childPhoto.startsWith('http')
                                          ? NetworkImage(childPhoto)
                                          : null,
                                      child: childPhoto == null || childPhoto.isEmpty || !childPhoto.startsWith('http')
                                          ? Icon(
                                              Icons.face_rounded,
                                              size: 28,
                                              color: theme.colorScheme.primary,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            child['name'] ?? 'N/A',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              if (ageInfo.isNotEmpty) ...[
                                                Text(
                                                  ageInfo,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                              if (gender != null && gender.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    gender,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: theme.colorScheme.primary,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                                  ],
                                ),
                                if (child['active_subscription'] != null) ...[
                                  const SizedBox(height: 12),
                                  Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(Icons.school_rounded, size: 16, color: theme.colorScheme.primary),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                child['active_subscription']['school_name'] ?? 'N/A',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(Icons.route_rounded, size: 16, color: theme.colorScheme.secondary),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                child['active_subscription']['route_name'] ?? 'N/A',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            const Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.green),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Pickup: ${child['active_subscription']['pickup_stop'] ?? 'N/A'}',
                                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            const Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.red),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Drop: ${child['active_subscription']['drop_stop'] ?? 'N/A'}',
                                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (child['active_subscription']['driver_name'] != null ||
                                      child['active_subscription']['attendant_name'] != null) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: theme.brightness == Brightness.dark
                                            ? Colors.grey.shade900.withOpacity(0.5)
                                            : Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          if (child['active_subscription']['driver_name'] != null)
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 12,
                                                    backgroundColor: theme.colorScheme.primaryContainer,
                                                    child: Icon(Icons.person_rounded, size: 12, color: theme.colorScheme.primary),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Text('Driver', style: TextStyle(fontSize: 9, color: Colors.grey)),
                                                        Text(
                                                          child['active_subscription']['driver_name'],
                                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (child['active_subscription']['driver_phone'] != null &&
                                                      (child['active_subscription']['driver_phone'] as String).isNotEmpty)
                                                    IconButton(
                                                      constraints: const BoxConstraints(),
                                                      padding: const EdgeInsets.all(4),
                                                      icon: const Icon(Icons.phone_rounded, color: Colors.green, size: 16),
                                                      onPressed: () => _makePhoneCall(child['active_subscription']['driver_phone']),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          if (child['active_subscription']['driver_name'] != null &&
                                              child['active_subscription']['attendant_name'] != null)
                                            Container(
                                              height: 24,
                                              width: 1,
                                              margin: const EdgeInsets.symmetric(horizontal: 8),
                                              color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                                            ),
                                          if (child['active_subscription']['attendant_name'] != null)
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 12,
                                                    backgroundColor: theme.colorScheme.secondaryContainer,
                                                    child: Icon(Icons.person_outline_rounded, size: 12, color: theme.colorScheme.secondary),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Text('Attendant', style: TextStyle(fontSize: 9, color: Colors.grey)),
                                                        Text(
                                                          child['active_subscription']['attendant_name'],
                                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (child['active_subscription']['attendant_phone'] != null &&
                                                      (child['active_subscription']['attendant_phone'] as String).isNotEmpty)
                                                    IconButton(
                                                      constraints: const BoxConstraints(),
                                                      padding: const EdgeInsets.all(4),
                                                      icon: const Icon(Icons.phone_rounded, color: Colors.green, size: 16),
                                                      onPressed: () => _makePhoneCall(child['active_subscription']['attendant_phone']),
                                                    ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ] else ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey.shade500),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Has no active subscription',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
                if (isDriver && driverTrips.isNotEmpty)
                  _buildHomeTripsSection(theme, driverTrips, 'Driver'),
                if (isAttendant && attendantTrips.isNotEmpty)
                  _buildHomeTripsSection(theme, attendantTrips, 'Attendant'),
                if (childrenList.isEmpty && hasAnyDutySection) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Center(
                      child: TextButton.icon(
                        onPressed: _showAddChildBottomSheet,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add a Child for School Transit'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDriverPage() {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: ApiService.getDriverTrips(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || snapshot.data == null || snapshot.data!['success'] == false) {
          final errorMsg = snapshot.data?['message'] ?? 'Failed to load driver details.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded, size: 64, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(
                    'Error Loading Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    errorMsg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final driver = snapshot.data!['driver'] as Map<String, dynamic>? ?? {};
        final trips = (snapshot.data!['trips'] as List?) ?? [];

        final driverName = driver['name'] ?? 'Driver Name';
        final driverEmail = driver['email'] ?? '';
        final driverMobile = driver['mobile'] ?? '';
        final driverPhoto = driver['profile_photo'] as String?;

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Driver Profile Header Card
                Card(
                  elevation: 4,
                  shadowColor: theme.colorScheme.shadow.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.1)),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primaryContainer.withOpacity(0.2),
                          theme.colorScheme.surface,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: theme.colorScheme.primary,
                          backgroundImage: driverPhoto != null && driverPhoto.isNotEmpty && driverPhoto.startsWith('http')
                              ? NetworkImage(driverPhoto)
                              : null,
                          child: driverPhoto == null || driverPhoto.isEmpty || !driverPhoto.startsWith('http')
                              ? Text(
                                  driverName.isNotEmpty ? driverName[0].toUpperCase() : 'D',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Text(
                                  'Duty Driver',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.primary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                driverName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (driverMobile.isNotEmpty)
                                Row(
                                  children: [
                                    Icon(Icons.phone_android_rounded, size: 14, color: Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Text(
                                      driverMobile,
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                    ),
                                  ],
                                ),
                              if (driverEmail.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(Icons.mail_outline_rounded, size: 14, color: Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        driverEmail,
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 2. Section Title
                Row(
                  children: [
                    Icon(Icons.route_rounded, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Assigned Transit Trips',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${trips.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 3. Trips Card List
                if (trips.isEmpty)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.directions_bus_outlined, size: 48, color: Colors.grey.shade500),
                            const SizedBox(height: 16),
                            const Text(
                              'No trips currently assigned.',
                              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ...trips.map((dynamic t) {
                    final tripName = t['name'] ?? 'N/A';
                    final orgName = t['organization'] ?? 'N/A';
                    final vehicle = t['vehicle'] as Map<String, dynamic>?;
                    final assistant = t['assistant'] as Map<String, dynamic>?;
                    final stops = (t['stops'] as List?) ?? [];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 2,
                      shadowColor: theme.colorScheme.shadow.withOpacity(0.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TripDetailsScreen(trip: t),
                            ),
                          ).then((_) {
                            setState(() {});
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Trip Info Header Row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tripName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          orgName,
                                          style: TextStyle(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      if (LocationService().isTracking && LocationService().activeTripId == t['id'])
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          margin: const EdgeInsets.only(right: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(Icons.sensors_rounded, color: Colors.red, size: 10),
                                              SizedBox(width: 4),
                                              Text(
                                                'LIVE',
                                                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'Active Route',
                                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _isTripToggling
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : Switch.adaptive(
                                              value: LocationService().isTracking && LocationService().activeTripId == t['id'],
                                              activeColor: Colors.green,
                                              onChanged: _isTripToggling
                                                  ? null
                                                  : (val) {
                                                      _toggleTripTracking(
                                                        t['id'] as int,
                                                        LocationService().isTracking && LocationService().activeTripId == t['id'],
                                                      );
                                                    },
                                            ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 24),

                              // Vehicle & Crew Info
                              Row(
                                children: [
                                  // Vehicle Detail
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(Icons.directions_bus_rounded, color: Colors.blue.shade300, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Vehicle',
                                                style: TextStyle(color: Colors.grey, fontSize: 11),
                                              ),
                                              Text(
                                                vehicle != null ? vehicle['registration_number'] ?? 'N/A' : 'N/A',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Attendant/Assistant Detail
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(Icons.support_agent_rounded, color: Colors.teal.shade300, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Attendant',
                                                style: TextStyle(color: Colors.grey, fontSize: 11),
                                              ),
                                              Text(
                                                assistant != null ? assistant['name'] ?? 'N/A' : 'N/A',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    'View stops & children',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttendantPage() {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: ApiService.getAttendantTrips(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || snapshot.data == null || snapshot.data!['success'] == false) {
          final errorMsg = snapshot.data?['message'] ?? 'Failed to load attendant details.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded, size: 64, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(
                    'Error Loading Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    errorMsg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final attendant = snapshot.data!['attendant'] as Map<String, dynamic>? ?? {};
        final trips = (snapshot.data!['trips'] as List?) ?? [];

        final attendantName = attendant['name'] ?? 'Attendant Name';
        final attendantEmail = attendant['email'] ?? '';
        final attendantMobile = attendant['mobile'] ?? '';
        final attendantPhoto = attendant['profile_photo'] as String?;

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Attendant Profile Header Card
                Card(
                  elevation: 4,
                  shadowColor: theme.colorScheme.shadow.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.1)),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primaryContainer.withOpacity(0.2),
                          theme.colorScheme.surface,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: theme.colorScheme.primary,
                          backgroundImage: attendantPhoto != null && attendantPhoto.isNotEmpty && attendantPhoto.startsWith('http')
                              ? NetworkImage(attendantPhoto)
                              : null,
                          child: attendantPhoto == null || attendantPhoto.isEmpty || !attendantPhoto.startsWith('http')
                              ? Text(
                                  attendantName.isNotEmpty ? attendantName[0].toUpperCase() : 'A',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Text(
                                  'Duty Attendant',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.primary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                attendantName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (attendantMobile.isNotEmpty)
                                Row(
                                  children: [
                                    Icon(Icons.phone_android_rounded, size: 14, color: Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Text(
                                      attendantMobile,
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                    ),
                                  ],
                                ),
                              if (attendantEmail.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(Icons.mail_outline_rounded, size: 14, color: Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        attendantEmail,
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 2. Section Title
                Row(
                  children: [
                    Icon(Icons.route_rounded, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Assigned Transit Trips',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${trips.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 3. Trips Card List
                if (trips.isEmpty)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.directions_bus_outlined, size: 48, color: Colors.grey.shade500),
                            const SizedBox(height: 16),
                            const Text(
                              'No trips currently assigned.',
                              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ...trips.map((dynamic t) {
                    final tripName = t['name'] ?? 'N/A';
                    final orgName = t['organization'] ?? 'N/A';
                    final vehicle = t['vehicle'] as Map<String, dynamic>?;
                    final driver = t['driver'] as Map<String, dynamic>?;
                    final stops = (t['stops'] as List?) ?? [];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 2,
                      shadowColor: theme.colorScheme.shadow.withOpacity(0.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TripDetailsScreen(trip: t),
                            ),
                          ).then((_) {
                            setState(() {});
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Trip Info Header Row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tripName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          orgName,
                                          style: TextStyle(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      if (LocationService().isTracking && LocationService().activeTripId == t['id'])
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          margin: const EdgeInsets.only(right: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(Icons.sensors_rounded, color: Colors.red, size: 10),
                                              SizedBox(width: 4),
                                              Text(
                                                'LIVE',
                                                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'Active Route',
                                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _isTripToggling
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : Switch.adaptive(
                                              value: LocationService().isTracking && LocationService().activeTripId == t['id'],
                                              activeColor: Colors.green,
                                              onChanged: _isTripToggling
                                                  ? null
                                                  : (val) {
                                                      _toggleTripTracking(
                                                        t['id'] as int,
                                                        LocationService().isTracking && LocationService().activeTripId == t['id'],
                                                      );
                                                    },
                                            ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 24),

                              // Vehicle & Crew Info
                              Row(
                                children: [
                                  // Vehicle Detail
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(Icons.directions_bus_rounded, color: Colors.blue.shade300, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Vehicle',
                                                style: TextStyle(color: Colors.grey, fontSize: 11),
                                              ),
                                              Text(
                                                vehicle != null ? vehicle['registration_number'] ?? 'N/A' : 'N/A',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Driver Detail
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(Icons.badge_rounded, color: Colors.teal.shade300, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Driver',
                                                style: TextStyle(color: Colors.grey, fontSize: 11),
                                              ),
                                              Text(
                                                driver != null ? driver['name'] ?? 'N/A' : 'N/A',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    'View stops & children',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrganizationPage() {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: ApiService.getOrganization(organizationId: _selectedOrganizationId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || snapshot.data == null || snapshot.data!['success'] == false) {
          final errorMsg = snapshot.data?['message'] ?? 'Failed to load organization details.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded, size: 64, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(
                    'Error Loading Organization',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    errorMsg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final org = snapshot.data!['organization'] as Map<String, dynamic>;
        final orgName = org['name'] ?? 'N/A';
        final orgEmail = org['email'] ?? 'N/A';
        final orgPhone = org['number'] ?? 'N/A';
        final orgAddress = org['address'] ?? 'N/A';
        final orgLogo = org['logo'] as String?;

        final vehiclesCount = org['vehicles_count']?.toString() ?? '0';
        final driversCount = org['drivers_count']?.toString() ?? '0';
        final attendantsCount = org['attendants_count']?.toString() ?? '0';
        final routesCount = org['routes_count']?.toString() ?? '0';

        final vehicles = (org['vehicles'] as List?) ?? [];
        final drivers = (org['drivers'] as List?) ?? [];
        final attendants = (org['attendants'] as List?) ?? [];
        final trips = (org['trips'] as List?) ?? [];
        final allOrgs = (snapshot.data!['organizations'] as List?) ?? [];

        final liveRoutes = [];
        for (var t in trips) {
          final routesList = (t['routes'] as List?) ?? [];
          for (var r in routesList) {
            if (r['is_tracking'] == true) {
              liveRoutes.add({
                'trip_id': t['id'],
                'trip_name': t['name'],
                ...r,
              });
            }
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (allOrgs.length > 1) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedOrganizationId ?? org['id'],
                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: theme.colorScheme.primary),
                        isExpanded: true,
                        dropdownColor: theme.colorScheme.surface,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        items: allOrgs.map<DropdownMenuItem<int>>((dynamic o) {
                          return DropdownMenuItem<int>(
                            value: o['id'] as int,
                            child: Text(o['name'] ?? 'N/A'),
                          );
                        }).toList(),
                        onChanged: (int? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedOrganizationId = newValue;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
              // Organization Header Card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        backgroundImage: orgLogo != null && orgLogo.isNotEmpty && orgLogo.startsWith('http') ? NetworkImage(orgLogo) : null,
                        child: orgLogo == null || orgLogo.isEmpty || !orgLogo.startsWith('http')
                            ? Icon(Icons.business_rounded, size: 36, color: theme.colorScheme.onPrimaryContainer)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              orgName,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.email_outlined, size: 14, color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    orgEmail,
                                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.phone_outlined, size: 14, color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  orgPhone,
                                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Address Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on_outlined, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        orgAddress,
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Tab Switching Segmented Control
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? Colors.grey.shade900
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    _buildOrgTabItem(0, 'Crew', '${drivers.length + attendants.length}', Icons.badge_rounded, theme),
                    _buildOrgTabItem(1, 'Vehicles', '${vehicles.length}', Icons.directions_bus_rounded, theme),
                    _buildOrgTabItem(2, 'Trips', '${trips.length}', Icons.route_rounded, theme),
                    _buildOrgTabItem(3, 'Live', '${liveRoutes.length}', Icons.sensors_rounded, theme),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Active Tab Content
              if (_activeOrgTabIndex == 0) ...[
                _buildCrewTab(org['id'] as int, drivers, attendants, theme),
              ] else if (_activeOrgTabIndex == 1) ...[
                _buildVehiclesTab(org['id'] as int, vehicles, theme),
              ] else if (_activeOrgTabIndex == 2) ...[
                _buildTripsTab(org['id'] as int, trips, vehicles, drivers, attendants, theme),
              ] else ...[
                _buildLiveTab(org['id'] as int, liveRoutes, theme),
              ],
              const SizedBox(height: 60), // Extra spacing for bottom notched bar
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrgTabItem(int index, String label, String count, IconData icon, ThemeData theme) {
    final isSelected = _activeOrgTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeOrgTabIndex = index;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.onPrimary.withOpacity(0.2)
                          : theme.colorScheme.primaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      count,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCrewTab(int orgId, List<dynamic> drivers, List<dynamic> attendants, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _buildSectionHeader(theme, 'Drivers (${drivers.length})', Icons.badge_rounded),
            ),
            IconButton(
              icon: Icon(Icons.add_circle_outline_rounded, color: theme.colorScheme.primary, size: 24),
              onPressed: () => _showHireCrewDialog(orgId: orgId, theme: theme),
              tooltip: 'Add Crew Member',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (drivers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 4),
            child: Text('No drivers registered.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          )
        else
          ...drivers.map((d) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
                    child: Icon(Icons.person_rounded, color: theme.colorScheme.primary, size: 20),
                  ),
                  title: Text(
                    d['driver_name'] ?? 'N/A',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(d['driver_mobile'] ?? d['driver_email'] ?? 'Driver'),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error, size: 20),
                    onPressed: () => _showDeleteCrewConfirmation(
                      orgId: orgId,
                      type: 'driver',
                      crewId: d['id'] as int,
                      name: d['driver_name'] ?? 'N/A',
                      theme: theme,
                    ),
                    tooltip: 'Remove Driver',
                  ),
                ),
              )),
        const SizedBox(height: 16),
        _buildSectionHeader(theme, 'Attendants (${attendants.length})', Icons.supervised_user_circle_rounded),
        const SizedBox(height: 8),
        if (attendants.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 4),
            child: Text('No attendants registered.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          )
        else
          ...attendants.map((a) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.secondaryContainer.withOpacity(0.3),
                    child: Icon(Icons.person_outline_rounded, color: theme.colorScheme.secondary, size: 20),
                  ),
                  title: Text(
                    a['attendant_name'] ?? 'N/A',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(a['attendant_mobile'] ?? a['attendant_email'] ?? 'Attendant'),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error, size: 20),
                    onPressed: () => _showDeleteCrewConfirmation(
                      orgId: orgId,
                      type: 'attendant',
                      crewId: a['id'] as int,
                      name: a['attendant_name'] ?? 'N/A',
                      theme: theme,
                    ),
                    tooltip: 'Remove Attendant',
                  ),
                ),
              )),
      ],
    );
  }

  void _showHireCrewDialog({required int orgId, required ThemeData theme}) {
    final identityController = TextEditingController();
    String selectedRole = 'driver'; // driver or attendant
    String? errorText;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Add Crew Member',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Link a registered user to your organization as a Pilot/Driver or travel assistant.',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (errorText != null) ...[
                  Text(
                    errorText!,
                    style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: identityController,
                  decoration: const InputDecoration(
                    labelText: 'User Email or Mobile',
                    hintText: 'e.g. pilot@school.com or 9876543210',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Crew Role',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(
                      value: 'driver',
                      label: Text('DRIVER'),
                      icon: Icon(Icons.directions_bus_rounded),
                    ),
                    ButtonSegment<String>(
                      value: 'attendant',
                      label: Text('ATTENDANT'),
                      icon: Icon(Icons.supervised_user_circle_rounded),
                    ),
                  ],
                  selected: <String>{selectedRole},
                  onSelectionChanged: (Set<String> newSelection) {
                    setDialogState(() {
                      selectedRole = newSelection.first;
                    });
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final identity = identityController.text.trim();

                          if (identity.isEmpty) {
                            setDialogState(() {
                              errorText = 'Email or mobile is required.';
                            });
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                            errorText = null;
                          });

                          final res = await ApiService.hireCrew(
                            orgId: orgId,
                            identity: identity,
                            type: selectedRole,
                          );

                          if (res['success'] == true) {
                            Navigator.pop(context);
                            setState(() {});
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(res['message'] ?? 'Crew member hired successfully.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else {
                            setDialogState(() {
                              isSaving = false;
                              errorText = res['message'] ?? 'Failed to hire crew member.';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('HIRE CREW MEMBER'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteCrewConfirmation({
    required int orgId,
    required String type,
    required int crewId,
    required String name,
    required ThemeData theme,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${type == 'driver' ? 'Driver' : 'Attendant'}'),
        content: Text('Are you sure you want to remove crew member $name? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final res = await ApiService.unhireCrew(orgId: orgId, type: type, id: crewId);
              if (res['success'] == true) {
                setState(() {});
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(res['message'] ?? 'Crew member removed successfully.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(res['message'] ?? 'Failed to remove crew member.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Widget _buildVehiclesTab(int orgId, List<dynamic> vehicles, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _buildSectionHeader(theme, 'Registered Vehicles (${vehicles.length})', Icons.directions_bus_rounded),
            ),
            IconButton(
              icon: Icon(Icons.add_circle_outline_rounded, color: theme.colorScheme.primary, size: 24),
              onPressed: () => _showVehicleDialog(orgId: orgId, theme: theme),
              tooltip: 'Add Vehicle',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (vehicles.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 4),
            child: Text('No vehicles registered.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          )
        else
          ...vehicles.map((v) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
                    child: Icon(Icons.directions_bus_rounded, color: theme.colorScheme.primary, size: 20),
                  ),
                  title: Text(
                    v['registration_number'] ?? 'N/A',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(v['type'] ?? 'Vehicle'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit_outlined, color: theme.colorScheme.primary, size: 20),
                        onPressed: () => _showVehicleDialog(orgId: orgId, vehicle: v, theme: theme),
                        tooltip: 'Edit',
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error, size: 20),
                        onPressed: () => _showDeleteVehicleConfirmation(
                          orgId: orgId,
                          vehicleId: v['id'] as int,
                          registrationNumber: v['registration_number'] ?? 'N/A',
                          theme: theme,
                        ),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  void _showVehicleDialog({required int orgId, Map<String, dynamic>? vehicle, required ThemeData theme}) {
    final isEditing = vehicle != null;
    final regController = TextEditingController(text: vehicle?['registration_number']);
    final vehicleTypes = ['Bus', 'Rickshaw', 'Van', 'Tempo', 'Car'];
    final typeVal = vehicle?['type'] as String?;
    final typesList = List<String>.from(vehicleTypes);
    if (typeVal != null && typeVal.isNotEmpty && !typesList.contains(typeVal)) {
      typesList.add(typeVal);
    }
    String selectedType = typeVal != null && typeVal.isNotEmpty ? typeVal : 'Bus';
    String? errorText;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isEditing ? 'Edit Vehicle' : 'Add Vehicle',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (errorText != null) ...[
                  Text(
                    errorText!,
                    style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: regController,
                  decoration: const InputDecoration(
                    labelText: 'Registration Number',
                    hintText: 'e.g. MH05AT0599',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Type',
                    border: OutlineInputBorder(),
                  ),
                  items: typesList.map((type) {
                    return DropdownMenuItem<String>(
                      value: type,
                      child: Text(type),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedType = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final regNum = regController.text.trim();

                          if (regNum.isEmpty) {
                            setDialogState(() {
                              errorText = 'Registration Number is required.';
                            });
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                            errorText = null;
                          });

                          final res = isEditing
                              ? await ApiService.updateVehicle(
                                  orgId: orgId,
                                  vehicleId: vehicle['id'] as int,
                                  registrationNumber: regNum,
                                  type: selectedType,
                                )
                              : await ApiService.addVehicle(
                                  orgId: orgId,
                                  registrationNumber: regNum,
                                  type: selectedType,
                                );

                          if (res['success'] == true) {
                            Navigator.pop(context);
                            setState(() {});
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(res['message'] ?? 'Saved successfully.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else {
                            setDialogState(() {
                              isSaving = false;
                              errorText = res['message'] ?? 'Failed to save vehicle details.';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(isEditing ? 'Save Changes' : 'Add Vehicle'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteVehicleConfirmation({required int orgId, required int vehicleId, required String registrationNumber, required ThemeData theme}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Vehicle'),
        content: Text('Are you sure you want to delete vehicle $registrationNumber? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final res = await ApiService.deleteVehicle(orgId: orgId, vehicleId: vehicleId);
              if (res['success'] == true) {
                setState(() {});
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(res['message'] ?? 'Vehicle deleted successfully.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(res['message'] ?? 'Failed to delete vehicle.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildTripsTab(
    int orgId,
    List<dynamic> trips,
    List<dynamic> vehicles,
    List<dynamic> drivers,
    List<dynamic> attendants,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'Organization Trips (${trips.length})', Icons.route_rounded),
        const SizedBox(height: 8),
        if (trips.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 4),
            child: Text('No trips scheduled.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          )
        else
          ...trips.map((t) {
            final routes = (t['routes'] as List?) ?? [];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
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
                            t['name'] ?? 'Trip Name',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.route_rounded, size: 12, color: theme.colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                '${routes.length} Route(s)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (routes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      ...routes.map((r) {
                        final isLive = r['is_tracking'] == true;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark
                                ? Colors.grey.shade900.withOpacity(0.5)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                            ),
                          ),
                          child: InkWell(
                            onTap: () => _showAssignLogisticsDialog(
                              orgId: orgId,
                              tripId: t['id'] as int,
                              route: r,
                              vehicles: vehicles,
                              drivers: drivers,
                              attendants: attendants,
                              theme: theme,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          r['route_name'] ?? 'Route',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(Icons.edit_outlined, size: 16, color: theme.colorScheme.primary),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isLive ? Colors.green.withOpacity(0.15) : Colors.grey.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: isLive ? Colors.green : Colors.grey,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              isLive ? 'LIVE' : 'OFFLINE',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: isLive ? Colors.green : Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.directions_bus_rounded, size: 14, color: theme.colorScheme.primary),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Vehicle: ${r['vehicle_number']}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.person_rounded, size: 14, color: theme.colorScheme.secondary),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Driver: ${r['driver_name']}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      if (r['driver_mobile'] != null && r['driver_mobile'].toString().isNotEmpty && r['driver_name'] != 'N/A')
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () async {
                                              final url = Uri.parse('tel:${r['driver_mobile']}');
                                              if (await canLaunchUrl(url)) {
                                                await launchUrl(url);
                                              }
                                            },
                                            borderRadius: BorderRadius.circular(16),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4.0),
                                              child: Icon(Icons.call, size: 16, color: theme.colorScheme.primary),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.person_outline_rounded, size: 14, color: theme.colorScheme.secondary),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Attendant: ${r['attendant_name']}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      if (r['attendant_mobile'] != null && r['attendant_mobile'].toString().isNotEmpty && r['attendant_name'] != 'N/A')
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () async {
                                              final url = Uri.parse('tel:${r['attendant_mobile']}');
                                              if (await canLaunchUrl(url)) {
                                                await launchUrl(url);
                                              }
                                            },
                                            borderRadius: BorderRadius.circular(16),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4.0),
                                              child: Icon(Icons.call, size: 16, color: theme.colorScheme.primary),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  void _showAssignLogisticsDialog({
    required int orgId,
    required int tripId,
    required Map<String, dynamic> route,
    required List<dynamic> vehicles,
    required List<dynamic> drivers,
    required List<dynamic> attendants,
    required ThemeData theme,
  }) {
    int? selectedVehicleId = route['vehicle_id'] as int?;
    int? selectedDriverId = route['driver_id'] as int?;
    int? selectedAttendantId = route['attendant_id'] as int?;

    if (selectedVehicleId != null && !vehicles.any((v) => v['id'] == selectedVehicleId)) {
      selectedVehicleId = null;
    }
    if (selectedDriverId != null && !drivers.any((d) => d['id'] == selectedDriverId)) {
      selectedDriverId = null;
    }
    if (selectedAttendantId != null && !attendants.any((a) => a['id'] == selectedAttendantId)) {
      selectedAttendantId = null;
    }

    String? errorText;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Assign Trip Roster',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Route: ${route['route_name'] ?? 'N/A'}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (errorText != null) ...[
                  Text(
                    errorText!,
                    style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                // Vehicle selection
                DropdownButtonFormField<int?>(
                  value: selectedVehicleId,
                  decoration: const InputDecoration(
                    labelText: 'Select Vehicle',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('None (Unassigned)'),
                    ),
                    ...vehicles.map((v) => DropdownMenuItem<int?>(
                          value: v['id'] as int?,
                          child: Text('${v['registration_number']} (${v['type']})'),
                        )),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedVehicleId = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Driver selection
                DropdownButtonFormField<int?>(
                  value: selectedDriverId,
                  decoration: const InputDecoration(
                    labelText: 'Select Driver',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('None (Unassigned)'),
                    ),
                    ...drivers.map((d) => DropdownMenuItem<int?>(
                          value: d['id'] as int?,
                          child: Text(d['driver_name'] ?? 'N/A'),
                        )),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedDriverId = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Attendant selection
                DropdownButtonFormField<int?>(
                  value: selectedAttendantId,
                  decoration: const InputDecoration(
                    labelText: 'Select Attendant',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('None (Unassigned)'),
                    ),
                    ...attendants.map((a) => DropdownMenuItem<int?>(
                          value: a['id'] as int?,
                          child: Text(a['attendant_name'] ?? 'N/A'),
                        )),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedAttendantId = value;
                    });
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() {
                            isSaving = true;
                            errorText = null;
                          });

                          final res = await ApiService.assignTripLogistics(
                            orgId: orgId,
                            tripId: tripId,
                            routeId: route['route_id'] as int,
                            vehicleId: selectedVehicleId,
                            driverId: selectedDriverId,
                            attendantId: selectedAttendantId,
                          );

                          if (res['success'] == true) {
                            Navigator.pop(context);
                            setState(() {});
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(res['message'] ?? 'Roster assigned successfully.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else {
                            setDialogState(() {
                              isSaving = false;
                              errorText = res['message'] ?? 'Failed to save assignments.';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('SAVE ASSIGNMENTS'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveTab(int orgId, List<dynamic> liveRoutes, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'Active Live Routes (${liveRoutes.length})', Icons.sensors_rounded),
        const SizedBox(height: 8),
        if (liveRoutes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0, horizontal: 4),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.sensors_off_rounded, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'No active routes right now.',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
          )
        else
          ...liveRoutes.map((r) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
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
                            r['route_name'] ?? 'Route',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Trip: ${r['trip_name'] ?? 'N/A'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.directions_bus_rounded, size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Vehicle: ${r['vehicle_number']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person_rounded, size: 14, color: theme.colorScheme.secondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Driver: ${r['driver_name']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (r['driver_mobile'] != null && r['driver_mobile'].toString().isNotEmpty && r['driver_name'] != 'N/A')
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () async {
                                final url = Uri.parse('tel:${r['driver_mobile']}');
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url);
                                }
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(Icons.call, size: 16, color: theme.colorScheme.primary),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person_outline_rounded, size: 14, color: theme.colorScheme.secondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Attendant: ${r['attendant_name']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (r['attendant_mobile'] != null && r['attendant_mobile'].toString().isNotEmpty && r['attendant_name'] != 'N/A')
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () async {
                                final url = Uri.parse('tel:${r['attendant_mobile']}');
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url);
                                }
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(Icons.call, size: 16, color: theme.colorScheme.primary),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/child-track',
                          arguments: {
                            'is_admin_mode': true,
                            'org_id': orgId,
                            'trip_id': r['trip_id'] as int,
                            'route_id': r['route_id'] as int,
                            'route_name': r['route_name'] ?? 'Route',
                          },
                        );
                      },
                      icon: const Icon(Icons.map_rounded, size: 16),
                      label: const Text('TRACK LIVE ON MAP'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildStatCard(ThemeData theme, String label, String value, IconData icon) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withOpacity(0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 22),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchPage() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search TextField
          TextField(
            controller: _searchQueryController,
            onChanged: (val) => _performSearch(val),
            decoration: InputDecoration(
              hintText: 'Search organizations by name, email, or address...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQueryController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchQueryController.clear();
                        _performSearch('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: theme.colorScheme.surface,
            ),
          ),
          const SizedBox(height: 16),
          
          if (_isSearching)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_searchError.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: Text(
                  _searchError,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Organizations Found',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text(
                    '${_searchResults.length} results',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _searchResults.isEmpty
                  ? const Center(
                      child: Text(
                        'No organizations found matching your search.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      controller: _searchScrollController,
                      padding: const EdgeInsets.only(left: 0, right: 0, bottom: 100),
                      itemCount: _searchResults.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _searchResults.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 16.0),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        final org = _searchResults[index];
                        final name = org['name'] ?? 'N/A';
                        final address = org['address'] ?? 'N/A';
                        final logo = org['logo'] as String?;

                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                            ),
                          ),
                          child: InkWell(
                            onTap: () {
                              Navigator.pushNamed(
                                context,
                                '/organization-profile',
                                arguments: org,
                              );
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: theme.colorScheme.primaryContainer,
                                backgroundImage: logo != null && logo.isNotEmpty && logo.startsWith('http') ? NetworkImage(logo) : null,
                                child: logo == null || logo.isEmpty || !logo.startsWith('http')
                                    ? Icon(
                                        Icons.business_rounded,
                                        size: 20,
                                        color: theme.colorScheme.onPrimaryContainer,
                                      )
                                    : null,
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                address,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.grey.shade400,
                              ),
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

  Widget _buildProfilePage(ThemeData theme, String userName, String userEmail) {
    final userMobile = _user != null ? _user!['mobile'] ?? '' : '';
    final userPhoto = _user != null ? _user!['profile_photo'] : null;

    return ListView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 100),
      children: [

        Center(
          child: Column(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: userPhoto != null && userPhoto.isNotEmpty && userPhoto.startsWith('http') ? NetworkImage(userPhoto) : null,
                    child: userPhoto == null || userPhoto.isEmpty || !userPhoto.startsWith('http')
                        ? Text(
                            userName.isNotEmpty ? userName[0] : 'U',
                            style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.primary,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                        onPressed: () => _showChangePhotoBottomSheet(theme),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                userName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                userEmail,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Card(
          elevation: 0,
          color: theme.colorScheme.surface,
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
                    const Text(
                      'Personal Information',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      onPressed: () => _showEditProfileDialog(theme),
                    ),
                  ],
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Name', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  subtitle: Text(userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Email Address', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  subtitle: Text(userEmail, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone_outlined),
                  title: const Text('Mobile Number', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  subtitle: Text(userMobile, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
          ),
          child: ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showChangePasswordDialog(theme),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.shade50.withOpacity(0.6),
            border: Border.all(color: Colors.red.shade200.withOpacity(0.8)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade800),
                  const SizedBox(width: 8),
                  Text(
                    'Danger Zone',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Deleting your account is permanent and cannot be undone. All child profiles, schedules, and settings will be permanently lost.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade800,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showDeleteAccountDialog(theme),
                icon: const Icon(Icons.delete_forever_rounded),
                label: const Text('Delete Account'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDrawerItem({
    required int index,
    required IconData icon,
    required String label,
    required ThemeData theme,
  }) {
    final isSelected = _currentIndex == index;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? theme.colorScheme.primary.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 5,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
            ),
            Expanded(
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 11, right: 16),
                 leading: Icon(
                  icon,
                  color: isSelected
                      ? (theme.brightness == Brightness.dark ? Colors.blue.shade300 : theme.colorScheme.primary)
                      : (theme.brightness == Brightness.dark ? Colors.white70 : theme.colorScheme.primary.withOpacity(0.7)),
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? (theme.brightness == Brightness.dark ? Colors.blue.shade300 : theme.colorScheme.primary)
                        : theme.colorScheme.onSurface,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  _onTabChanged(index);
                  Navigator.pop(context); // Close the drawer
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final isSelected = _currentIndex == index;
    final color = isSelected ? theme.colorScheme.primary : theme.disabledColor;
    return Expanded(
      child: InkWell(
        onTap: () {
          _onTabChanged(index);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userName = _user != null ? _user!['name'] ?? 'User' : 'User';
    final userEmail = _user != null ? _user!['email'] ?? '' : '';
    final userPhoto = _user != null ? _user!['profile_photo'] as String? : null;

    final roles = _user != null && _user!['roles'] != null
        ? List<String>.from(_user!['roles'])
        : <String>[];

    final isDriver = roles.contains('Driver');
    final isAttendant = roles.contains('Attendant');
    final isOrganization = roles.contains('Organization');

    Widget activeBody;
    switch (_currentIndex) {
      case 0:
        activeBody = _buildGroupPage();
        break;
      case 1:
        activeBody = _buildParentPage();
        break;
      case 2:
        activeBody = _buildHomePage(theme, userName, userEmail);
        break;
      case 3:
        activeBody = _buildOrganizationPage();
        break;
      case 4:
        activeBody = _buildProfilePage(theme, userName, userEmail);
        break;
      case 5:
        activeBody = _buildSearchPage();
        break;
      case 6:
        activeBody = _buildDriverPage();
        break;
      case 7:
        activeBody = _buildAttendantPage();
        break;
      default:
        activeBody = _buildHomePage(theme, userName, userEmail);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.brightness == Brightness.dark ? const Color(0xFF1E2A38) : theme.colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: false,
        title: Text(
          _currentIndex == 0
              ? 'Groups'
              : _currentIndex == 1
                  ? 'Parent Panel'
                  : _currentIndex == 3
                      ? 'Organization'
                      : _currentIndex == 4
                          ? 'Profile'
                          : _currentIndex == 5
                              ? 'Search'
                              : _currentIndex == 6
                                  ? 'Drivers'
                                  : _currentIndex == 7
                                      ? 'Attendants'
                                      : widget.title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: theme.colorScheme.onPrimary,
                backgroundImage: userPhoto != null && userPhoto.isNotEmpty && userPhoto.startsWith('http') ? NetworkImage(userPhoto) : null,
                child: userPhoto == null || userPhoto.isEmpty || !userPhoto.startsWith('http')
                    ? Text(
                        userName.isNotEmpty ? userName[0] : 'U',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : null,
              ),
              accountName: Text(
                userName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              accountEmail: Text(
                userEmail,
                style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.8)),
              ),
            ),
            Expanded(
              child: Material(
                color: theme.colorScheme.primary.withOpacity(0.02),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    _buildDrawerItem(
                      index: 2,
                      icon: Icons.home_rounded,
                      label: 'Home',
                      theme: theme,
                    ),
                    _buildDrawerItem(
                      index: 1,
                      icon: Icons.supervisor_account_rounded,
                      label: 'Parent',
                      theme: theme,
                    ),
                    _buildDrawerItem(
                      index: 0,
                      icon: Icons.group_rounded,
                      label: 'Group',
                      theme: theme,
                    ),
                    if (isOrganization)
                      _buildDrawerItem(
                        index: 3,
                        icon: Icons.business_rounded,
                        label: 'Organization',
                        theme: theme,
                      ),
                    if (isDriver)
                      _buildDrawerItem(
                        index: 6,
                        icon: Icons.badge_rounded,
                        label: 'Driver',
                        theme: theme,
                      ),
                    if (isAttendant)
                      _buildDrawerItem(
                        index: 7,
                        icon: Icons.assignment_ind_rounded,
                        label: 'Attendant',
                        theme: theme,
                      ),
                    _buildDrawerItem(
                      index: 5,
                      icon: Icons.search_rounded,
                      label: 'Search',
                      theme: theme,
                    ),
                    _buildDrawerItem(
                      index: 4,
                      icon: Icons.person_rounded,
                      label: 'Profile',
                      theme: theme,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.logout_rounded, color: Colors.red),
                      title: const Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      onTap: () {
                        Navigator.pop(context);
                        _handleLogout();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      body: activeBody,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: SizedBox(
          height: 60.0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTabItem(index: 1, icon: Icons.supervisor_account_rounded, label: 'Parent'),
              _buildTabItem(index: 0, icon: Icons.group_rounded, label: 'Group'),
              const SizedBox(width: 48), // Spacer for center FAB
              _buildTabItem(index: 5, icon: Icons.search_rounded, label: 'Search'),
              _buildTabItem(index: 4, icon: Icons.person_rounded, label: 'Profile'),
            ],
          ),
        ),
      ),
      floatingActionButton: Container(
        height: 68,
        width: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.2),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          heroTag: 'fab_main_center_docked',
          elevation: 0,
          highlightElevation: 0,
          shape: const CircleBorder(),
          backgroundColor: theme.colorScheme.surface,
          onPressed: () {
            setState(() {
              _currentIndex = 2; // Home
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(6.0),
            child: RotationTransition(
              turns: _rotationController,
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

class _AddChildBottomSheet extends StatefulWidget {
  final VoidCallback onSaved;
  final Map<String, dynamic>? child;

  const _AddChildBottomSheet({Key? key, required this.onSaved, this.child}) : super(key: key);

  @override
  State<_AddChildBottomSheet> createState() => _AddChildBottomSheetState();
}

class _AddChildBottomSheetState extends State<_AddChildBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  DateTime? _selectedDate;
  String _gender = 'Male';
  String _relationshipType = 'Mother';
  File? _imageFile;
  String? _imageBase64;
  bool _isSaving = false;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    if (widget.child != null) {
      _nameController.text = widget.child!['name'] ?? '';
      _gender = widget.child!['gender'] ?? 'Male';
      _relationshipType = widget.child!['relationship_type'] ?? 'Mother';
      final dobStr = widget.child!['dob'] as String?;
      if (dobStr != null && dobStr.isNotEmpty) {
        try {
          _selectedDate = DateTime.parse(dobStr);
        } catch (_) {}
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);
        final bytes = await file.readAsBytes();
        final base64Str = 'data:image/${pickedFile.path.split('.').last};base64,${base64Encode(bytes)}';
        setState(() {
          _imageFile = file;
          _imageBase64 = base64Str;
        });
      }
    } catch (e) {
      setState(() {
        _errorMsg = 'Error picking image: $e';
      });
    }
  }

  void _showImagePickerOptions() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Child Photo Source',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
                child: Icon(Icons.camera_alt_rounded, color: theme.colorScheme.primary),
              ),
              title: const Text('Camera', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Take a new photo with camera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
                child: Icon(Icons.photo_library_rounded, color: theme.colorScheme.primary),
              ),
              title: const Text('From Phone', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Choose an existing photo from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(now.year - 8),
      firstDate: DateTime(now.year - 18),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Theme.of(context).colorScheme.onPrimary,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  Future<void> _saveChild() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMsg = '';
    });

    final dobFormatted = _selectedDate != null
        ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
        : null;

    final response = widget.child == null
        ? await ApiService.addChild(
            name: _nameController.text.trim(),
            dob: dobFormatted,
            gender: _gender,
            photoBase64: _imageBase64,
            relationshipType: _relationshipType,
          )
        : await ApiService.updateChild(
            widget.child!['id'],
            name: _nameController.text.trim(),
            dob: dobFormatted,
            gender: _gender,
            photoBase64: _imageBase64,
            relationshipType: _relationshipType,
          );

    if (mounted) {
      setState(() {
        _isSaving = false;
      });

      if (response['success'] == true) {
        widget.onSaved();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Child saved successfully.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _errorMsg = response['message'] ?? 'Failed to save child details.';
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: media.viewInsets.bottom + media.padding.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.child == null ? 'Add Child Profile' : 'Edit Child Profile',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Photo Uploader circle
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
                      backgroundImage: _imageFile != null
                          ? FileImage(_imageFile!)
                          : (widget.child != null && widget.child!['photo'] != null && widget.child!['photo'].toString().isNotEmpty && widget.child!['photo'].toString().startsWith('http'))
                              ? NetworkImage(widget.child!['photo']) as ImageProvider
                              : null,
                      child: _imageFile == null && (widget.child == null || widget.child!['photo'] == null || widget.child!['photo'].toString().isEmpty || !widget.child!['photo'].toString().startsWith('http'))
                          ? Icon(
                              Icons.face_rounded,
                              size: 56,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Material(
                        color: theme.colorScheme.primary,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: IconButton(
                          icon: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                          onPressed: _showImagePickerOptions,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_errorMsg.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorMsg,
                    style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Name Field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: "Child's Name",
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter the name';
                  }
                  return null;
                },
              ),

              // Gender chips
              Text(
                'Gender',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['Male', 'Female', 'Other'].map((g) {
                  final isSel = _gender == g;
                  return ChoiceChip(
                    label: Text(g),
                    selected: isSel,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _gender = g;
                        });
                      }
                    },
                    selectedColor: theme.colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                      color: isSel ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _relationshipType,
                decoration: InputDecoration(
                  labelText: 'Your Relationship to Child',
                  prefixIcon: const Icon(Icons.people_outline_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: ['Mother', 'Father', 'Guardian', 'Other'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    if (value != null) {
                      _relationshipType = value;
                    }
                  });
                },
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveChild,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        widget.child == null ? 'Save Profile' : 'Update Profile',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
