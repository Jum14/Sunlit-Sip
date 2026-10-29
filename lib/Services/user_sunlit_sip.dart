import 'dart:convert';
import 'package:http/http.dart' as http;

class SunlitSipItem {
  final dynamic id;
  final String title;
  final String description;
  final String price;
  final String points;

  SunlitSipItem({
    this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.points,
  });

  factory SunlitSipItem.fromJson(Map<String, dynamic> json) {
    return SunlitSipItem(
      id: json['id'],
      title: json['title'] ?? json['name'] ?? 'Coffee Item',
      description: json['description'] ?? json['category'] ?? 'Espresso Blend',
      price: json['price']?.toString() ?? '₱150.00',
      points: json['points']?.toString() ?? '+15 Pts',
    );
  }
}

class SunlitSipApiService {
  static const String apiUrl =
      'https://raw.githubusercontent.com/Jum14/SunlitSip-API/refs/heads/main/sunlit_sip_menu.json';

  static Future<List<SunlitSipItem>> fetchMenuItems() async {
    final response = await http.get(Uri.parse(apiUrl));

    if (response.statusCode == 200) {
      final List<dynamic> body = jsonDecode(response.body);
      return body.map((item) => SunlitSipItem.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load menu data (Status Code: ${response.statusCode})');
    }
  }
}