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

  // Search Organizations API request
  static Future<Map<String, dynamic>> searchOrganizations(String query) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'message': 'No authentication token found'};
      }

      final response = await http.get(
        Uri.parse('$baseUrl/organizations/search?q=${Uri.encodeComponent(query)}'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'organizations': data['organizations']};
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
}
