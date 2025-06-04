import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class ProfilAvatarButton extends StatelessWidget {
  final String photoUrl;
  const ProfilAvatarButton({super.key, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfilEcran()),
        );
      },
      icon: CircleAvatar(backgroundImage: NetworkImage(photoUrl), radius: 18),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (response) {},
  );

  if (Platform.isAndroid) {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'expiration_channel',
      'Expiration Notifications',
      description: 'Notifications pour les produits proches de la péremption',
      importance: Importance.high,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  await Firebase.initializeApp()
      .then((_) {
        runApp(const MonApp());
      })
      .catchError((error) {
        print("Erreur lors de l'initialisation de Firebase : $error");
      });
}

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
            icon: Icon(Icons.restaurant),
            label: 'Recettes',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

class Course {
  final String nom;
  final bool achete;

  Course({required this.nom, this.achete = false});

  Map<String, dynamic> toMap() => {'nom': nom, 'achete': achete};

  static Course fromMap(Map<String, dynamic> map) =>
      Course(nom: map['nom'], achete: map['achete'] ?? false);
}

class AccueilEcran extends StatefulWidget {
  const AccueilEcran({super.key});

  @override
  State<AccueilEcran> createState() => _AccueilEcranState();
}

class _AccueilEcranState extends State<AccueilEcran> {
  List<Map<String, dynamic>> produits = [];

  @override
  void initState() {
    super.initState();
    _verifierProduitsPerimesEtNotifer(); // Vérifier au démarrage
  }

  Future<void> _verifierProduitsPerimesEtNotifer() async {
    final currentDate = DateTime.now();
    final snapshot = await FirebaseFirestore.instance
        .collection('produits')
        .get();
    final ingredientsExpiringSoon = <String>[];

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final rawDate = data['date_de_peremption'];
      DateTime? expirationDate;

      if (rawDate is String && rawDate.isNotEmpty) {
        try {
          expirationDate = DateTime.parse(rawDate);
        } catch (_) {
          try {
            expirationDate = DateFormat('dd/MM/yyyy').parseStrict(rawDate);
          } catch (_) {}
        }
      } else if (rawDate is Timestamp) {
        expirationDate = rawDate.toDate();
      }

      if (expirationDate != null) {
        final daysUntilExpiration = expirationDate
            .difference(currentDate)
            .inDays;
        if (daysUntilExpiration <= 2 && daysUntilExpiration >= 0) {
          if (data['nom'] != null && data['nom'].toString().isNotEmpty) {
            ingredientsExpiringSoon.add(data['nom'].toString());
          }
        }
      }
    }

    if (ingredientsExpiringSoon.isNotEmpty) {
      final recipeGenerator = _RecettesEcranState();
      final recettes = await recipeGenerator._genererRecette(
        ingredientsExpiringSoon,
      );

      if (recettes.isNotEmpty && recettes[0].titre.isNotEmpty) {
        final notificationDetails = const NotificationDetails(
          android: AndroidNotificationDetails(
            'expiration_channel',
            'Expiration Notifications',
            channelDescription:
                'Notifications pour les produits proches de la péremption',
            importance: Importance.high,
            priority: Priority.high,
          ),
        );

        await flutterLocalNotificationsPlugin.show(
          0,
          'Produits proches de la péremption',
          'Essayez cette recette : ${recettes[0].titre}',
          notificationDetails,
        );
      }
    }
  }

  void _ajouterProduit(Map<String, dynamic> produit) {
    FirebaseFirestore.instance
        .collection('produits')
        .add({
          'nom': produit['name'],
          'date_de_peremption': produit['date'].toIso8601String(),
          'ajoute_le': Timestamp.now().toString(),
          'image': produit['imageUrl'],
        })
        .then((value) {
          print("Produit ajouté avec ID : ${value.id}");
          _verifierProduitsPerimesEtNotifer();
        })
        .catchError((error) {
          print("Erreur lors de l'ajout : $error");
        });
  }

  void _ajouterListeDeCourses(Map<String, dynamic> produit) {
    FirebaseFirestore.instance
        .collection('courses')
        .add({'nom': produit['name'], 'achete': false})
        .then((value) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Ajouté à la liste de courses 🛒")),
          );
        })
        .catchError((error) {
          print("Erreur ajout liste de courses: $error");
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accueil'),
        foregroundColor: const Color.fromARGB(255, 0, 0, 0),
        actions: const [
          ProfilAvatarButton(
            photoUrl: "https://cdn-icons-png.flaticon.com/512/149/149071.png",
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('produits')
            .orderBy('date_de_peremption')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Erreur de chargement.'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final produits = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: produits.length,
            itemBuilder: (context, index) {
              final p = produits[index];
              final nom = p['nom'] ?? '';
              DateTime? date;
              try {
                date = DateTime.parse(p['date_de_peremption']);
              } catch (_) {
                try {
                  date = DateFormat(
                    'dd/MM/yyyy',
                  ).parse(p['date_de_peremption']);
                } catch (_) {}
              }
              final image = p['image'];
              final estPerime = date != null && date.isBefore(DateTime.now());
              final docId = p.id;
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                color: estPerime ? Colors.red[50] : Colors.white,
                elevation: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: image != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            image,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(Icons.fastfood, size: 40),
                  title: Text(
                    nom,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: estPerime ? Colors.red : Colors.black,
                    ),
                  ),
                  subtitle: Text(
                    date != null
                        ? 'Périme le ${DateFormat('dd/MM/yyyy').format(date)}'
                        : 'Date invalide',
                    style: TextStyle(
                      color: estPerime ? Colors.red : Colors.grey[700],
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final confirmation = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Supprimer le produit'),
                              content: const Text(
                                'Es-tu sûr de vouloir supprimer ce produit ?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Non'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Oui'),
                                ),
                              ],
                            ),
                          );

                          if (confirmation == true) {
                            FirebaseFirestore.instance
                                .collection('produits')
                                .doc(docId)
                                .delete();
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_shopping_cart,
                          color: Colors.green,
                        ),
                        tooltip: "Ajouter à la liste de courses",
                        onPressed: () {
                          _ajouterListeDeCourses(nom);
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ResultatEcranScan(nomProduit: nom, imageUrl: image),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
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
    );
  }
}

class ScanEcran extends StatefulWidget {
  @override
  _ScanEcranState createState() => _ScanEcranState();
}

class ProduitInfo {
  final String nom;
  final String? imageUrl;

  ProduitInfo(this.nom, this.imageUrl);
}

class _ScanEcranState extends State<ScanEcran> {
  String codeBarres = '';

  Future<void> _scannerCodeBarres() async {
    try {
      var result = await BarcodeScanner.scan(
        options: ScanOptions(
          strings: {'cancel': 'Annuler'},
          restrictFormat: [BarcodeFormat.code128, BarcodeFormat.ean13],
          useCamera: -1,
          autoEnableFlash: false,
        ),
      );

      if (result.type == ResultType.Barcode) {
        setState(() => codeBarres = result.rawContent);
        final produitInfo = await _infoDepuisCodeBarres(result.rawContent);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResultatEcranScan(
              nomProduit: produitInfo.nom,
              imageUrl: produitInfo.imageUrl,
            ),
          ),
        );
      } else if (result.type == ResultType.Cancelled) {}
    } catch (e) {
      print('Erreur lors du scan : $e');
    }
  }

  Future<ProduitInfo> _infoDepuisCodeBarres(String code) async {
    final url = Uri.parse(
      'https://world.openfoodfacts.net/api/v2/product/$code.json',
    );

    final headers = {
      'Authorization': 'Basic ${base64Encode(utf8.encode('off:off'))}',
    };

    try {
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final produit = data['product'];
        final nomProduit = produit?['product_name'] ?? 'Produit inconnu';
        final imageUrl = produit?['image_url'];
        return ProduitInfo(nomProduit, imageUrl);
      } else if (response.statusCode == 404) {
        return ProduitInfo('Produit non trouvé', null);
      } else {
        return ProduitInfo('Erreur serveur : ${response.statusCode}', null);
      }
    } catch (e) {
      print('Erreur lors de l\'appel à l\'API : $e');
      return ProduitInfo('Erreur de connexion', null);
    }
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
  final String nomProduit;
  final String? imageUrl;

  const ResultatEcranScan({Key? key, required this.nomProduit, this.imageUrl})
    : super(key: key);

  @override
  State<ResultatEcranScan> createState() => _ResultatEcranScanState();
}

class _ResultatEcranScanState extends State<ResultatEcranScan> {
  final TextEditingController _dateController = TextEditingController();
  File? _imageDate;
  String _texteReconnu = '';
  DateTime? _selectedDate;

  final ImagePicker _picker = ImagePicker();

  Future<void> _scanDatePeremption() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile == null) return;

    final inputImage = InputImage.fromFilePath(pickedFile.path);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    final recognizedText = await textRecognizer.processImage(inputImage);
    await textRecognizer.close();

    String fullText = recognizedText.text;
    String? dateExtraite = _extractDate(fullText);

    setState(() {
      _imageDate = File(pickedFile.path);
      _texteReconnu = fullText;
      _dateController.text = dateExtraite ?? '';
    });
  }

  String? _extractDate(String text) {
    final List<RegExp> regexList = [
      RegExp(r'(\d{2}[\/\-\.]\d{2}[\/\-\.]\d{4})'),
      RegExp(r'(\d{4}[\/\-\.]\d{2}[\/\-\.]\d{2})'),
      RegExp(r'(\d{2}[\/\-\.]\d{2}[\/\-\.]\d{2})'),
    ];

    for (var regex in regexList) {
      final match = regex.firstMatch(text);
      if (match != null) {
        return match.group(0);
      }
    }
    return null;
  }

  void _enregistrer() {
    String dateStr = _dateController.text.trim();
    if (dateStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer ou scanner une date.')),
      );
      return;
    }

    DateTime? date;

    List<DateFormat> tryFormats = [
      DateFormat('dd/MM/yyyy'),
      DateFormat('dd-MM-yyyy'),
      DateFormat('yyyy-MM-dd'),
      DateFormat('yyyy/MM/dd'),
      DateFormat('dd/MM/yy'),
      DateFormat('dd-MM-yy'),
    ];

    for (var format in tryFormats) {
      try {
        date = format.parseStrict(dateStr);
        break;
      } catch (_) {}
    }

    if (date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Format de date non reconnu.')),
      );
      return;
    }

    if (date.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce produit est déjà périmé !')),
      );
      return;
    }

    final produit = {
      'name': widget.nomProduit,
      'date': date,
      'imageUrl': widget.imageUrl,
    };

    Navigator.pop(context, produit);
    Navigator.pop(context, produit);
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
      body: SingleChildScrollView(
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
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                final pickedDate = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (pickedDate != null) {
                  setState(() {
                    _selectedDate = pickedDate;
                    _dateController.text = DateFormat(
                      'dd/MM/yyyy',
                    ).format(pickedDate);
                  });
                }
              },
              child: const Text('Sélectionner la date manuellement'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _scanDatePeremption,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scanner la date via OCR'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _enregistrer,
              child: const Text('Enregistrer le produit'),
            ),
            if (_imageDate != null) ...[
              const SizedBox(height: 20),
              const Text('Aperçu de l\'image :'),
              const SizedBox(height: 8),
              Image.file(_imageDate!, height: 150),
            ],
            if (_texteReconnu.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Texte reconnu par OCR :'),
              const SizedBox(height: 8),
              Text(_texteReconnu),
            ],
          ],
        ),
      ),
    );
  }
}

class Recette {
  final String titre;
  final List<String> ingredients;
  final List<String> instructions;

  Recette({
    required this.titre,
    required this.ingredients,
    required this.instructions,
  });
}

class RecettesEcran extends StatefulWidget {
  const RecettesEcran({Key? key}) : super(key: key);

  @override
  State<RecettesEcran> createState() => _RecettesEcranState();
}

class _RecettesEcranState extends State<RecettesEcran> {
  List<Recette>? recettes;
  bool isLoading = false;
  String? erreur;

  static const String openAIApiKey =
      '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';

  @override
  void initState() {
    super.initState();
    _chargerIngredientsEtGenererRecette();
  }

  Future<void> _chargerIngredientsEtGenererRecette() async {
    setState(() {
      isLoading = true;
      erreur = null;
      recettes = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('produits')
          .get();

      final ingredients = <String>[];
      final currentDate = DateTime.now();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final rawDate = data['date_de_peremption'];
        DateTime? expirationDate;

        if (rawDate is String && rawDate.isNotEmpty) {
          try {
            expirationDate = DateTime.parse(rawDate);
          } catch (_) {
            try {
              expirationDate = DateFormat('dd/MM/yyyy').parseStrict(rawDate);
            } catch (_) {}
          }
        } else if (rawDate is Timestamp) {
          expirationDate = rawDate.toDate();
        }

        if (expirationDate != null &&
            expirationDate.isAfter(currentDate) &&
            data['nom'] != null &&
            data['nom'].toString().isNotEmpty) {
          ingredients.add(data['nom'].toString());
        }
      }

      if (ingredients.isEmpty) {
        setState(() {
          erreur = "Aucun ingrédient non périmé trouvé.";
          isLoading = false;
        });
        return;
      }

      await _genererRecette(ingredients);
    } catch (e) {
      setState(() {
        erreur = "Erreur lors de la récupération des ingrédients : $e";
        isLoading = false;
      });
    }
  }

  Future<List<Recette>> _genererRecette(List<String> ingredients) async {
    final prompt =
        "Génère 3 recettes simples, rapides et en français utilisant uniquement ces ingrédients : ${ingredients.join(', ')}. "
        "Pour chaque recette, donne :\n"
        "- Titre : <titre de la recette>\n"
        "- Ingrédients :\n  - <ingrédient 1>\n  - <ingrédient 2>\n  ...\n"
        "- Instructions :\n  1. <étape 1>\n  2. <étape 2>\n  ...\n\n"
        "Sépare chaque recette par '---'.";

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openAIApiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 1000,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String result = data['choices'][0]['message']['content'];

        final parsedRecettes = _parseRecettes(result);

        setState(() {
          recettes = parsedRecettes;
          isLoading = false;
        });
        return parsedRecettes;
      } else {
        setState(() {
          erreur = "Erreur API : ${response.statusCode}";
          isLoading = false;
        });
        return [];
      }
    } catch (e) {
      setState(() {
        erreur = "Erreur : $e";
        isLoading = false;
      });
      return [];
    }
  }

  List<Recette> _parseRecettes(String texte) {
    final recettesParsed = <Recette>[];

    final recettesBrutes = texte.split('---');

    for (var recetteBrute in recettesBrutes) {
      if (recetteBrute.trim().isEmpty) continue;

      String titre = '';
      List<String> ingredients = [];
      List<String> instructions = [];

      final titreMatch = RegExp(
        r'Titre\s*:\s*(.*?)\n',
        caseSensitive: false,
      ).firstMatch(recetteBrute);
      if (titreMatch != null) {
        titre = titreMatch.group(1)!.trim();
      }

      final ingMatch = RegExp(
        r'Ingrédients\s*:\s*\n([\s\S]*?)(?=\nInstructions\s*:|$)',
        caseSensitive: false,
      ).firstMatch(recetteBrute);
      if (ingMatch != null) {
        final ingText = ingMatch.group(1)!.trim();
        ingredients = ingText
            .split('\n')
            .map((e) => e.replaceAll(RegExp(r'^[-\d\.\)\s]+'), '').trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }

      final instrMatch = RegExp(
        r'Instructions\s*:\s*\n([\s\S]*?)(?=$|\n---)',
        caseSensitive: false,
      ).firstMatch(recetteBrute);
      if (instrMatch != null) {
        final instrText = instrMatch.group(1)!.trim();
        instructions = instrText
            .split('\n')
            .map((e) => e.replaceAll(RegExp(r'^\d+\.\s*'), '').trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }

      if (titre.isNotEmpty &&
          ingredients.isNotEmpty &&
          instructions.isNotEmpty) {
        recettesParsed.add(
          Recette(
            titre: titre,
            ingredients: ingredients,
            instructions: instructions,
          ),
        );
      }
    }

    return recettesParsed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recettes'),
        actions: const [
          ProfilAvatarButton(
            photoUrl: "https://cdn-icons-png.flaticon.com/512/149/149071.png",
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : erreur != null
          ? Center(child: Text(erreur!))
          : recettes == null || recettes!.isEmpty
          ? const Center(child: Text("Aucune recette générée."))
          : ListView.builder(
              itemCount: recettes!.length,
              itemBuilder: (context, index) {
                final recette = recettes![index];
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recette.titre,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Ingrédients :',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          ...recette.ingredients.map(
                            (ingredient) => Text('• $ingredient'),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Instructions :',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          ...recette.instructions.asMap().entries.map(
                            (entry) => Text('${entry.key + 1}. ${entry.value}'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _chargerIngredientsEtGenererRecette,
        child: const Icon(Icons.refresh),
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🛒 Liste de courses')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('liste_courses')
            .orderBy('ajoute_le', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Erreur de chargement'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data!.docs;

          if (items.isEmpty) {
            return const Center(child: Text('Ta liste est vide 🥲'));
          }

          return ListView.builder(
            itemCount: items.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final doc = items[index];
              final nom = doc['nom'] ?? '';
              DateTime? date;
              try {
                date = DateTime.parse(doc['date']);
              } catch (_) {}
              final image = doc['image'];
              final achete = doc['achete'] ?? false;
              final docId = doc.id;

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  leading: image != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            image,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(Icons.shopping_cart),
                  title: Text(
                    nom,
                    style: TextStyle(
                      decoration: achete ? TextDecoration.lineThrough : null,
                      color: achete ? Colors.grey : Colors.black,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (date != null)
                        Text(
                          'À consommer avant le ${DateFormat('dd/MM/yyyy').format(date)}',
                        ),
                      Text(
                        achete ? '✅ Acheté' : '🕒 À acheter',
                        style: TextStyle(
                          color: achete ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          achete
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: achete ? Colors.green : Colors.grey,
                        ),
                        tooltip: achete
                            ? 'Marqué comme acheté'
                            : 'Cocher comme acheté',
                        onPressed: () {
                          FirebaseFirestore.instance
                              .collection('liste_courses')
                              .doc(docId)
                              .update({'achete': !achete});
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          FirebaseFirestore.instance
                              .collection('liste_courses')
                              .doc(docId)
                              .delete();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
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
  List<Map<String, dynamic>> produitsFiltres = [];

  Future<void> _filtrerProduitsParDate(
    DateTime dateDebut,
    DateTime dateFin,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('produits')
        .get();
    final produits = snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;
      return data;
    }).toList();

    final List<Map<String, dynamic>> filtres = [];
    for (var p in produits) {
      final rawDate = p['date_de_peremption'];
      DateTime? date;
      if (rawDate is String && rawDate.isNotEmpty) {
        try {
          date = DateFormat('dd/MM/yyyy').parseStrict(rawDate);
        } catch (_) {
          try {
            date = DateTime.parse(rawDate);
          } catch (_) {}
        }
      } else if (rawDate is Timestamp) {
        date = rawDate.toDate();
      }
      if (date != null && !date.isBefore(dateDebut) && !date.isAfter(dateFin)) {
        filtres.add(p);
      }
    }
    setState(() {
      produitsFiltres = filtres;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendrier'),
        foregroundColor: const Color.fromARGB(255, 0, 0, 0),
        actions: const [
          ProfilAvatarButton(
            photoUrl: "https://cdn-icons-png.flaticon.com/512/149/149071.png",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                final now = DateTime.now();
                final debut = DateTime(now.year, now.month, now.day);
                final fin = DateTime(
                  selectedDay.year,
                  selectedDay.month,
                  selectedDay.day,
                );
                if (fin.isBefore(debut)) {
                  _filtrerProduitsParDate(fin, debut);
                } else {
                  _filtrerProduitsParDate(debut, fin);
                }
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
            if (produitsFiltres.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                "Produits qui périment entre aujourd'hui et le ${DateFormat('dd/MM/yyyy').format(_selectedDay!)} :",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: produitsFiltres.length,
                itemBuilder: (context, index) {
                  final p = produitsFiltres[index];
                  return ListTile(
                    leading: p['image'] != null
                        ? Image.network(
                            p['image'],
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.fastfood),
                    title: Text(p['nom'] ?? ''),
                    subtitle: Text(
                      'Périme le ${p['date_de_peremption'] ?? ''}',
                    ),
                  );
                },
              ),
            ] else if (_selectedDay != null) ...[
              const SizedBox(height: 20),
              const Text("Aucun produit ne périme à cette date."),
            ],
          ],
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
  String nom = "Utilisateur";
  String email = "utilisateur@email.com";
  String photoUrl = "https://cdn-icons-png.flaticon.com/512/149/149071.png";

  final Map<String, bool> frequences = {
    "Le jour même": false,
    "1 jour avant": false,
    "3 jours avant": false,
    "1 semaine avant": false,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(radius: 50, backgroundImage: NetworkImage(photoUrl)),
            const SizedBox(height: 20),
            Text(
              nom,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              email,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("À venir"),
                    content: const Text(
                      "Fonctionnalité de modification du profil bientôt disponible.",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("OK"),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.edit),
              label: const Text("Modifier le profil"),
            ),
            const SizedBox(height: 30),
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      "Paramètres de notifications",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...frequences.keys.map(
                      (freq) => CheckboxListTile(
                        title: Text(freq),
                        value: frequences[freq],
                        onChanged: (val) {
                          setState(() {
                            frequences[freq] = val ?? false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Préférences de notifications enregistrées.",
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.notifications_active),
                      label: const Text("Enregistrer"),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Déconnexion... (à implémenter)"),
                  ),
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text("Se déconnecter"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
