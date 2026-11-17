import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Services/user_sunlit_sip.dart';
import 'orders_page.dart';
import 'points_shop_page.dart';

class CartEntry {
  final SunlitSipItem item;
  int quantity;

  CartEntry({required this.item, this.quantity = 1});

  double get unitPrice {
    final numeric = item.price.replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(numeric) ?? 0.0;
  }

  double get totalPrice => unitPrice * quantity;
}

class HomePage extends StatefulWidget {
  final String userEmail;

  const HomePage({super.key, required this.userEmail});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Search, Category Filter & Cart state
  String _searchQuery = '';
  String _selectedCategory = 'All'; // 'All', 'Drinks', 'Foods'
  final Map<String, CartEntry> _cart = {};
  bool _usePointsDiscount = false;
  int _userLoyaltyPoints = 50;
  StreamSubscription? _walletSub;

  bool get isAdmin =>
      widget.userEmail.toLowerCase() == 'jumirson.jumawan@jmc.edu.ph';

  String get _userDocId => widget.userEmail.trim().isEmpty
      ? 'guest@sunlitsip.com'
      : widget.userEmail.toLowerCase().trim();

  DocumentReference get _userWalletRef =>
      FirebaseFirestore.instance.collection('users').doc(_userDocId);

  Stream<QuerySnapshot> get _pendingOrdersStream {
    final ordersRef = FirebaseFirestore.instance.collection('orders');
    if (isAdmin) {
      return ordersRef.where('status', isEqualTo: 'Pending').snapshots();
    }
    return ordersRef
        .where('userEmail', isEqualTo: widget.userEmail)
        .where('status', isEqualTo: 'Pending')
        .snapshots();
  }

  @override
  void initState() {
    super.initState();
    _initAndListenWallet();
  }

  Future<void> _initAndListenWallet() async {
    final doc = await _userWalletRef.get();
    if (!doc.exists) {
      await _userWalletRef.set({
        'email': widget.userEmail,
        'loyaltyPoints': 50,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    _walletSub = _userWalletRef.snapshots().listen((snapshot) {
      if (!mounted) return;
      final data = snapshot.data() as Map<String, dynamic>?;
      if (data != null && data.containsKey('loyaltyPoints')) {
        setState(() {
          _userLoyaltyPoints =
              (data['loyaltyPoints'] as num?)?.toInt() ?? 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _walletSub?.cancel();
    super.dispose();
  }

  int _parseItemPoints(String pointsStr) {
    final numeric = pointsStr.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(numeric) ?? 0;
  }

  int get _cartEarnedPoints {
    return _cart.values.fold(0, (acc, entry) {
      return acc + (_parseItemPoints(entry.item.points) * entry.quantity);
    });
  }

  double get _subtotal {
    return _cart.values.fold(0.0, (acc, entry) => acc + entry.totalPrice);
  }

  double get _discount {
    if (!_usePointsDiscount) return 0.0;
    return _userLoyaltyPoints > _subtotal
        ? _subtotal
        : _userLoyaltyPoints.toDouble();
  }

  double get _finalTotal => (_subtotal - _discount).clamp(0.0, double.infinity);

  int get _totalCartItems {
    return _cart.values.fold(0, (acc, entry) => acc + entry.quantity);
  }

  void _openOrdersPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrdersPage(
          userEmail: widget.userEmail,
          isAdmin: isAdmin,
        ),
      ),
    );
  }

  void _addToCart(SunlitSipItem item) {
    setState(() {
      if (_cart.containsKey(item.id)) {
        _cart[item.id]!.quantity++;
      } else {
        _cart[item.id] = CartEntry(item: item);
      }
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.title} added to cart!'),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.brown[700],
      ),
    );
  }

  void _removeFromCart(String itemId) {
    setState(() {
      if (_cart.containsKey(itemId)) {
        if (_cart[itemId]!.quantity > 1) {
          _cart[itemId]!.quantity--;
        } else {
          _cart.remove(itemId);
        }
      }
    });
  }

  void _showCheckoutSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Your Order',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        )
                      ],
                    ),
                    const Divider(),
                    if (_cart.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: Text('Your cart is empty.')),
                      )
                    else
                      Column(
                        children: _cart.values.map((entry) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.item.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                '₱${entry.unitPrice.toStringAsFixed(2)} x ${entry.quantity}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      color: Colors.redAccent),
                                  onPressed: () {
                                    _removeFromCart(entry.item.id);
                                    setModalState(() {});
                                    setState(() {});
                                  },
                                ),
                                Text('${entry.quantity}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline,
                                      color: Colors.green),
                                  onPressed: () {
                                    _addToCart(entry.item);
                                    setModalState(() {});
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    const Divider(),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Redeem Points ($_userLoyaltyPoints Pts = ₱$_userLoyaltyPoints.00)',
                        style: const TextStyle(fontSize: 14),
                      ),
                      value: _usePointsDiscount,
                      onChanged: _userLoyaltyPoints > 0
                          ? (val) {
                              setModalState(() {
                                _usePointsDiscount = val ?? false;
                              });
                              setState(() {});
                            }
                          : null,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal:'),
                        Text('₱${_subtotal.toStringAsFixed(2)}'),
                      ],
                    ),
                    if (_usePointsDiscount)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Loyalty Discount:',
                              style: TextStyle(color: Colors.green)),
                          Text('-₱${_discount.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.green)),
                        ],
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Points on Completion:',
                            style: TextStyle(color: Colors.amber)),
                        Text('+$_cartEarnedPoints Pts',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.amber[800])),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total:',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('₱${_finalTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.brown)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.brown[700],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed:
                            _cart.isEmpty ? null : () => _placeOrder(context),
                        child: const Text('Place Order',
                            style:
                                TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _placeOrder(BuildContext modalContext) async {
    final int earnedPoints = _cartEarnedPoints;
    final int spentPoints = _usePointsDiscount ? _discount.toInt() : 0;

    final orderData = {
      'userEmail': widget.userEmail,
      'items': _cart.values
          .map((e) => {
                'id': e.item.id,
                'title': e.item.title,
                'price': e.unitPrice,
                'quantity': e.quantity,
              })
          .toList(),
      'subtotal': _subtotal,
      'discount': _discount,
      'total': _finalTotal,
      'pointsEarned': earnedPoints,
      'pointsSpent': spentPoints,
      'status': 'Pending',
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      final navigator = Navigator.of(modalContext);
      final messenger = ScaffoldMessenger.of(context);

      await FirebaseFirestore.instance.collection('orders').add(orderData);

      // Deduct redeemed points immediately so they cannot be double-spent;
      // earnedPoints will be credited once Admin completes the order.
      if (spentPoints > 0) {
        await _userWalletRef.set({
          'email': widget.userEmail,
          'loyaltyPoints': FieldValue.increment(-spentPoints),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      setState(() {
        _usePointsDiscount = false;
        _cart.clear();
      });

      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            earnedPoints > 0
                ? 'Order placed! You will earn +$earnedPoints Pts once completed ☕'
                : 'Order placed! ☕',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to place order: $e')),
        );
      }
    }
  }

  void _showAddOrEditDialog([SunlitSipItem? existingItem]) {
    final nameController =
        TextEditingController(text: existingItem?.title ?? '');
    final descController =
        TextEditingController(text: existingItem?.description ?? '');
    final priceController =
        TextEditingController(text: existingItem?.price ?? '₱160.00');
    final pointsController =
        TextEditingController(text: existingItem?.points ?? '+16 Pts');
    String selectedTag = existingItem?.category ?? 'Drink';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                  existingItem == null ? 'Add Menu Item' : 'Edit Menu Item'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Category Tag',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            avatar: Icon(
                              Icons.local_cafe,
                              size: 18,
                              color: selectedTag == 'Drink'
                                  ? Colors.white
                                  : Colors.brown[700],
                            ),
                            label: const Text('Drink'),
                            selected: selectedTag == 'Drink',
                            selectedColor: Colors.brown[700],
                            labelStyle: TextStyle(
                              color: selectedTag == 'Drink'
                                  ? Colors.white
                                  : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) {
                              setDialogState(() {
                                selectedTag = 'Drink';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            avatar: Icon(
                              Icons.bakery_dining,
                              size: 18,
                              color: selectedTag == 'Food'
                                  ? Colors.white
                                  : Colors.amber[900],
                            ),
                            label: const Text('Food'),
                            selected: selectedTag == 'Food',
                            selectedColor: Colors.amber[800],
                            labelStyle: TextStyle(
                              color: selectedTag == 'Food'
                                  ? Colors.white
                                  : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) {
                              setDialogState(() {
                                selectedTag = 'Food';
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration:
                          const InputDecoration(labelText: 'Item Name'),
                    ),
                    TextField(
                      controller: descController,
                      decoration:
                          const InputDecoration(labelText: 'Description'),
                    ),
                    TextField(
                      controller: priceController,
                      decoration: const InputDecoration(labelText: 'Price'),
                    ),
                    TextField(
                      controller: pointsController,
                      decoration: const InputDecoration(labelText: 'Points'),
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
                      backgroundColor: Colors.brown[700]),
                  onPressed: () async {
                    final navigator = Navigator.of(dialogContext);
                    final messenger = ScaffoldMessenger.of(context);

                    final newItem = SunlitSipItem(
                      id: existingItem?.id ?? '',
                      title: nameController.text.trim(),
                      description: descController.text.trim(),
                      price: priceController.text.trim(),
                      points: pointsController.text.trim(),
                      category: selectedTag,
                    );

                    if (existingItem == null) {
                      await SunlitSipApiService.addMenuItem(newItem);
                    } else {
                      await SunlitSipApiService.updateMenuItem(
                          existingItem.id, newItem);
                    }

                    navigator.pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(existingItem == null
                            ? 'New $selectedTag item added!'
                            : 'Menu item updated!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  child: const Text('Save Item',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleDeleteItem(String id) async {
    await SunlitSipApiService.deleteMenuItem(id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item deleted successfully!'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryFilters = ['All', 'Drinks', 'Foods'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sunlit Sip Dashboard'),
        backgroundColor: Colors.brown[800],
        foregroundColor: Colors.white,
        actions: [
          // Live Pending Orders Badge Button in AppBar
          StreamBuilder<QuerySnapshot>(
            stream: _pendingOrdersStream,
            builder: (context, snapshot) {
              final pendingCount = snapshot.data?.docs.length ?? 0;
              return IconButton(
                tooltip: isAdmin ? 'Pending Store Orders' : 'My Pending Orders',
                onPressed: _openOrdersPage,
                icon: Badge(
                  isLabelVisible: pendingCount > 0,
                  label: Text('$pendingCount'),
                  backgroundColor: Colors.amber[700],
                  textColor: Colors.white,
                  child: const Icon(Icons.receipt_long),
                ),
              );
            },
          ),
        ],
      ),
      // Side Navigation Drawer
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: Colors.brown[800]),
              accountName: Text(
                isAdmin ? 'Admin User' : 'Sunlit Sip Customer',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              accountEmail: Text(widget.userEmail.isNotEmpty
                  ? widget.userEmail
                  : 'guest@sunlitsip.com'),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.amber[400],
                child: Icon(
                  isAdmin ? Icons.admin_panel_settings : Icons.person,
                  size: 40,
                  color: Colors.brown[900],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.restaurant_menu, color: Colors.brown),
              title: const Text('Cafe Menu'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.stars, color: Colors.amber),
              title: Text('Points Shop ($_userLoyaltyPoints Pts)'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PointsShopPage(
                      userEmail: widget.userEmail,
                      isAdmin: isAdmin,
                      currentPoints: _userLoyaltyPoints,
                      onPointsUpdated: (updatedPoints) {
                        setState(() {
                          _userLoyaltyPoints = updatedPoints;
                        });
                      },
                    ),
                  ),
                );
              },
            ),
            // My Orders with Live Pending Badge
            StreamBuilder<QuerySnapshot>(
              stream: _pendingOrdersStream,
              builder: (context, snapshot) {
                final pendingCount = snapshot.data?.docs.length ?? 0;
                return ListTile(
                  leading: const Icon(Icons.receipt_long, color: Colors.brown),
                  title: Text(isAdmin ? 'Store Orders' : 'My Orders'),
                  trailing: pendingCount > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber[800],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$pendingCount pending',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _openOrdersPage();
                  },
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Logout',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(context);
                await FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Loyalty Balance Header Card
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
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
                    const Text('1:1 Loyalty Wallet Balance',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    Text(
                      '$_userLoyaltyPoints Points (₱$_userLoyaltyPoints.00 Value)',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Section Title & Admin Add Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sunlit Sip Menu',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (isAdmin)
                  IconButton(
                    tooltip: 'Add Menu Item',
                    icon: const Icon(Icons.add_circle,
                        color: Colors.brown, size: 28),
                    onPressed: () => _showAddOrEditDialog(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search drinks, pastries, or description...',
                prefixIcon: const Icon(Icons.search),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          // Category Filter Buttons (All / Drinks / Foods)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: categoryFilters.map((filter) {
                final selected = _selectedCategory == filter;
                IconData? chipIcon;
                if (filter == 'Drinks') chipIcon = Icons.local_cafe;
                if (filter == 'Foods') chipIcon = Icons.bakery_dining;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: chipIcon != null
                        ? Icon(
                            chipIcon,
                            size: 16,
                            color: selected ? Colors.white : Colors.brown[700],
                          )
                        : null,
                    label: Text(filter),
                    selected: selected,
                    selectedColor: Colors.brown[700],
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _selectedCategory = filter;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          // Real-time Firestore Stream
          Expanded(
            child: StreamBuilder<List<SunlitSipItem>>(
              stream: SunlitSipApiService.getMenuItemsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                      child: Text('No menu items found in Firestore.'));
                }

                final items = snapshot.data!.where((item) {
                  // 1. Category filter check
                  if (_selectedCategory == 'Drinks' &&
                      item.category != 'Drink') {
                    return false;
                  }
                  if (_selectedCategory == 'Foods' &&
                      item.category != 'Food') {
                    return false;
                  }

                  // 2. Search text check
                  final q = _searchQuery.toLowerCase();
                  return item.title.toLowerCase().contains(q) ||
                      item.description.toLowerCase().contains(q);
                }).toList();

                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      _selectedCategory == 'All'
                          ? 'No menu items match your search.'
                          : 'No ${_selectedCategory.toLowerCase()} match your filter.',
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isFood = item.category == 'Food';

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              isFood ? Colors.amber[100] : Colors.brown[100],
                          child: Icon(
                            isFood ? Icons.bakery_dining : Icons.local_cafe,
                            color:
                                isFood ? Colors.amber[900] : Colors.brown[700],
                          ),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isFood
                                    ? Colors.amber[100]
                                    : Colors.brown[50],
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isFood
                                      ? Colors.amber[400]!
                                      : Colors.brown[200]!,
                                ),
                              ),
                              child: Text(
                                item.category,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isFood
                                      ? Colors.amber[900]
                                      : Colors.brown[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                            '${item.description}\n${item.price}  (${item.points})'),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.brown[700],
                              ),
                              onPressed: () => _addToCart(item),
                              child: const Text('Add',
                                  style: TextStyle(color: Colors.white)),
                            ),
                            if (isAdmin) ...[
                              IconButton(
                                icon:
                                    const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _showAddOrEditDialog(item),
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _handleDeleteItem(item.id),
                              ),
                            ]
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
      bottomNavigationBar: _cart.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.brown[900],
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6)
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_totalCartItems item${_totalCartItems > 1 ? 's' : ''} added',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        '₱${_subtotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[700],
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _showCheckoutSheet,
                    icon: const Icon(Icons.shopping_cart_checkout),
                    label: const Text('View Cart'),
                  ),
                ],
              ),
            ),
    );
  }
}