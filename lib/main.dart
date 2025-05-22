import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

void main() => runApp(const MonApp());

class MonApp extends StatelessWidget {
  const MonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anti-Gaspillage',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const EcranPrincipal(),
    );
  }
}

class EcranPrincipal extends StatefulWidget {
  const EcranPrincipal({super.key});

  @override
  State<EcranPrincipal> createState() => _EcranPrincipalState();
}

class _EcranPrincipalState extends State<EcranPrincipal> {
  int _selectedIndex = 2;

  final List<Widget> _screens = const [
    CalendrierEcran(),
    ListeCoursesEcran(),
    AccueilEcran(),
    RecettesEcran(),
    ProfilEcran(),
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
        unselectedItemColor: Colors.grey,
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

class AccueilEcran extends StatefulWidget {
  const AccueilEcran({super.key});

  @override
  State<AccueilEcran> createState() => _AccueilEcranState();
}

class _AccueilEcranState extends State<AccueilEcran> {
  final List<Map<String, dynamic>> produits = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accueil'),
                    backgroundColor: Colors.green),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (var p in produits)
            Card(
              child: ListTile(
                title: Text(p['name']),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(p['date'])),
                leading: const Icon(Icons.fastfood),
              ),
            ),
          const SizedBox(height: 20),
          Center(
            child: FloatingActionButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanEcran()));
              },
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }
}

class ScanEcran extends StatefulWidget {
  const ScanEcran({super.key});

  @override
  State<ScanEcran> createState() => _ScanEcranState();
}

class _ScanEcranState extends State<ScanEcran> {
  final TextEditingController _controller = TextEditingController();

  void _valider() {
    final texte = _controller.text;
    final entier = int.tryParse(texte);
    if (entier != null) {
      print('Code barre saisi : $entier');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultatScanEcran(nomProduit: texte),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez saisir un numéro valide')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
              onPressed: _valider,              
              child: const Text('VALIDER'),
            ),
          ],
        ),
      ),
    );
  }
}

class ResultatScanEcran extends StatefulWidget {
  final String nomProduit;
  const ResultatScanEcran({super.key, required this.nomProduit});

  @override
  State<ResultatScanEcran> createState() => _ResultatScanEcranState();
}

class _ResultatScanEcranState extends State<ResultatScanEcran> {
  final TextEditingController _dateController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Réussi')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.shopping_basket),
              title: Text(widget.nomProduit.isEmpty ? 'Produit Scanné' : widget.nomProduit),
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

class RecettesEcran extends StatefulWidget {
  const RecettesEcran({super.key});

  @override
  State<RecettesEcran> createState() => _RecettesEcranState();
}

class _RecettesEcranState extends State<RecettesEcran> {
  final List<Map<String, dynamic>> recettes = [];

  @override
  Widget build(BuildContext context) {
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
          for (var recette in recettes)
            Card(
              child: ListTile(
                title: Text(recette['name']),
                trailing: const Text('Détails >'),
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(recette['name']),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: (recette['ingredients'] as List<String>)
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

class ListeCoursesEcran extends StatefulWidget {
  const ListeCoursesEcran({super.key});

  @override
  State<ListeCoursesEcran> createState() => _ListeCoursesEcranState();
}

class _ListeCoursesEcranState extends State<ListeCoursesEcran> {
  final List<String> items = [];
  final Map<String, bool> completed = {};

  @override
  void initState() {
    super.initState();
    for (var item in items) {
      completed[item] = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Liste de courses')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (var item in items)
            CheckboxListTile(
              title: Text(item),
              value: completed[item],
              onChanged: (val) {
                setState(() {
                  completed[item] = val!;
                });
              },
            ),
          const Divider(),
          ElevatedButton(onPressed: () {}, child: const Text('Voir les recettes associées')),
          ElevatedButton(onPressed: () {}, child: const Text('Supprimer ce(s) produit(s)')),
        ],
      ),
    );
  }
}

class CalendrierEcran extends StatefulWidget {
  const CalendrierEcran({super.key});

  @override
  State<CalendrierEcran> createState() => _CalendrierEcranState();
}

class _CalendrierEcranState extends State<CalendrierEcran> {
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

class ProfilEcran extends StatefulWidget {
  const ProfilEcran({super.key});

  @override
  State<ProfilEcran> createState() => _ProfilEcranState();
}

class _ProfilEcranState extends State<ProfilEcran> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: const Center(child: Text('Fonctionnalités à venir...')),
    );
  }
}
