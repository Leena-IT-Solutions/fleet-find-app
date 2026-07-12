import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://fleet.infoleena.com/api';

  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';

  // Helper to save token
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  // Helper to get token
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // Helper to save user data
  static Future<void> saveUser(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(userData));
  }

  // Helper to get user data
  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString(_userKey);
    if (userStr != null) {
      return jsonDecode(userStr) as Map<String, dynamic>;
    }
    return null;
  }

  // Clear session (Logout)
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  // Is user logged in?
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  // Register API request
  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String mobile,
    required String password,
    required String confirmPassword,
    String? relationshipType,
    String? coParentPhoneOrEmail,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'mobile': mobile,
          'password': password,
          'password_confirmation': confirmPassword,
          if (relationshipType != null) 'relationship_type': relationshipType,
          if (coParentPhoneOrEmail != null) 'co_parent_phone_or_email': coParentPhoneOrEmail,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        final token = data['access_token'];
        await saveToken(token);
        await saveUser(data['user']);
        return {'success': true, 'message': 'Registration successful'};
      } else {
        final message = data['message'] ?? 'Registration failed';
        final errors = data['errors'] as Map<String, dynamic>?;
        return {
          'success': false,
          'message': message,
          'errors': errors,
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Login API request
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final token = data['access_token'];
        await saveToken(token);
        await saveUser(data['user']);
        return {'success': true, 'message': 'Login successful'};
      } else {
        final message = data['message'] ?? 'Login failed';
        return {'success': false, 'message': message};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Forgot Password API request
  static Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/forgot-password'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'OTP code sent successfully.'};
      } else {
        final message = data['message'] ?? 'Failed to send OTP code.';
        return {'success': false, 'message': message};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Reset Password API request
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String password,
    required String confirmPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/reset-password'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
          'password': password,
          'password_confirmation': confirmPassword,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'Password reset successful'};
      } else {
        final message = data['message'] ?? 'Failed to reset password';
        final errors = data['errors'] as Map<String, dynamic>?;
        return {
          'success': false,
          'message': message,
          'errors': errors,
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Logout API request
  static Future<Map<String, dynamic>> logout() async {
    try {
      final token = await getToken();
      if (token == null) {
        await clearSession();
        return {'success': true, 'message': 'Logged out locally'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/logout'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      await clearSession();

      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Logout successful'};
      } else {
        return {'success': true, 'message': 'Logged out locally after server mismatch'};
      }
    } catch (e) {
      await clearSession();
      return {'success': true, 'message': 'Logged out locally'};
    }
  }

  // Fetch fresh user profile from the server
  static Future<Map<String, dynamic>> fetchFreshUser() async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No auth token found'};
      }

      final response = await http.get(
        Uri.parse('$baseUrl/user'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final userData = Map<String, dynamic>.from(data['user']);
        await saveUser(userData);
        return {'success': true, 'user': userData};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to fetch user profile'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Get trips assigned to the logged-in driver
  static Future<Map<String, dynamic>> getDriverTrips() async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No auth token found'};
      }

      final response = await http.get(
        Uri.parse('$baseUrl/driver/trips'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'driver': data['driver'],
          'trips': data['trips'],
        };
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to load driver trips'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Update Profile API request
  static Future<Map<String, dynamic>> updateProfile({
    required String name,
    required String email,
    required String mobile,
    String? profilePhoto,
  }) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/profile/update'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
          'email': email,
          'mobile': mobile,
          if (profilePhoto != null) 'profile_photo': profilePhoto,
        }),
      );
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await saveUser(data['user']);
        return {'success': true, 'message': 'Profile updated successfully', 'user': data['user']};
      } else {
        final message = data['message'] ?? 'Failed to update profile';
        final errors = data['errors'] as Map<String, dynamic>?;
        return {
          'success': false,
          'message': message,
          'errors': errors,
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Change Password API request
  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String password,
    required String confirmPassword,
  }) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/profile/password'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'current_password': currentPassword,
          'password': password,
          'password_confirmation': confirmPassword,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'Password changed successfully'};
      } else {
        final message = data['message'] ?? 'Failed to change password';
        final errors = data['errors'] as Map<String, dynamic>?;
        return {
          'success': false,
          'message': message,
          'errors': errors,
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Delete Account API request
  static Future<Map<String, dynamic>> deleteAccount() async {
    try {
      final token = await getToken();
      if (token == null) {
        await clearSession();
        return {'success': true, 'message': 'Session cleared'};
      }

      final response = await http.delete(
        Uri.parse('$baseUrl/profile/delete'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      await clearSession();

      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Account deleted successfully'};
      } else {
        return {'success': true, 'message': 'Account deleted locally after server mismatch'};
      }
    } catch (e) {
      await clearSession();
      return {'success': true, 'message': 'Account deleted locally'};
    }
  }

  static Future<Map<String, dynamic>> getOrganization({int? organizationId}) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final url = organizationId != null
          ? '$baseUrl/organization?organization_id=$organizationId'
          : '$baseUrl/organization';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'organization': data['organization'],
          'organizations': data['organizations']
        };
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to load organization'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> searchOrganizations(String query, {int page = 1}) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final response = await http.get(
        Uri.parse('$baseUrl/organizations/search?q=${Uri.encodeComponent(query)}&page=$page'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return data;
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to search organizations'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Get Children API request
  static Future<Map<String, dynamic>> getChildren() async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final response = await http.get(
        Uri.parse('$baseUrl/children'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'children': data['children']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to load children'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Add Child API request
  static Future<Map<String, dynamic>> addChild({
    required String name,
    String? dob,
    String? gender,
    String? photoBase64,
    String? relationshipType,
  }) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/children'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
          if (dob != null) 'dob': dob,
          if (gender != null) 'gender': gender,
          if (photoBase64 != null) 'photo': photoBase64,
          if (relationshipType != null) 'relationship_type': relationshipType,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'child': data['child'], 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to add child'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Update Child API request
  static Future<Map<String, dynamic>> updateChild(
    int id, {
    required String name,
    String? dob,
    String? gender,
    String? photoBase64,
    String? relationshipType,
  }) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final response = await http.put(
        Uri.parse('$baseUrl/children/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
          if (dob != null) 'dob': dob,
          if (gender != null) 'gender': gender,
          if (photoBase64 != null) 'photo': photoBase64,
          if (relationshipType != null) 'relationship_type': relationshipType,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'child': data['child'], 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to update child'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Delete Child API request
  static Future<Map<String, dynamic>> deleteChild(int id) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final response = await http.delete(
        Uri.parse('$baseUrl/children/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to delete child'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Get User's Groups
  static Future<Map<String, dynamic>> getGroups() async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'message': 'No authentication token found'};

      final response = await http.get(
        Uri.parse('$baseUrl/groups'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'groups': data['groups']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to get groups'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Create Group
  static Future<Map<String, dynamic>> createGroup(String name, String? description) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'message': 'No authentication token found'};

      final response = await http.post(
        Uri.parse('$baseUrl/groups'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
          'description': description,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return {'success': true, 'group': data['group'], 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to create group'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Get Group Detail (Members and location list)
  static Future<Map<String, dynamic>> getGroupDetail(int id) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'message': 'No authentication token found'};

      final response = await http.get(
        Uri.parse('$baseUrl/groups/$id'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'group': data['group'],
          'members': data['members'],
        };
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to get group details'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Update Group
  static Future<Map<String, dynamic>> updateGroup(int id, String name, String? description) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'message': 'No authentication token found'};

      final response = await http.put(
        Uri.parse('$baseUrl/groups/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
          'description': description,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'group': data['group'], 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to update group'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Delete Group
  static Future<Map<String, dynamic>> deleteGroup(int id) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'message': 'No authentication token found'};

      final response = await http.delete(
        Uri.parse('$baseUrl/groups/$id'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to delete group'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Add Group Member
  static Future<Map<String, dynamic>> addGroupMember(int groupId, String emailOrMobile) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'message': 'No authentication token found'};

      final response = await http.post(
        Uri.parse('$baseUrl/groups/$groupId/members'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'search': emailOrMobile,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'member': data['member'], 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to add member'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Remove Group Member
  static Future<Map<String, dynamic>> removeGroupMember(int groupId, int userId) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'message': 'No authentication token found'};

      final response = await http.delete(
        Uri.parse('$baseUrl/groups/$groupId/members/$userId'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to remove member'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Update Member Role
  static Future<Map<String, dynamic>> updateMemberRole(int groupId, int userId, String role) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'message': 'No authentication token found'};

      final response = await http.patch(
        Uri.parse('$baseUrl/groups/$groupId/members/$userId/role'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'role': role,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to update role'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Update User Location
  static Future<Map<String, dynamic>> updateLocation(double? lat, double? lng, bool sharingEnabled) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'message': 'No authentication token found'};

      final response = await http.patch(
        Uri.parse('$baseUrl/location'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitude': lat,
          'longitude': lng,
          'location_sharing_enabled': sharingEnabled,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'user': data['user'], 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to update location'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Get Location Update Interval Setting
  static Future<Map<String, dynamic>> getLocationInterval() async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'message': 'No authentication token found'};

      final response = await http.get(
        Uri.parse('$baseUrl/settings/location-interval'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'location_update_interval_seconds': data['location_update_interval_seconds']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to get location interval'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Toggle Group-Specific Location Sharing
  static Future<Map<String, dynamic>> toggleGroupLocationSharing(int groupId, bool sharingEnabled) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'message': 'No authentication token found'};

      final response = await http.patch(
        Uri.parse('$baseUrl/groups/$groupId/location-sharing'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'location_sharing_enabled': sharingEnabled,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'location_sharing_enabled': data['location_sharing_enabled'], 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to update location sharing'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Get single child details and relationships
  static Future<Map<String, dynamic>> getChild(int id) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final response = await http.get(
        Uri.parse('$baseUrl/children/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'child': data['child']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to fetch child details'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Add parent relationship to a child
  static Future<Map<String, dynamic>> addChildRelationship(
    int childId, {
    required String emailOrMobile,
    required String relationshipType,
  }) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/children/$childId/relationships'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'email_or_mobile': emailOrMobile,
          'relationship_type': relationshipType,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'Relationship added successfully'};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to add relationship'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Delete parent relationship from a child
  static Future<Map<String, dynamic>> deleteChildRelationship(int childId, int userId) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final response = await http.delete(
        Uri.parse('$baseUrl/children/$childId/relationships/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'Relationship removed successfully'};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to remove relationship'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Get subscription enrollment options (children, grades, routes, stops)
  static Future<Map<String, dynamic>> getSubscriptionEnrollmentOptions(int planId) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final response = await http.get(
        Uri.parse('$baseUrl/subscription-plans/$planId/enrollment-options'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'children': data['children'] ?? [],
          'grades': data['grades'] ?? [],
          'routes': data['routes'] ?? [],
        };
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to load options'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Submit subscription enrollment request
  static Future<Map<String, dynamic>> enrollSubscription(int planId, {
    required int childId,
    required int gradeId,
    required int divisionId,
    required int routeId,
    required int pickupStopId,
    required int dropStopId,
  }) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/subscription-plans/$planId/enroll'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'child_id': childId,
          'grade_id': gradeId,
          'division_id': divisionId,
          'route_id': routeId,
          'pickup_stop_id': pickupStopId,
          'drop_stop_id': dropStopId,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'Enrolled successfully'};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to enroll'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
