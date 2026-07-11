import 'dart:convert';
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

  @override
  void initState() {
    super.initState();
    _loadUser();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Registered Children & Schedule',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildListCard(
          title: 'Aarav Rathod',
          subtitle: 'Grade 4 • Route A1 • Bus No. MH-12-3456',
          icon: Icons.child_care_rounded,
        ),
        _buildListCard(
          title: 'Kiara Rathod',
          subtitle: 'Grade 1 • Route A1 • Bus No. MH-12-3456',
          icon: Icons.child_care_rounded,
        ),
      ],
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

  Widget _buildOrganizationPage() {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: ApiService.getOrganization(),
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

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                        backgroundImage: orgLogo != null ? NetworkImage(orgLogo) : null,
                        child: orgLogo == null
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
                        subtitle: Text(v['model'] ?? 'N/A'),
                        trailing: Text(
                          'Cap: ${v['capacity'] ?? 'N/A'}',
                          style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                        ),
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
                    backgroundImage: userPhoto != null ? NetworkImage(userPhoto) : null,
                    child: userPhoto == null
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
                backgroundImage: userPhoto != null && userPhoto.isNotEmpty ? NetworkImage(userPhoto) : null,
                child: userPhoto == null || userPhoto.isEmpty
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
                      index: 0,
                      icon: Icons.group_rounded,
                      label: 'Group',
                      theme: theme,
                    ),
                    _buildDrawerItem(
                      index: 1,
                      icon: Icons.supervisor_account_rounded,
                      label: 'Parent',
                      theme: theme,
                    ),
                    _buildDrawerItem(
                      index: 3,
                      icon: Icons.business_rounded,
                      label: 'Organization',
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
              _buildTabItem(index: 0, icon: Icons.group_rounded, label: 'Group'),
              _buildTabItem(index: 1, icon: Icons.supervisor_account_rounded, label: 'Parent'),
              const SizedBox(width: 48), // Spacer for center FAB
              _buildTabItem(index: 3, icon: Icons.business_rounded, label: 'Organization'),
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
