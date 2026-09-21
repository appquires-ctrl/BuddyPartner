import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static String baseUrl = const String.fromEnvironment(
    'ADMIN_BACKEND_URL',
    defaultValue: 'https://buddypartner.onrender.com/api/admin',
  );

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('admin_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_token', token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('admin_token');
  }

  static Future<Map<String, String>> _headers() async {
    final token = await getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Future<dynamic> get(String path, {Map<String, String>? queryParams}) async {
    try {
      var uri = Uri.parse('$baseUrl$path');
      if (queryParams != null && queryParams.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParams);
      }
      final response = await http.get(uri, headers: await _headers());
      return _processResponse(response);
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = await http.post(
        uri,
        headers: await _headers(),
        body: body != null ? jsonEncode(body) : null,
      );
      return _processResponse(response);
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = await http.patch(
        uri,
        headers: await _headers(),
        body: body != null ? jsonEncode(body) : null,
      );
      return _processResponse(response);
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<dynamic> put(String path, {Map<String, dynamic>? body}) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = await http.put(
        uri,
        headers: await _headers(),
        body: body != null ? jsonEncode(body) : null,
      );
      return _processResponse(response);
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<dynamic> delete(String path) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = await http.delete(
        uri,
        headers: await _headers(),
      );
      return _processResponse(response);
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<dynamic> uploadFile(String path, List<int> bytes, String filename) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final request = http.MultipartRequest('POST', uri);
      final token = await getToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      MediaType? contentType;
      final ext = filename.toLowerCase();
      if (ext.endsWith('.png')) {
        contentType = MediaType('image', 'png');
      } else if (ext.endsWith('.webp')) {
        contentType = MediaType('image', 'webp');
      } else if (ext.endsWith('.jpg') || ext.endsWith('.jpeg')) {
        contentType = MediaType('image', 'jpeg');
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: filename,
          contentType: contentType,
        ),
      );
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      return _processResponse(response);
    } catch (e) {
      throw Exception('Upload error: $e');
    }
  }

  static dynamic _processResponse(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true, 'data': response.body};
      }
      throw Exception('Server returned ${response.statusCode}');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    } else {
      final msg = body is Map && body.containsKey('message')
          ? body['message']
          : 'HTTP Error ${response.statusCode}';
      throw Exception(msg);
    }
  }
}
