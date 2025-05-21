import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anti-Gaspillage',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 2; // Accueil au centre

  final List<Widget> _screens = const [
    CalendarScreen(),
    ShoppingListScreen(),
    HomeScreen(),
    RecipesScreen(),
    ProfileScreen(),
  ];

  void _onTap(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTap,
        selectedItemColor: Colors.green,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Calendrier'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Liste'),
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Accueil'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Recettes'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final products = [];

    return Scaffold(
      appBar: AppBar(title: const Text('Accueil')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (var p in products)
            Card(
              child: ListTile(
                title: Text(p['name'] as String),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(p['date'] as DateTime)),
                leading: const Icon(Icons.fastfood),
              ),
            ),
          const SizedBox(height: 20),
          Center(
            child: FloatingActionButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
              },
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }
}

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final TextEditingController _controller = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Expanded(child: Center(child: Icon(Icons.qr_code_scanner, size: 150))),
            const Text('Scan bientôt disponible'),
            const Divider(),
            const Text('OU SAISIR MANUELLEMENT'),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(hintText: 'Numéro du code barres'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScanResultScreen(nomProduit: _controller.text),
                  ),
                );
              },
              child: const Text('VALIDER'),
            ),
          ],
        ),
      ),
    );
  }
}

class ScanResultScreen extends StatelessWidget {
  final String nomProduit;
  const ScanResultScreen({super.key, required this.nomProduit});

  @override
  Widget build(BuildContext context) {
    final TextEditingController _dateController = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Réussi')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.shopping_basket),
              title: Text(nomProduit.isEmpty ? 'Produit Scanné' : nomProduit),
            ),
            const SizedBox(height: 10),
            const Text('Saisissez la date de péremption du produit'),
            TextField(
              controller: _dateController,
              decoration: const InputDecoration(hintText: 'jj/mm/aaaa'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: const Text('Valider'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Rescanner'),
            ),
          ],
        ),
      ),
    );
  }
}

class RecipesScreen extends StatelessWidget {
  const RecipesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final recipes = [];

    return Scaffold(
      appBar: AppBar(title: const Text('Recettes')),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: const [
              ElevatedButton(onPressed: null, child: Text('Filtre')),
              ElevatedButton(onPressed: null, child: Text('Trier par')),
            ],
          ),
          const SizedBox(height: 10),
          for (var recipe in recipes)
            Card(
              child: ListTile(
                title: Text(recipe['name'] as String),
                trailing: const Text('Détails >'),
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(recipe['name'] as String),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: (recipe['ingredients'] as List<String>)
                          .map((i) => Text('• $i'))
                          .toList(),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ShoppingListScreen extends StatelessWidget {
  const ShoppingListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final items = [];
    final Map<String, bool> completed = {for (var i in items) i: false};

    return Scaffold(
      appBar: AppBar(title: const Text('Liste de courses')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (var item in items)
            CheckboxListTile(
              title: Text(item),
              value: completed[item],
              onChanged: (val) {},
            ),
          const Divider(),
          ElevatedButton(onPressed: () {}, child: const Text('Voir les recettes associées')),
          ElevatedButton(onPressed: () {}, child: const Text('Supprimer ce(s) produit(s)')),
        ],
      ),
    );
  }
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  _CalendarScreenState createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendrier')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          calendarFormat: CalendarFormat.month,
          startingDayOfWeek: StartingDayOfWeek.monday,
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
          ),
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Profil')),
      body: Center(child: Text('Fonctionnalités à venir...')),
    );
  }
}
