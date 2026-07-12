import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class OrganizationProfileScreen extends StatelessWidget {
  const OrganizationProfileScreen({super.key});

  Future<void> _launchMaps(String query) async {
    final Uri url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchPhone(String phone) async {
    final Uri url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _launchEmail(String email) async {
    final Uri url = Uri.parse('mailto:$email');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _showEnrollmentBottomSheet(BuildContext context, Map<String, dynamic> plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EnrollmentBottomSheet(plan: plan),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> org = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final theme = Theme.of(context);

    final String name = org['name'] ?? 'N/A';
    final String contactName = org['contact_name'] ?? 'N/A';
    final String email = org['email'] ?? 'N/A';
    final String number = org['number'] ?? 'N/A';
    final String address = org['address'] ?? 'N/A';
    final String? logo = org['logo'] as String?;

    final bool showEmail = org['show_email'] == true || org['show_email'] == 1 || org['show_email'] == null;
    final bool showPhone = org['show_phone'] == true || org['show_phone'] == 1 || org['show_phone'] == null;
    final List<dynamic> plans = org['subscription_plans'] as List<dynamic>? ?? [];

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Organization Profile'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Section with Custom Gradient Background
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withOpacity(0.85),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Logo Container
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: logo != null && logo.isNotEmpty && logo.startsWith('http')
                          ? Image.network(
                              logo,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Icon(
                                  Icons.business_rounded,
                                  size: 45,
                                  color: theme.colorScheme.primary,
                                ),
                            )
                          : Icon(
                              Icons.business_rounded,
                              size: 45,
                              color: theme.colorScheme.primary,
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (contactName != 'N/A' && contactName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Contact: $contactName',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Quick Actions Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildHeaderActionButton(
                        icon: Icons.directions_rounded,
                        label: 'Navigate',
                        onTap: () {
                          final double? lat = double.tryParse(org['latitude']?.toString() ?? '');
                          final double? lng = double.tryParse(org['longitude']?.toString() ?? '');
                          if (lat != null && lng != null) {
                            _launchMaps('$lat,$lng');
                          } else {
                            _launchMaps(address);
                          }
                        },
                      ),
                      if (showPhone && number != 'N/A' && number.isNotEmpty)
                        _buildHeaderActionButton(
                          icon: Icons.call_rounded,
                          label: 'Call',
                          onTap: () => _launchPhone(number),
                        ),
                      if (showEmail && email != 'N/A' && email.isNotEmpty)
                        _buildHeaderActionButton(
                          icon: Icons.email_rounded,
                          label: 'Email',
                          onTap: () => _launchEmail(email),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Profile Details Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 8),
                    child: Text(
                      'CONTACT DETAILS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            icon: Icons.location_on_rounded,
                            iconColor: Colors.red.shade600,
                            title: 'Address',
                            value: address,
                          ),
                          if (showEmail) ...[
                            const Divider(height: 24),
                            _buildDetailRow(
                              icon: Icons.email_rounded,
                              iconColor: Colors.blue.shade600,
                              title: 'Email Address',
                              value: email,
                            ),
                          ],
                          if (showPhone) ...[
                            const Divider(height: 24),
                            _buildDetailRow(
                              icon: Icons.phone_rounded,
                              iconColor: Colors.green.shade600,
                              title: 'Phone Number',
                              value: number,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Subscription Plans Section
            if (plans.isNotEmpty) ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 8, bottom: 8),
                      child: Text(
                        'SUBSCRIPTION PLANS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    ...plans.map((plan) {
                      final String planName = plan['name'] ?? 'N/A';
                      final String amount = plan['amount']?.toString() ?? '0.00';
                      
                      String regStart = 'N/A';
                      String regEnd = 'N/A';
                      String validTill = 'N/A';

                      DateTime? regStartDate;
                      DateTime? regEndDate;

                      try {
                        if (plan['registration_start_date'] != null) {
                          regStartDate = DateTime.parse(plan['registration_start_date'].toString());
                          regStart = DateFormat('MMM dd, yyyy').format(regStartDate);
                        }
                        if (plan['registration_end_date'] != null) {
                          regEndDate = DateTime.parse(plan['registration_end_date'].toString());
                          regEnd = DateFormat('MMM dd, yyyy').format(regEndDate);
                        }
                        if (plan['valid_till'] != null) {
                          validTill = DateFormat('MMM dd, yyyy').format(DateTime.parse(plan['valid_till'].toString()));
                        }
                      } catch (_) {}

                      // Compute active window status
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      
                      String buttonText = 'Enroll Now';
                      bool isButtonEnabled = true;

                      if (regStartDate != null && today.isBefore(DateTime(regStartDate.year, regStartDate.month, regStartDate.day))) {
                        buttonText = 'Opens on ${DateFormat('MMM dd').format(regStartDate)}';
                        isButtonEnabled = false;
                      } else if (regEndDate != null && today.isAfter(DateTime(regEndDate.year, regEndDate.month, regEndDate.day))) {
                        buttonText = 'Registration Closed';
                        isButtonEnabled = false;
                      }

                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      planName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '₹$amount',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              Row(
                                children: [
                                  const Icon(Icons.app_registration_rounded, size: 16, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Registration Open: $regStart - $regEnd',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.event_available_rounded, size: 16, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Valid Till: $validTill',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: isButtonEnabled
                                      ? () => _showEnrollmentBottomSheet(context, plan)
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    elevation: 0,
                                    backgroundColor: theme.colorScheme.primary,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: Colors.grey.shade200,
                                    disabledForegroundColor: Colors.grey.shade500,
                                  ),
                                  child: Text(
                                    buttonText,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class EnrollmentBottomSheet extends StatefulWidget {
  final Map<String, dynamic> plan;

  const EnrollmentBottomSheet({super.key, required this.plan});

  @override
  State<EnrollmentBottomSheet> createState() => _EnrollmentBottomSheetState();
}

class _EnrollmentBottomSheetState extends State<EnrollmentBottomSheet> {
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;
  String _errorMsg = '';

  List<dynamic> _children = [];
  List<dynamic> _grades = [];
  List<dynamic> _routes = [];

  // Dropdown Selections
  int? _selectedChildId;
  int? _selectedGradeId;
  int? _selectedDivisionId;
  int? _selectedRouteId;
  int? _selectedPickupStopId;
  int? _selectedDropStopId;

  // Filtered lists based on parent selection
  List<dynamic> _availableDivisions = [];
  List<dynamic> _availableStops = [];

  @override
  void initState() {
    super.initState();
    _loadEnrollmentOptions();
  }

  Future<void> _loadEnrollmentOptions() async {
    setState(() {
      _isLoading = true;
      _errorMsg = '';
    });

    final res = await ApiService.getSubscriptionEnrollmentOptions(widget.plan['id']);

    if (mounted) {
      if (res['success'] == true) {
        setState(() {
          _children = res['children'] ?? [];
          _grades = res['grades'] ?? [];
          _routes = res['routes'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMsg = res['message'] ?? 'Failed to load options from server';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submitEnrollment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedChildId == null ||
        _selectedGradeId == null ||
        _selectedDivisionId == null ||
        _selectedRouteId == null ||
        _selectedPickupStopId == null ||
        _selectedDropStopId == null) {
      setState(() {
        _errorMsg = 'Please make all selections';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMsg = '';
    });

    final res = await ApiService.enrollSubscription(
      widget.plan['id'],
      childId: _selectedChildId!,
      gradeId: _selectedGradeId!,
      divisionId: _selectedDivisionId!,
      routeId: _selectedRouteId!,
      pickupStopId: _selectedPickupStopId!,
      dropStopId: _selectedDropStopId!,
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
      });

      if (res['success'] == true) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Successfully submitted enrollment request!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _errorMsg = res['message'] ?? 'Failed to submit enrollment request';
        });
      }
    }
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
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
                'Enroll Subscription',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                widget.plan['name'] ?? '',
                style: TextStyle(fontSize: 14, color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
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
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                // Child Dropdown
                DropdownButtonFormField<int>(
                  value: _selectedChildId,
                  decoration: InputDecoration(
                    labelText: 'Select Child',
                    prefixIcon: const Icon(Icons.face_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _children.map<DropdownMenuItem<int>>((c) {
                    return DropdownMenuItem<int>(
                      value: c['id'],
                      child: Text(c['name'] ?? 'N/A'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedChildId = val;
                    });
                  },
                  validator: (value) => value == null ? 'Please select a child' : null,
                ),
                const SizedBox(height: 16),

                // Grade Dropdown
                DropdownButtonFormField<int>(
                  value: _selectedGradeId,
                  decoration: InputDecoration(
                    labelText: 'Select Grade',
                    prefixIcon: const Icon(Icons.school_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _grades.map<DropdownMenuItem<int>>((g) {
                    return DropdownMenuItem<int>(
                      value: g['id'],
                      child: Text(g['name'] ?? 'N/A'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedGradeId = val;
                      _selectedDivisionId = null;
                      _availableDivisions = [];
                      if (val != null) {
                        final grade = _grades.firstWhere((g) => g['id'] == val);
                        _availableDivisions = grade['divisions'] ?? [];
                      }
                    });
                  },
                  validator: (value) => value == null ? 'Please select a grade' : null,
                ),
                const SizedBox(height: 16),

                // Division Dropdown
                DropdownButtonFormField<int>(
                  value: _selectedDivisionId,
                  decoration: InputDecoration(
                    labelText: 'Select Division',
                    prefixIcon: const Icon(Icons.class_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _availableDivisions.map<DropdownMenuItem<int>>((d) {
                    return DropdownMenuItem<int>(
                      value: d['id'],
                      child: Text(d['name'] ?? 'N/A'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedDivisionId = val;
                    });
                  },
                  validator: (value) => value == null ? 'Please select a division' : null,
                ),
                const SizedBox(height: 16),

                // Route Dropdown
                DropdownButtonFormField<int>(
                  value: _selectedRouteId,
                  decoration: InputDecoration(
                    labelText: 'Select Route',
                    prefixIcon: const Icon(Icons.directions_bus_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _routes.map<DropdownMenuItem<int>>((r) {
                    return DropdownMenuItem<int>(
                      value: r['id'],
                      child: Text(r['name'] ?? 'N/A'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedRouteId = val;
                      _selectedPickupStopId = null;
                      _selectedDropStopId = null;
                      _availableStops = [];
                      if (val != null) {
                        final route = _routes.firstWhere((r) => r['id'] == val);
                        _availableStops = route['stops'] ?? [];
                      }
                    });
                  },
                  validator: (value) => value == null ? 'Please select a route' : null,
                ),
                const SizedBox(height: 16),

                // Pickup Stop Dropdown
                DropdownButtonFormField<int>(
                  value: _selectedPickupStopId,
                  decoration: InputDecoration(
                    labelText: 'Pickup Stop',
                    prefixIcon: const Icon(Icons.location_on_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _availableStops.map<DropdownMenuItem<int>>((s) {
                    return DropdownMenuItem<int>(
                      value: s['id'],
                      child: Text(s['name'] ?? 'N/A'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedPickupStopId = val;
                    });
                  },
                  validator: (value) => value == null ? 'Please select a pickup stop' : null,
                ),
                const SizedBox(height: 16),

                // Drop Stop Dropdown
                DropdownButtonFormField<int>(
                  value: _selectedDropStopId,
                  decoration: InputDecoration(
                    labelText: 'Drop Stop',
                    prefixIcon: const Icon(Icons.wrong_location_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _availableStops.map<DropdownMenuItem<int>>((s) {
                    return DropdownMenuItem<int>(
                      value: s['id'],
                      child: Text(s['name'] ?? 'N/A'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedDropStopId = val;
                    });
                  },
                  validator: (value) => value == null ? 'Please select a drop stop' : null,
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _isSaving ? null : _submitEnrollment,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Submit Subscription Request',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
