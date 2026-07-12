import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ChildDetailScreen extends StatefulWidget {
  const ChildDetailScreen({super.key});

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  int? _childId;
  Map<String, dynamic>? _childDetails;
  bool _isLoading = true;
  String _errorMsg = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_childId == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _childId = args['id'] as int?;
        _fetchDetails();
      } else if (args is int) {
        _childId = args;
        _fetchDetails();
      } else {
        setState(() {
          _errorMsg = 'Invalid child selection';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchDetails() async {
    if (_childId == null) return;
    setState(() {
      _isLoading = true;
      _errorMsg = '';
    });

    final response = await ApiService.getChild(_childId!);
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (response['success'] == true) {
          _childDetails = response['child'];
        } else {
          _errorMsg = response['message'] ?? 'Failed to load details';
        }
      });
    }
  }

  Future<void> _deleteChild() async {
    if (_childId == null) return;

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
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
            const Text(
              'Delete Child Profile?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Are you sure you want to permanently delete this child profile? This action cannot be undone.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
      });
      final res = await ApiService.deleteChild(_childId!);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Child profile deleted successfully')),
          );
          Navigator.pop(context, true); // Return true to refresh parent screen
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Failed to delete child')),
          );
        }
      }
    }
  }

  void _showEditChildBottomSheet() {
    if (_childDetails == null) return;
    // Open the same _AddChildBottomSheet by dispatching or routing.
    // Wait, let's open a bottom sheet with same form fields dynamically.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _EditChildBottomSheet(
        child: _childDetails!,
        onSaved: () {
          _fetchDetails();
        },
      ),
    );
  }

  void _showAddRelationshipBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AddRelationshipBottomSheet(
        childId: _childId!,
        onSaved: () {
          _fetchDetails();
        },
      ),
    );
  }

  void _showEditRelationshipBottomSheet(Map<String, dynamic> relationship) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _EditRelationshipBottomSheet(
        childId: _childId!,
        relationship: relationship,
        onSaved: () {
          _fetchDetails();
        },
      ),
    );
  }

  Future<void> _removeRelationship(int userId) async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
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
            const Text(
              'Remove Relationship?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Are you sure you want to remove this parent/guardian relationship from this child?',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
      });
      final res = await ApiService.deleteChildRelationship(_childId!, userId);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        if (res['success'] == true) {
          _fetchDetails();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Relationship removed successfully')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Failed to remove relationship')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMsg.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Child Profile')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMsg, style: const TextStyle(color: Colors.red, fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchDetails,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final child = _childDetails;
    if (child == null) {
      return const Scaffold(
        body: Center(child: Text('Child data unavailable')),
      );
    }

    final String? dob = child['dob'];
    final String gender = child['gender'] ?? 'Male';
    final String? photoUrl = child['photo'];
    final List<dynamic> relationships = child['relationships'] ?? [];

    // Calculate age
    int age = 0;
    if (dob != null && dob.isNotEmpty) {
      try {
        final birthDate = DateTime.parse(dob);
        final today = DateTime.now();
        age = today.year - birthDate.year;
        if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) {
          age--;
        }
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(child['name'] ?? 'Child Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: _showEditChildBottomSheet,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            onPressed: _deleteChild,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Section (Child Photo and Info)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 64,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: photoUrl != null && photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null || photoUrl.isEmpty
                        ? Icon(Icons.face_rounded, size: 64, color: theme.colorScheme.primary)
                        : null,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    child['name'] ?? '',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (dob != null && dob.isNotEmpty)
                        Chip(
                          label: Text('$age Years Old'),
                          avatar: const Icon(Icons.cake_outlined, size: 16),
                          backgroundColor: Colors.blue.shade50,
                          side: BorderSide.none,
                        ),
                      Chip(
                        label: Text(gender),
                        avatar: Icon(
                          gender == 'Male'
                              ? Icons.male_rounded
                              : gender == 'Female'
                                  ? Icons.female_rounded
                                  : Icons.transgender_rounded,
                          size: 16,
                        ),
                        backgroundColor: gender == 'Male'
                            ? Colors.green.shade50
                            : gender == 'Female'
                                ? Colors.pink.shade50
                                : Colors.purple.shade50,
                        side: BorderSide.none,
                      ),
                    ],
                  ),
                  if (dob != null && dob.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'DOB: $dob',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Relationships Card Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Parents & Guardians',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        onPressed: _showAddRelationshipBottomSheet,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: relationships.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final rel = relationships[index];
                      final String name = rel['name'] ?? '';
                      final String role = rel['relationship_type'] ?? 'Other';
                      final String email = rel['email'] ?? '';
                      final String mobile = rel['mobile'] ?? '';

                      final Color bgRole = role.toLowerCase() == 'mother'
                          ? const Color(0xFFFDE8E8)
                          : role.toLowerCase() == 'father'
                              ? const Color(0xFFE1EFFE)
                              : role.toLowerCase() == 'guardian'
                                  ? const Color(0xFFE5F7F6)
                                  : const Color(0xFFF3F4F6);

                      final Color textRole = role.toLowerCase() == 'mother'
                          ? const Color(0xFFE02424)
                          : role.toLowerCase() == 'father'
                              ? const Color(0xFF1E429F)
                              : role.toLowerCase() == 'guardian'
                                  ? const Color(0xFF0369A1)
                                  : const Color(0xFF4B5563);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade100),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.colorScheme.primary.withOpacity(0.08),
                                  theme.colorScheme.primary.withOpacity(0.15),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'P',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: bgRole,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      role,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: textRole,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    email.isNotEmpty ? Icons.mail_outline_rounded : Icons.phone_android_rounded,
                                    size: 14,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      email.isNotEmpty ? email : mobile,
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => _showEditRelationshipBottomSheet(rel),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.edit_rounded, color: Colors.blue.shade700, size: 16),
                                ),
                              ),
                              if (relationships.length > 1) ...[
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => _removeRelationship(rel['id']),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.link_off_rounded, color: Colors.red.shade700, size: 16),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Inline bottom sheet for updating the child details
class _EditChildBottomSheet extends StatefulWidget {
  final Map<String, dynamic> child;
  final VoidCallback onSaved;

  const _EditChildBottomSheet({
    required this.child,
    required this.onSaved,
  });

  @override
  State<_EditChildBottomSheet> createState() => _EditChildBottomSheetState();
}

class _EditChildBottomSheetState extends State<_EditChildBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  DateTime? _selectedDate;
  late String _gender;
  bool _isSaving = false;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.child['name'] ?? '');
    _gender = widget.child['gender'] ?? 'Male';
    final dobStr = widget.child['dob'] as String?;
    if (dobStr != null && dobStr.isNotEmpty) {
      try {
        _selectedDate = DateTime.parse(dobStr);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().subtract(const Duration(days: 365 * 8)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
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

    final response = await ApiService.updateChild(
      widget.child['id'],
      name: _nameController.text.trim(),
      dob: dobFormatted,
      gender: _gender,
      relationshipType: widget.child['relationship_type'], // preserve existing relation type
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
      });
      if (response['success'] == true) {
        widget.onSaved();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Child profile updated successfully')),
        );
      } else {
        setState(() {
          _errorMsg = response['message'] ?? 'Failed to update child';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24,
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
              const Text(
                'Edit Child Profile',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_errorMsg.isNotEmpty) ...[
                Text(_errorMsg, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                const SizedBox(height: 12),
              ],
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

              const Text(
                'Gender',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                    : const Text(
                        'Update Profile',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Add relationship bottom sheet modal
class _AddRelationshipBottomSheet extends StatefulWidget {
  final int childId;
  final VoidCallback onSaved;

  const _AddRelationshipBottomSheet({
    required this.childId,
    required this.onSaved,
  });

  @override
  State<_AddRelationshipBottomSheet> createState() => _AddRelationshipBottomSheetState();
}

class _AddRelationshipBottomSheetState extends State<_AddRelationshipBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _inputController = TextEditingController();
  String _relationshipType = 'Mother';
  bool _isSaving = false;
  String _errorMsg = '';

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMsg = '';
    });

    final res = await ApiService.addChildRelationship(
      widget.childId,
      emailOrMobile: _inputController.text.trim(),
      relationshipType: _relationshipType,
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
      });
      if (res['success'] == true) {
        widget.onSaved();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relationship added successfully')),
        );
      } else {
        setState(() {
          _errorMsg = res['message'] ?? 'Failed to add relationship';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24,
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
              const Text(
                'Add Parent / Guardian',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_errorMsg.isNotEmpty) ...[
                Text(_errorMsg, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _inputController,
                decoration: InputDecoration(
                  labelText: 'Email Address or Mobile Number',
                  helperText: 'Link another registered parent/guardian profile',
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter email or mobile';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _relationshipType,
                decoration: InputDecoration(
                  labelText: 'Relationship to Child',
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
                onPressed: _isSaving ? null : _submit,
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
                    : const Text(
                        'Link Relationship',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Edit relationship bottom sheet modal
class _EditRelationshipBottomSheet extends StatefulWidget {
  final int childId;
  final Map<String, dynamic> relationship;
  final VoidCallback onSaved;

  const _EditRelationshipBottomSheet({
    required this.childId,
    required this.relationship,
    required this.onSaved,
  });

  @override
  State<_EditRelationshipBottomSheet> createState() => _EditRelationshipBottomSheetState();
}

class _EditRelationshipBottomSheetState extends State<_EditRelationshipBottomSheet> {
  late String _relationshipType;
  bool _isSaving = false;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    _relationshipType = widget.relationship['relationship_type'] ?? 'Mother';
  }

  Future<void> _submit() async {
    setState(() {
      _isSaving = true;
      _errorMsg = '';
    });

    final String input = widget.relationship['email'] ?? widget.relationship['mobile'] ?? '';

    final res = await ApiService.addChildRelationship(
      widget.childId,
      emailOrMobile: input,
      relationshipType: _relationshipType,
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
      });
      if (res['success'] == true) {
        widget.onSaved();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relationship updated successfully')),
        );
      } else {
        setState(() {
          _errorMsg = res['message'] ?? 'Failed to update relationship';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String name = widget.relationship['name'] ?? '';
    final String contact = widget.relationship['email'] ?? widget.relationship['mobile'] ?? '';

    return Container(
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
            const Text(
              'Edit Relationship',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_errorMsg.isNotEmpty) ...[
              Text(_errorMsg, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 12),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(contact),
              leading: CircleAvatar(
                child: Text(name.isNotEmpty ? name[0] : 'P'),
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _relationshipType,
              decoration: InputDecoration(
                labelText: 'Relationship to Child',
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
              onPressed: _isSaving ? null : _submit,
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
                  : const Text(
                      'Update Relationship',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
