import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OrdersPage extends StatefulWidget {
  final String userEmail;
  final bool isAdmin;

  const OrdersPage({
    super.key,
    required this.userEmail,
    required this.isAdmin,
  });

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  String _selectedFilter = 'All';

  Stream<QuerySnapshot> get _ordersStream {
    final collection = FirebaseFirestore.instance.collection('orders');
    if (widget.isAdmin) {
      return collection.snapshots();
    }
    return collection
        .where('userEmail', isEqualTo: widget.userEmail)
        .snapshots();
  }

  String _formatTimestamp(dynamic rawTimestamp) {
    if (rawTimestamp is! Timestamp) return 'Just now';
    final dt = rawTimestamp.toDate().toLocal();

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final month = months[dt.month - 1];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';

    return '$month ${dt.day}, ${dt.year} • $hour12:$minute $period';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Completed':
        return Colors.green;
      case 'Cancelled':
        return Colors.redAccent;
      default:
        return Colors.amber[800]!;
    }
  }

  Future<void> _updateOrderStatus({
    required DocumentSnapshot orderDoc,
    required String newStatus,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final data = orderDoc.data() as Map<String, dynamic>;
    final currentStatus = data['status'] as String? ?? 'Pending';

    if (currentStatus == newStatus) return;

    final orderEmail =
        (data['userEmail'] as String? ?? '').toLowerCase().trim();
    final int pointsSpent = (data['pointsSpent'] as num?)?.toInt() ?? 0;
    final int pointsEarned = (data['pointsEarned'] as num?)?.toInt() ?? 0;

    try {
      // 1. Credit earned points ONLY when Admin completes a Pending order
      if (newStatus == 'Completed' && currentStatus == 'Pending') {
        if (orderEmail.isNotEmpty && pointsEarned > 0) {
          final walletRef =
              FirebaseFirestore.instance.collection('users').doc(orderEmail);
          await walletRef.set({
            'email': orderEmail,
            'loyaltyPoints': FieldValue.increment(pointsEarned),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      // 2. Refund spent/redeemed points if a Pending order is cancelled
      if (newStatus == 'Cancelled' && currentStatus == 'Pending') {
        if (orderEmail.isNotEmpty && pointsSpent > 0) {
          final walletRef =
              FirebaseFirestore.instance.collection('users').doc(orderEmail);
          await walletRef.set({
            'email': orderEmail,
            'loyaltyPoints': FieldValue.increment(pointsSpent),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      await orderDoc.reference.update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      String feedback;
      if (newStatus == 'Completed') {
        feedback = pointsEarned > 0
            ? 'Order completed! +$pointsEarned Pts credited to customer.'
            : 'Order marked as Completed!';
      } else if (newStatus == 'Cancelled') {
        feedback = pointsSpent > 0
            ? 'Order cancelled & $pointsSpent redeemed Pts refunded.'
            : 'Order cancelled.';
      } else {
        feedback = 'Order marked as $newStatus!';
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(feedback),
          backgroundColor:
              newStatus == 'Cancelled' ? Colors.redAccent : Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update order: $e')),
      );
    }
  }

  void _confirmCancel(DocumentSnapshot orderDoc) {
    final data = orderDoc.data() as Map<String, dynamic>;
    final int pointsSpent = (data['pointsSpent'] as num?)?.toInt() ?? 0;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Order'),
          content: Text(
            pointsSpent > 0
                ? 'Are you sure you want to cancel this order? Your $pointsSpent redeemed points will be refunded to your wallet.'
                : 'Are you sure you want to cancel this order?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Keep Order'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                _updateOrderStatus(
                  orderDoc: orderDoc,
                  newStatus: 'Cancelled',
                );
              },
              child: const Text(
                'Yes, Cancel',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAdminSummaryCard(List<QueryDocumentSnapshot> allDocs) {
    double completedRevenue = 0.0;
    int pendingCount = 0;
    int completedCount = 0;
    int cancelledCount = 0;
    int pointsIssued = 0;
    int pointsRedeemed = 0;

    for (final doc in allDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] as String? ?? 'Pending';
      final total = (data['total'] as num?)?.toDouble() ?? 0.0;
      final earned = (data['pointsEarned'] as num?)?.toInt() ?? 0;
      final spent = (data['pointsSpent'] as num?)?.toInt() ?? 0;

      if (status == 'Completed') {
        completedCount++;
        completedRevenue += total;
        pointsIssued += earned;
      } else if (status == 'Cancelled') {
        cancelledCount++;
      } else {
        pendingCount++;
      }

      if (status != 'Cancelled') {
        pointsRedeemed += spent;
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.brown[900]!, Colors.brown[700]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.analytics_outlined,
                      color: Colors.amber[400], size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Store Sales & Loyalty Summary',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber[700],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Completed Revenue',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            '₱${completedRevenue.toStringAsFixed(2)}',
            style: TextStyle(
              color: Colors.amber[300],
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(color: Colors.white24, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricColumn(
                label: 'Pending',
                value: '$pendingCount',
                color: Colors.amber[300]!,
              ),
              _buildMetricColumn(
                label: 'Completed',
                value: '$completedCount',
                color: Colors.greenAccent,
              ),
              _buildMetricColumn(
                label: 'Cancelled',
                value: '$cancelledCount',
                color: Colors.red[200]!,
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Points Issued: +$pointsIssued Pts',
                style: TextStyle(
                  color: Colors.amber[200],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Redeemed: -$pointsRedeemed Pts',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filters = ['All', 'Pending', 'Completed', 'Cancelled'];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'All Store Orders' : 'My Orders'),
        backgroundColor: Colors.brown[800],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Error loading orders: ${snapshot.error}'),
            );
          }

          final rawDocs = snapshot.data?.docs.toList() ?? [];

          // Sort newest-first (null serverTimestamp treated as newest)
          rawDocs.sort((a, b) {
            final aTs =
                (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final bTs =
                (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return -1;
            if (bTs == null) return 1;
            return bTs.compareTo(aTs);
          });

          final docs = _selectedFilter == 'All'
              ? rawDocs
              : rawDocs.where((doc) {
                  final status = (doc.data()
                          as Map<String, dynamic>)['status'] as String? ??
                      'Pending';
                  return status == _selectedFilter;
                }).toList();

          return Column(
            children: [
              // Admin-only Sales & Revenue Overview Card
              if (widget.isAdmin) _buildAdminSummaryCard(rawDocs),
              // Status Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: filters.map((filter) {
                    final selected = _selectedFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(filter),
                        selected: selected,
                        selectedColor: Colors.brown[700],
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) {
                          setState(() {
                            _selectedFilter = filter;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              // Orders List
              Expanded(
                child: docs.isEmpty
                    ? Center(
                        child: Text(
                          _selectedFilter == 'All'
                              ? 'No orders yet.'
                              : 'No $_selectedFilter orders.',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final status = data['status'] as String? ?? 'Pending';
                          final customerEmail =
                              data['userEmail'] as String? ?? 'Unknown';
                          final total =
                              (data['total'] as num?)?.toDouble() ?? 0.0;
                          final discount =
                              (data['discount'] as num?)?.toDouble() ?? 0.0;
                          final pointsEarned =
                              (data['pointsEarned'] as num?)?.toInt() ?? 0;
                          final pointsSpent =
                              (data['pointsSpent'] as num?)?.toInt() ?? 0;
                          final timeText = _formatTimestamp(data['createdAt']);
                          final items =
                              (data['items'] as List<dynamic>?) ?? [];

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header: Timestamp & Status Badge
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.access_time,
                                              size: 15, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(
                                            timeText,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _statusColor(status)
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: _statusColor(status),
                                          ),
                                        ),
                                        child: Text(
                                          status,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _statusColor(status),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.isAdmin) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Customer: $customerEmail',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.brown[800],
                                      ),
                                    ),
                                  ],
                                  const Divider(height: 18),
                                  // Ordered Items
                                  ...items.map((rawItem) {
                                    final item =
                                        rawItem as Map<String, dynamic>;
                                    final title = item['title'] ?? 'Item';
                                    final qty = item['quantity'] ?? 1;
                                    final price =
                                        (item['price'] as num?)?.toDouble() ??
                                            0.0;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${qty}x $title',
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                          ),
                                          Text(
                                            '₱${(price * qty).toStringAsFixed(2)}',
                                            style:
                                                const TextStyle(fontSize: 14),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  const Divider(height: 18),
                                  // Totals & Loyalty Summary
                                  if (discount > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Loyalty Discount:',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.green,
                                            ),
                                          ),
                                          Text(
                                            '-₱${discount.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Total: ₱${total.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          if (pointsEarned > 0 &&
                                              status != 'Cancelled')
                                            Text(
                                              status == 'Completed'
                                                  ? '+$pointsEarned Pts '
                                                  : '+$pointsEarned Pts (pending) ',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: status == 'Completed'
                                                    ? Colors.amber[800]
                                                    : Colors.grey[600],
                                              ),
                                            ),
                                          if (pointsSpent > 0)
                                            Text(
                                              '(-$pointsSpent Pts)',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.redAccent,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  // Action Buttons for Pending Orders
                                  if (status == 'Pending') ...[
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.redAccent,
                                            side: const BorderSide(
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                          onPressed: () => _confirmCancel(doc),
                                          child: Text(
                                            widget.isAdmin
                                                ? 'Cancel Order'
                                                : 'Cancel My Order',
                                          ),
                                        ),
                                        if (widget.isAdmin) ...[
                                          const SizedBox(width: 8),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                            ),
                                            onPressed: () => _updateOrderStatus(
                                              orderDoc: doc,
                                              newStatus: 'Completed',
                                            ),
                                            icon: const Icon(Icons.check,
                                                size: 18),
                                            label: const Text('Complete'),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
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
    );
  }
}