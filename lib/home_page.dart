import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Services/user_sunlit_sip.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final user = FirebaseAuth.instance.currentUser!;

  List<SunlitSipItem> menuItems = [];
  bool isLoading = true;
  String errorMessage = '';

  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    loadMenuItems();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadMenuItems() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final items = await SunlitSipApiService.fetchMenuItems();
      setState(() {
        menuItems = items;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Network error: $e';
        isLoading = false;
      });
    }
  }

  List<SunlitSipItem> get filteredMenuItems {
    if (searchQuery.trim().isEmpty) {
      return menuItems;
    }
    return menuItems.where((item) {
      final titleMatch = item.title.toLowerCase().contains(searchQuery.toLowerCase());
      final descMatch = item.description.toLowerCase().contains(searchQuery.toLowerCase());
      return titleMatch || descMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Sunlit Sip Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color.fromARGB(255, 114, 69, 24),
        foregroundColor: Colors.white,
      ),

      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                color: Color.fromARGB(255, 114, 69, 24),
              ),
              accountName: const Text(
                'Valued Customer',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              accountEmail: Text(user.email ?? 'No email available'),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.amber,
                child: Icon(
                  Icons.person,
                  color: Color.fromARGB(255, 114, 69, 24),
                  size: 40,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.coffee,
                color: Color.fromARGB(255, 114, 69, 24),
              ),
              title: const Text('Menu Items'),
              onTap: () {
                Navigator.pop(context);
                loadMenuItems();
              },
            ),
            ListTile(
              leading: const Icon(Icons.stars, color: Colors.amber),
              title: const Text('Loyalty Wallet (50 Pts)'),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(
                Icons.receipt_long,
                color: Color.fromARGB(255, 114, 69, 24),
              ),
              title: const Text('My Orders'),
              onTap: () {},
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Sign Out'),
              onTap: () {
                Navigator.pop(context);
                FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade800, width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.stars, color: Colors.amber, size: 40),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '1:1 Loyalty Wallet Balance',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '50 Points (₱50.00 Value)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.brown[900],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sunlit Sip Menu',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown[900],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    color: Color.fromARGB(255, 114, 69, 24),
                  ),
                  onPressed: loadMenuItems,
                  tooltip: 'Reload Menu',
                ),
              ],
            ),
            const SizedBox(height: 8),

            TextField(
              controller: searchController,
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search coffee or description...',
                prefixIcon: const Icon(
                  Icons.search,
                  color: Color.fromARGB(255, 114, 69, 24),
                ),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          setState(() {
                            searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color.fromARGB(255, 114, 69, 24),
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(
                    color: Color.fromARGB(255, 114, 69, 24),
                  ),
                ),
              )
            else if (errorMessage.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    errorMessage,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              )
            else if (filteredMenuItems.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    'No items match your search.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredMenuItems.length,
                itemBuilder: (context, index) {
                  final item = filteredMenuItems[index];
                  return _buildProductCard(
                    name: item.title,
                    category: item.description,
                    price: item.price,
                    pointsEarned: item.points,
                  );
                },
              ),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color.fromARGB(255, 114, 69, 24),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.shopping_bag),
        label: const Text('View Cart'),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Opening Shopping Cart...')),
          );
        },
      ),
    );
  }

  Widget _buildProductCard({
    required String name,
    required String category,
    required String price,
    required String pointsEarned,
  }) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Container(
              width: 55,
              height: 55,
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.coffee,
                color: Color.fromARGB(255, 114, 69, 24),
                size: 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    category,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        price,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 114, 69, 24),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber[800],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          pointsEarned,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 114, 69, 24),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {},
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}