import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PointsShopPage extends StatefulWidget {
  final String userEmail;
  final bool isAdmin;
  final int currentPoints;
  final ValueChanged<int> onPointsUpdated;

  const PointsShopPage({
    super.key,
    required this.userEmail,
    required this.isAdmin,
    required this.currentPoints,
    required this.onPointsUpdated,
  });

  @override
  State<PointsShopPage> createState() => _PointsShopPageState();
}

class _PointsShopPageState extends State<PointsShopPage> {
  late int _points;

  @override
  void initState() {
    super.initState();
    _points = widget.currentPoints;
  }

  String get _userDocId => widget.userEmail.trim().isEmpty
      ? 'guest@sunlitsip.com'
      : widget.userEmail.toLowerCase().trim();

  int _extractCost(Map<String, dynamic> data) {
    final raw = data['pointsCost'] ?? data['cost'] ?? data['points'] ?? 0;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      return int.tryParse(raw.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    }
    return 0;
  }

  void _showRewardDialog({DocumentSnapshot? existingDoc}) {
    final existingData = existingDoc?.data() as Map<String, dynamic>?;
    final titleController = TextEditingController(
      text: existingData?['title'] as String? ?? '',
    );
    final descController = TextEditingController(
      text: existingData?['description'] as String? ?? '',
    );
    final costController = TextEditingController(
      text: existingData != null ? '${_extractCost(existingData)}' : '50',
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(existingDoc == null ? 'Add New Reward' : 'Edit Reward'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Reward Name'),
                ),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  controller: costController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Points Cost (e.g. 80)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.brown[700],
              ),
              onPressed: () async {
                final title = titleController.text.trim();
                final desc = descController.text.trim();
                final cost = int.tryParse(
                      costController.text.replaceAll(RegExp(r'[^\d]'), ''),
                    ) ??
                    0;

                if (title.isEmpty || cost <= 0) return;

                final navigator = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(context);

                if (existingDoc == null) {
                  await FirebaseFirestore.instance.collection('rewards').add({
                    'title': title,
                    'description': desc,
                    'pointsCost': cost,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                } else {
                  final Map<String, dynamic> updates = {
                    'title': title,
                    'description': desc,
                    'pointsCost': cost,
                    'updatedAt': FieldValue.serverTimestamp(),
                  };
                  if (existingData != null &&
                      existingData.containsKey('cost')) {
                    updates['cost'] = cost;
                  }
                  await existingDoc.reference.update(updates);
                }

                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      existingDoc == null
                          ? 'New reward added!'
                          : 'Reward updated!',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text(
                'Save Reward',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteReward(String docId) async {
    await FirebaseFirestore.instance.collection('rewards').doc(docId).delete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reward deleted!'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _redeemReward(
    String rewardId,
    String title,
    int cost,
  ) async {
    if (_points < cost) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final walletRef =
          FirebaseFirestore.instance.collection('users').doc(_userDocId);

      // 1. Deduct points from the user's Firestore wallet
      await walletRef.set({
        'email': widget.userEmail,
        'loyaltyPoints': FieldValue.increment(-cost),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. Create a Pending reward redemption order
      await FirebaseFirestore.instance.collection('orders').add({
        'userEmail': widget.userEmail,
        'items': [
          {
            'id': rewardId,
            'title': '$title (Reward)',
            'price': 0.0,
            'quantity': 1,
          }
        ],
        'subtotal': 0.0,
        'discount': 0.0,
        'total': 0.0,
        'pointsEarned': 0,
        'pointsSpent': cost,
        'status': 'Pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      final updatedPoints = _points - cost;
      setState(() {
        _points = updatedPoints;
      });
      widget.onPointsUpdated(updatedPoints);

      messenger.showSnackBar(
        SnackBar(
          content: Text('Redeemed "$title" for $cost Pts!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Redemption failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sunlit Sip Points Shop'),
        backgroundColor: Colors.brown[800],
        foregroundColor: Colors.white,
        actions: [
          if (widget.isAdmin)
            IconButton(
              tooltip: 'Add Reward',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _showRewardDialog(),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Available Points Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber[400]!),
            ),
            child: Row(
              children: [
                const Icon(Icons.stars, color: Colors.amber, size: 36),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Available Reward Points',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$_points Pts',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Redeemable Rewards',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          // Rewards List from Firestore
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rewards')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No rewards available right now.'),
                  );
                }

                // Sort cheapest rewards first
                final sortedDocs = docs.toList()
                  ..sort((a, b) {
                    final aCost =
                        _extractCost(a.data() as Map<String, dynamic>);
                    final bCost =
                        _extractCost(b.data() as Map<String, dynamic>);
                    return aCost.compareTo(bCost);
                  });

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sortedDocs.length,
                  itemBuilder: (context, index) {
                    final doc = sortedDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final title = data['title'] as String? ?? 'Reward';
                    final description = data['description'] as String? ?? '';
                    final cost = _extractCost(data);
                    final canAfford = _points >= cost;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.amber[100],
                          child: Icon(
                            Icons.card_giftcard,
                            color: Colors.brown[700],
                          ),
                        ),
                        title: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('$description\nCost: $cost Pts'),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: canAfford
                                    ? Colors.brown[700]
                                    : Colors.grey[300],
                                foregroundColor: canAfford
                                    ? Colors.white
                                    : Colors.grey[600],
                                elevation: canAfford ? 2 : 0,
                                shape: const StadiumBorder(),
                              ),
                              onPressed: canAfford
                                  ? () => _redeemReward(doc.id, title, cost)
                                  : null,
                              child: Text(canAfford ? 'Redeem' : 'Need $cost'),
                            ),
                            if (widget.isAdmin) ...[
                              IconButton(
                                tooltip: 'Edit Reward',
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                onPressed: () =>
                                    _showRewardDialog(existingDoc: doc),
                              ),
                              IconButton(
                                tooltip: 'Delete Reward',
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () => _deleteReward(doc.id),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}