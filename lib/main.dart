import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';
import 'dart:io';

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
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Calendrier',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Liste'),
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Accueil'),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: 'Recettes',
          ),
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
  List<Map<String, dynamic>> produits = [];

  void _ajouterProduit(Map<String, dynamic> produit) {
    setState(() {
      produits.add(produit);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accueil'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.green,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (var p in produits)
            Card(
              child: ListTile(
                title: Text(p['name']),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(p['date'])),
                leading: const Icon(Icons.food_bank_outlined),
              ),
            ),
          const SizedBox(height: 20),
          Center(
            child: FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(builder: (_) => ScanEcran()),
                );
                if (result != null) {
                  _ajouterProduit(result);
                }
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
  @override
  _ScanEcranState createState() => _ScanEcranState();
}

class _ScanEcranState extends State<ScanEcran> {
  String codeBarres = '';

  Future<void> _scannerCodeBarres() async {
    try {
      var result = await BarcodeScanner.scan(
        options: ScanOptions(
          strings: {'cancel': 'Annuler'},
          restrictFormat: [
            BarcodeFormat.code128,
            BarcodeFormat.ean13,
          ], // adapte selon besoin
          useCamera: -1, // caméra arrière par défaut
          autoEnableFlash: true,
        ),
      );

      if (result.type == ResultType.Barcode) {
        setState(() => codeBarres = result.rawContent);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResultatEcranScan(
              nomProduit: _nomDepuisCodeBarres(result.rawContent),
            ),
          ),
        );
      } else if (result.type == ResultType.Cancelled) {
        // L’utilisateur a annulé le scan
      }
    } catch (e) {
      // Gestion d'erreur
      print('Erreur lors du scan : $e');
    }
  }

  String _nomDepuisCodeBarres(String code) {
    // Remplacer par une vraie base de données ou API
    return ' $code';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Code-Barres')),
      body: Center(
        child: ElevatedButton(
          onPressed: _scannerCodeBarres,
          child: const Text('Scanner un code-barres'),
        ),
      ),
    );
  }
}

class ResultatEcranScan extends StatefulWidget {
  final String nomProduit; // Reçu depuis ScanEcran

  const ResultatEcranScan({Key? key, required this.nomProduit})
    : super(key: key);

  @override
  State<ResultatEcranScan> createState() => _ResultatEcranScanState();
}

class _ResultatEcranScanState extends State<ResultatEcranScan> {
  final TextEditingController _dateController = TextEditingController();
  File? _imageDate;
  String _dateScannee = '';

  Future<void> _scanDatePeremption() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.camera,
    );
    if (pickedFile != null) {
      final text = await TesseractOcr.extractText(pickedFile.path);
      setState(() {
        _imageDate = File(pickedFile.path);
        _dateScannee = text;
        _dateController.text = _extractDate(text);
      });
    }
  }

  String _extractDate(String text) {
    // Exemple : chercher une date de type JJ/MM/AAAA ou similaire
    final regex = RegExp(r'(\d{2}[\/\-\.]\d{2}[\/\-\.]\d{4})');
    final match = regex.firstMatch(text);
    return match != null ? match.group(0)! : text;
  }

  void _enregistrer() {
    String date = _dateController.text.trim();
    if (date.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez entrer ou scanner une date de péremption.'),
        ),
      );
      return;
    }

    // Enregistrement des données ici
    // Par exemple : envoyer vers une base de données ou Provider

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Produit enregistré avec succès !')),
    );

    Navigator.pop(context);
  }

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Résultat du scan')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Produit : ${widget.nomProduit}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _dateController,
              decoration: const InputDecoration(
                labelText: 'Date de péremption',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _scanDatePeremption,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scanner la date de péremption'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _enregistrer,
              child: const Text('Enregistrer le produit'),
            ),
            if (_imageDate != null) ...[
              const SizedBox(height: 24),
              const Text('Aperçu de l\'image scannée :'),
              const SizedBox(height: 8),
              Image.file(_imageDate!, height: 150),
            ],
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
  List<Map<String, dynamic>> recettes = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recettes'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.green,
      ),
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
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fermer'),
                      ),
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
      appBar: AppBar(
        title: const Text('Liste de courses'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.green,
      ),
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
          ElevatedButton(
            onPressed: () {},
            child: const Text('Voir les recettes associées'),
          ),
          ElevatedButton(
            onPressed: () {},
            child: const Text('Supprimer ce(s) produit(s)'),
          ),
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
      appBar: AppBar(
        title: const Text('Calendrier'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.green,
      ),
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
