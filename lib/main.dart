import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final loggedIn = await ApiService.isLoggedIn();
  runApp(MyApp(loggedIn: loggedIn));
}

class MyApp extends StatelessWidget {
  final bool loggedIn;

  const MyApp({super.key, required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FleetFind',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      initialRoute: loggedIn ? '/home' : '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const MyHomePage(title: 'FleetFind Operations Board'),
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
  int _counter = 0;
  Map<String, dynamic>? _user;
  int _currentIndex = 2; // Default to Home page in the center
  late AnimationController _rotationController;

  final TextEditingController _searchQueryController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  String _searchError = '';
  int? _selectedOrganizationId;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    _performSearch('');
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _searchQueryController.dispose();
    super.dispose();
  }

  void _performSearch(String query) async {
    setState(() {
      _isSearching = true;
      _searchError = '';
    });
    try {
      final res = await ApiService.searchOrganizations(query);
      if (res['success'] == true) {
        setState(() {
          _searchResults = res['organizations'] ?? [];
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

  Future<void> _loadUser() async {
    final user = await ApiService.getUser();
    if (user != null) {
      setState(() {
        _user = user;
      });
    }
  }

  void _showEditProfileDialog(ThemeData theme) {
    final nameController = TextEditingController(text: _user?['name'] ?? '');
    final emailController = TextEditingController(text: _user?['email'] ?? '');
    final mobileController = TextEditingController(text: _user?['mobile'] ?? '');

    String? dialogError;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Profile Info'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dialogError != null) ...[
                  Text(dialogError!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
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
      ),
    );
  }

  void _showChangePasswordDialog(ThemeData theme) {
    final currentPasswordController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    String? dialogError;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dialogError != null) ...[
                  Text(dialogError!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'Are you absolutely sure you want to delete your account? This action is permanent and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
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
    );
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Transit Groups & Routes',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildListCard(
          title: 'Primary School Shift A',
          subtitle: 'Route A1 • 15 Stops • 28 Students',
          icon: Icons.school_rounded,
        ),
        _buildListCard(
          title: 'High School Route B',
          subtitle: 'Route B2 • 10 Stops • 19 Students',
          icon: Icons.directions_bus_rounded,
        ),
      ],
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
                      'Registered Children & Schedule',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage school transit registration profiles for your children.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
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
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 30,
                                    backgroundColor: theme.colorScheme.primaryContainer,
                                    backgroundImage: childPhoto != null && childPhoto.isNotEmpty && childPhoto.startsWith('http')
                                        ? NetworkImage(childPhoto)
                                        : null,
                                    child: childPhoto == null || childPhoto.isEmpty || !childPhoto.startsWith('http')
                                        ? Icon(
                                            Icons.face_rounded,
                                            size: 32,
                                            color: theme.colorScheme.primary,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          child['name'] ?? 'N/A',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            if (ageInfo.isNotEmpty) ...[
                                              Text(
                                                ageInfo,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            if (gender != null && gender.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: theme.colorScheme.primaryContainer.withOpacity(0.4),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  gender,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: theme.colorScheme.primary,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        if (dobStr != null && dobStr.isNotEmpty)
                                          Text(
                                            'DOB: $dobStr',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade600),
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _showEditChildBottomSheet(child);
                                      } else if (value == 'delete') {
                                        _showDeleteChildDialog(child);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_rounded, size: 20),
                                            SizedBox(width: 8),
                                            Text('Edit Profile'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_rounded, color: Colors.red, size: 20),
                                            SizedBox(width: 8),
                                            Text('Delete Profile', style: TextStyle(color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
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
        content: Text('Are you sure you want to delete ${child['name']}\'s profile? This action cannot be undone.'),
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

  Widget _buildHomePage(ThemeData theme, String userName, String userEmail) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_bus_rounded,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Welcome, $userName!',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (userEmail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                userEmail,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 32),
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _incrementCounter,
              icon: const Icon(Icons.add),
              label: const Text('Increment Counter'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverPage() {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: ApiService.getOrganization(organizationId: _selectedOrganizationId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || snapshot.data == null || snapshot.data!['success'] == false) {
          final errorMsg = snapshot.data?['message'] ?? 'Failed to load drivers.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded, size: 64, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(
                    'Error Loading Drivers',
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
        final drivers = (org['drivers'] as List?) ?? [];
        final allOrgs = (snapshot.data!['organizations'] as List?) ?? [];

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
              Text(
                'Registered Organization Drivers',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'List of professional drivers configured for transit routes under ${org['name']}.',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              if (drivers.isEmpty)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(
                      child: Text(
                        'No drivers registered under this organization.',
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                )
              else
                ...drivers.map((d) => Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
                          child: Icon(Icons.badge_rounded, color: theme.colorScheme.primary, size: 20),
                        ),
                        title: Text(
                          d['driver_name'] ?? 'N/A',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('License: ${d['license'] ?? 'N/A'}'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttendantPage() {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: ApiService.getOrganization(organizationId: _selectedOrganizationId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || snapshot.data == null || snapshot.data!['success'] == false) {
          final errorMsg = snapshot.data?['message'] ?? 'Failed to load attendants.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded, size: 64, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(
                    'Error Loading Attendants',
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
        final attendants = (org['attendants'] as List?) ?? [];
        final allOrgs = (snapshot.data!['organizations'] as List?) ?? [];

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
              Text(
                'Registered Organization Attendants',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'List of professional transit attendants registered under ${org['name']}.',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              if (attendants.isEmpty)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(
                      child: Text(
                        'No attendants registered under this organization.',
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                )
              else
                ...attendants.map((a) => Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
                          child: Icon(Icons.assignment_ind_rounded, color: theme.colorScheme.primary, size: 20),
                        ),
                        title: Text(
                          a['attendant_name'] ?? 'N/A',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text('Role: Route Assistant'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                    )),
            ],
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
        final allOrgs = (snapshot.data!['organizations'] as List?) ?? [];

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
              const SizedBox(height: 24),

              // Counts Grid
              const Text(
                'Fleet & Operations Metrics',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _buildStatCard(theme, 'Vehicles', vehiclesCount, Icons.directions_bus_rounded),
                  _buildStatCard(theme, 'Drivers', driversCount, Icons.badge_rounded),
                  _buildStatCard(theme, 'Attendants', attendantsCount, Icons.supervised_user_circle_rounded),
                  _buildStatCard(theme, 'Routes', routesCount, Icons.route_rounded),
                ],
              ),
              const SizedBox(height: 24),

              // Details Lists (Vehicles, Drivers, Attendants)
              const Text(
                'Registered Fleet Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Vehicles Section
              _buildSectionHeader(theme, 'Vehicles list', Icons.directions_bus_rounded),
              if (vehicles.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12.0),
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
                        subtitle: Text(v['type'] ?? 'N/A'),
                      ),
                    )),

              const SizedBox(height: 16),

              // Drivers Section
              _buildSectionHeader(theme, 'Drivers list', Icons.badge_rounded),
              if (drivers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12.0),
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
                        subtitle: Text('License: ${d['license'] ?? 'N/A'}'),
                      ),
                    )),

              const SizedBox(height: 16),

              // Attendants Section
              _buildSectionHeader(theme, 'Attendants list', Icons.supervised_user_circle_rounded),
              if (attendants.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12.0),
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
                          backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
                          child: Icon(Icons.person_outline_rounded, color: theme.colorScheme.primary, size: 20),
                        ),
                        title: Text(
                          a['attendant_name'] ?? 'N/A',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    )),
              const SizedBox(height: 60), // Extra spacing for bottom notched bar
            ],
          ),
        );
      },
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
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final org = _searchResults[index];
                        final name = org['name'] ?? 'N/A';
                        final email = org['email'] ?? 'N/A';
                        final phone = org['number'] ?? 'N/A';
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
                          child: ExpansionTile(
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
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Divider(),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Icon(Icons.phone_rounded, size: 16, color: theme.colorScheme.primary),
                                        const SizedBox(width: 8),
                                        Text(phone, style: const TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.location_on_rounded, size: 16, color: theme.colorScheme.primary),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            address,
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'My Account & Roles',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
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
        Material(
          type: MaterialType.card,
          color: theme.colorScheme.primary.withOpacity(0.02),
          borderRadius: BorderRadius.circular(16),
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
                  leading: const Icon(Icons.phone_iphone),
                  title: const Text('Mobile Number', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  subtitle: Text(userMobile, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Material(
          type: MaterialType.card,
          color: theme.colorScheme.primary.withOpacity(0.02),
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showChangePasswordDialog(theme),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _handleLogout,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign Out'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade50,
            foregroundColor: Colors.red.shade700,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => _showDeleteAccountDialog(theme),
          icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
          label: const Text('Delete Account', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        color: isSelected ? theme.colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(
            icon,
            color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
          ),
          title: Text(
            label,
            style: TextStyle(
              color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          onTap: () {
            setState(() {
              _currentIndex = index;
            });
            Navigator.pop(context); // Close the drawer
          },
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
          setState(() {
            _currentIndex = index;
          });
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
        backgroundColor: theme.colorScheme.primaryContainer,
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
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                    _buildDrawerItem(
                      index: 3,
                      icon: Icons.business_rounded,
                      label: 'Organization',
                      theme: theme,
                    ),
                    _buildDrawerItem(
                      index: 6,
                      icon: Icons.badge_rounded,
                      label: 'Driver',
                      theme: theme,
                    ),
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
          )
        : await ApiService.updateChild(
            widget.child!['id'],
            name: _nameController.text.trim(),
            dob: dobFormatted,
            gender: _gender,
            photoBase64: _imageBase64,
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
        bottom: media.viewInsets.bottom + 24,
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
              const SizedBox(height: 20),
              // Date of birth DatePicker trigger
              InkWell(
                onTap: _selectDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, color: Colors.grey.shade600),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedDate == null
                              ? 'Date of Birth'
                              : '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 16,
                            color: _selectedDate == null ? Colors.grey.shade600 : Colors.black87,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: Colors.grey.shade600),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
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
