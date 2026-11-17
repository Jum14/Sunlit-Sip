import 'package:cloud_firestore/cloud_firestore.dart';

class SunlitSipItem {
  final String id;
  final String title;
  final String description;
  final String price;
  final String points;
  final String category; // 'Drink' or 'Food'

  SunlitSipItem({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.points,
    this.category = 'Drink',
  });

  static String _inferCategory(String title, dynamic rawCategory) {
    if (rawCategory is String && rawCategory.trim().isNotEmpty) {
      return rawCategory.trim();
    }
    final lower = title.toLowerCase();
    const foodKeywords = [
      'cake',
      'cupcake',
      'cheesecake',
      'croissant',
      'ensaymada',
      'cookie',
      'brownie',
      'brioche',
      'roll',
      'pastry',
      'muffin',
      'sandwich',
      'bread',
    ];
    for (final word in foodKeywords) {
      if (lower.contains(word)) return 'Food';
    }
    return 'Drink';
  }

  factory SunlitSipItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final title = data['title'] as String? ?? '';
    return SunlitSipItem(
      id: doc.id,
      title: title,
      description: data['description'] as String? ?? '',
      price: data['price'] as String? ?? '₱0.00',
      points: data['points'] as String? ?? '+0 Pts',
      category: _inferCategory(title, data['category']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'price': price,
      'points': points,
      'category': category,
    };
  }
}

class SunlitSipApiService {
  static final CollectionReference _menuCollection =
      FirebaseFirestore.instance.collection('menu_items');

  static Stream<List<SunlitSipItem>> getMenuItemsStream() {
    return _menuCollection.snapshots().map((snapshot) {
      final docs = snapshot.docs.toList();
      docs.sort((a, b) {
        final aTs =
            (a.data() as Map<String, dynamic>?)?['createdAt'] as Timestamp?;
        final bTs =
            (b.data() as Map<String, dynamic>?)?['createdAt'] as Timestamp?;
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return bTs.compareTo(aTs);
      });
      return docs.map((doc) => SunlitSipItem.fromFirestore(doc)).toList();
    });
  }

  static Future<void> addMenuItem(SunlitSipItem item) async {
    await _menuCollection.add({
      ...item.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateMenuItem(String id, SunlitSipItem item) async {
    await _menuCollection.doc(id).update({
      ...item.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteMenuItem(String id) async {
    await _menuCollection.doc(id).delete();
  }
}