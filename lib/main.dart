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
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

Future<void> _demanderPermissionNotification() async {
  if (Platform.isAndroid) {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }
}

Future<void> creerFamille(String nomFamille) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final familleRef = FirebaseFirestore.instance.collection('familles').doc();
  final familleId = familleRef.id;

  await familleRef.set({
    'nom': nomFamille,
    'membres': [user.uid],
  });

  await FirebaseFirestore.instance.collection('utilisateurs').doc(user.uid).set(
    {'familleId': familleId},
    SetOptions(merge: true),
  );
}

Future<String?> _importerEtUploaderPhoto() async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(source: ImageSource.gallery);
  if (picked == null) return null;

  final file = File(picked.path);
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  final ref = FirebaseStorage.instance
      .ref()
      .child('avatars')
      .child('${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');

  await ref.putFile(file);
  return await ref.getDownloadURL();
}

Future<String?> getFamilleId() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  final userDoc = await FirebaseFirestore.instance
      .collection('utilisateurs')
      .doc(user.uid)
      .get();
  return userDoc.data()?['familleId'];
}

Future<bool> rejoindreFamille(String familleId) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;

  final familleRef = FirebaseFirestore.instance
      .collection('familles')
      .doc(familleId);
  final doc = await familleRef.get();
  if (!doc.exists) return false;

  await familleRef.update({
    'membres': FieldValue.arrayUnion([user.uid]),
  });

  await FirebaseFirestore.instance.collection('utilisateurs').doc(user.uid).set(
    {'familleId': familleId},
    SetOptions(merge: true),
  );

  return true;
}

Future<void> reprogrammerNotificationsPourTousLesProduits(
  Map<String, bool> nouvellesFrequences,
) async {
  final familleId = await getFamilleId();
  if (familleId == null) return;

  final snapshot = await FirebaseFirestore.instance
      .collection('familles')
      .doc(familleId)
      .collection('produits')
      .get();

  await flutterLocalNotificationsPlugin.cancelAll();

  for (var doc in snapshot.docs) {
    final data = doc.data();
    final nom = data['nom'];
    final rawDate = data['date_de_peremption'];
    DateTime? date;
    if (rawDate is String && rawDate.isNotEmpty) {
      try {
        date = DateTime.parse(rawDate);
      } catch (_) {
        try {
          date = DateFormat('dd/MM/yyyy').parseStrict(rawDate);
        } catch (_) {}
      }
    } else if (rawDate is Timestamp) {
      date = rawDate.toDate();
    }
    if (nom != null && date != null) {
      await planifierNotificationProduit(
        produitNom: nom,
        datePeremption: date,
        frequences: nouvellesFrequences,
      );
    }
  }
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class LoginEcran extends StatefulWidget {
  @override
  State<LoginEcran> createState() => _LoginEcranState();
}

class _LoginEcranState extends State<LoginEcran> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLogin = true;
  String error = '';

  Future<void> _submit() async {
    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      }
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    }
  }

  Future<void> _resetPassword() async {
    final emailCtrl = TextEditingController(text: emailController.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Réinitialiser le mot de passe'),
        content: TextField(
          controller: emailCtrl,
          decoration: const InputDecoration(labelText: 'Email'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, emailCtrl.text.trim()),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    if (email != null && email.isNotEmpty) {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Email de réinitialisation envoyé.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erreur : ${e.toString()}')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? 'Connexion' : 'Inscription')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(labelText: 'Mot de passe'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submit,
              child: Text(isLogin ? 'Se connecter' : 'S’inscrire'),
            ),
            TextButton(
              onPressed: () => setState(() => isLogin = !isLogin),
              child: Text(isLogin ? 'Créer un compte' : 'J’ai déjà un compte'),
            ),
            TextButton(
              onPressed: _resetPassword,
              child: const Text('Mot de passe oublié ?'),
            ),
            if (error.isNotEmpty)
              Text(error, style: TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

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
  await _demanderPermissionNotification();
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
  tz.initializeTimeZones();

  await Firebase.initializeApp()
      .then((_) {
        runApp(const MonApp());
        Future.delayed(Duration(seconds: 5), () async {
          await flutterLocalNotificationsPlugin.show(
            9999,
            'Test notification',
            'Ceci est un test de notification',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'expiration_channel',
                'Expiration Notifications',
                channelDescription:
                    'Notifications pour les produits proches de la péremption',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
          );
        });
      })
      .catchError((error) {
        print("Erreur lors de l'initialisation de Firebase : $error");
      });
}

Future<void> planifierNotificationProduit({
  required String produitNom,
  required DateTime datePeremption,
  required Map<String, bool> frequences,
}) async {
  final now = DateTime.now();
  final List<Map<String, dynamic>> configs = [
    {"label": "Le jour même", "daysBefore": 0},
    {"label": "1 jour avant", "daysBefore": 1},
    {"label": "3 jours avant", "daysBefore": 3},
    {"label": "1 semaine avant", "daysBefore": 7},
  ];

  for (final config in configs) {
    if (frequences[config["label"]] == true) {
      final notifDate = datePeremption.subtract(
        Duration(days: config["daysBefore"]),
      );
      if (notifDate.isAfter(now)) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          (produitNom.hashCode + (config["daysBefore"] as int)),
          'Péremption à venir',
          '$produitNom périme ${config["label"].toLowerCase()} (${DateFormat('dd/MM/yyyy').format(datePeremption)})',
          tz.TZDateTime.from(notifDate, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'expiration_channel',
              'Expiration Notifications',
              channelDescription:
                  'Notifications pour les produits proches de la péremption',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          matchDateTimeComponents: DateTimeComponents.dateAndTime,
          androidScheduleMode: AndroidScheduleMode.exact,
        );
      }
    }
  }
}

class MonApp extends StatelessWidget {
  const MonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: Colors.green),
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return CircularProgressIndicator();
          }
          if (snapshot.hasData) {
            return EcranPrincipal();
          }
          return LoginEcran();
        },
      ),
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
    _verifierProduitsPerimesEtNotifer();
    _verifierFamille();
  }

  Future<void> _verifierFamille() async {
    final familleId = await getFamilleId();
    if (familleId == null && mounted) {
      Future.delayed(Duration.zero, () {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text("Bienvenue !"),
            content: const Text(
              "Pour utiliser pleinement l'application, vous devez rejoindre ou créer une famille.",
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.green),
                onPressed: () async {
                  Navigator.pop(context);
                  final code = await showDialog<String>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Rejoindre une famille'),
                      content: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Code famille',
                          hintText: 'Entrez le code famille',
                        ),
                        onChanged: (value) => codeFamille = value,
                      ),
                      actions: [
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.green,
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Annuler'),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.green,
                          ),
                          onPressed: () => Navigator.pop(context, codeFamille),
                          child: const Text('Rejoindre'),
                        ),
                      ],
                    ),
                  );
                  if (code != null && code.isNotEmpty) {
                    final ok = await rejoindreFamille(code);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok ? "Famille rejointe !" : "Famille introuvable",
                        ),
                      ),
                    );
                    setState(() {});
                  }
                },
                child: const Text("Rejoindre une famille"),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.green),
                onPressed: () async {
                  Navigator.pop(context);
                  final nomCtrl = TextEditingController();
                  final nom = await showDialog<String>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Nom de la famille"),
                      content: TextField(
                        controller: nomCtrl,
                        decoration: const InputDecoration(
                          labelText: "Nom de la famille",
                        ),
                      ),
                      actions: [
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.green,
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Annuler"),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.green,
                          ),
                          onPressed: () =>
                              Navigator.pop(context, nomCtrl.text.trim()),
                          child: const Text("Créer"),
                        ),
                      ],
                    ),
                  );
                  if (nom != null && nom.isNotEmpty) {
                    await creerFamille(nom);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Famille créée !")),
                    );
                    setState(() {});
                  }
                },
                child: const Text("Créer une famille"),
              ),
            ],
          ),
        );
      });
    }
  }

  String codeFamille = '';

  Future<void> _verifierProduitsPerimesEtNotifer() async {
    final familleId = await getFamilleId();
    if (familleId == null) return;

    final currentDate = DateTime.now();
    final snapshot = await FirebaseFirestore.instance
        .collection('familles')
        .doc(familleId)
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

  Future<void> _ajouterProduit(Map<String, dynamic> produit) async {
    final familleId = await getFamilleId();
    if (familleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aucune famille associée à ce compte.")),
      );
      return;
    }

    final produitsRef = FirebaseFirestore.instance
        .collection('familles')
        .doc(familleId)
        .collection('produits');

    final query = await produitsRef
        .where('nom', isEqualTo: produit['name'])
        .where(
          'date_de_peremption',
          isEqualTo: produit['date'].toIso8601String(),
        )
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      final quantiteExistante = doc['quantite'] ?? 1;
      final quantiteAjoutee = produit['quantite'] ?? 1;
      await doc.reference.update({
        'quantite': quantiteExistante + quantiteAjoutee,
      });
    } else {
      await produitsRef.add({
        'nom': produit['name'],
        'date_de_peremption': produit['date'].toIso8601String(),
        'ajoute_le': Timestamp.now().toString(),
        'image': produit['imageUrl'],
        'quantite': produit['quantite'] ?? 1,
      });
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(user.uid)
          .get();
      final frequences = Map<String, bool>.from(
        userDoc.data()?['notification_frequences'] ??
            {
              "Le jour même": true,
              "1 jour avant": false,
              "3 jours avant": false,
              "1 semaine avant": false,
            },
      );
      await planifierNotificationProduit(
        produitNom: produit['name'],
        datePeremption: produit['date'],
        frequences: frequences,
      );
    }
  }

  Future<void> _ajouterListeDeCourses(String nomProduit) async {
    final familleId = await getFamilleId();
    if (familleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aucune famille associée à ce compte.")),
      );
      return;
    }
    FirebaseFirestore.instance
        .collection('familles')
        .doc(familleId)
        .collection('courses')
        .add({
          'nom': nomProduit,
          'achete': false,
          'date': DateTime.now().toIso8601String(),
        })
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
      body: FutureBuilder<String?>(
        future: getFamilleId(),
        builder: (context, familleSnapshot) {
          if (!familleSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final familleId = familleSnapshot.data;
          if (familleId == null) {
            return const Center(
              child: Text("Aucune famille associée à ce compte."),
            );
          }
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('familles')
                .doc(familleId)
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
                  final estPerime =
                      date != null && date.isBefore(DateTime.now());
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
                        (p['quantite'] ?? 1) > 1
                            ? "$nom (x${p['quantite']})"
                            : nom,
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
                              final quantite = (p['quantite'] ?? 1) as int;
                              if (quantite > 1) {
                                int nbASupprimer = 1;
                                final maxValue = quantite;
                                final result = await showDialog<int>(
                                  context: context,
                                  builder: (context) {
                                    return StatefulBuilder(
                                      builder: (context, setState) => AlertDialog(
                                        title: const Text(
                                          'Supprimer des unités',
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Vous avez $quantite produits.',
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                const Text(
                                                  'Quantité à supprimer : ',
                                                ),
                                                Expanded(
                                                  child: Slider(
                                                    value: nbASupprimer
                                                        .toDouble(),
                                                    min: 1,
                                                    max: maxValue.toDouble(),
                                                    divisions: maxValue - 1,
                                                    label: '$nbASupprimer',
                                                    onChanged:
                                                        (double newValue) {
                                                          setState(() {
                                                            nbASupprimer =
                                                                newValue
                                                                    .round();
                                                          });
                                                        },
                                                  ),
                                                ),
                                                Text('$nbASupprimer'),
                                              ],
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, null),
                                            child: const Text('Annuler'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(
                                              context,
                                              nbASupprimer,
                                            ),
                                            child: const Text('Supprimer'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                                if (result != null) {
                                  if (result >= quantite) {
                                    final familleId = await getFamilleId();
                                    if (familleId != null) {
                                      await FirebaseFirestore.instance
                                          .collection('familles')
                                          .doc(familleId)
                                          .collection('produits')
                                          .doc(p.id)
                                          .delete();
                                    }
                                  } else {
                                    final familleId = await getFamilleId();
                                    if (familleId != null) {
                                      await FirebaseFirestore.instance
                                          .collection('familles')
                                          .doc(familleId)
                                          .collection('produits')
                                          .doc(p.id)
                                          .update({
                                            'quantite': quantite - result,
                                          });
                                    }
                                  }
                                }
                              } else {
                                final familleId = await getFamilleId();
                                if (familleId != null) {
                                  await FirebaseFirestore.instance
                                      .collection('familles')
                                      .doc(familleId)
                                      .collection('produits')
                                      .doc(p.id)
                                      .delete();
                                }
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
                    ),
                  );
                },
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
  final TextEditingController codeBarresController = TextEditingController();

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
              codeBarres: codeBarres,
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
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: codeBarresController,
              decoration: const InputDecoration(
                labelText: 'Code-barres',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (val) => codeBarres = val,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                if (codeBarresController.text.trim().isNotEmpty) {
                  final produitInfo = await _infoDepuisCodeBarres(
                    codeBarresController.text.trim(),
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ResultatEcranScan(
                        nomProduit: produitInfo.nom,
                        imageUrl: produitInfo.imageUrl,
                        codeBarres: codeBarresController.text
                            .trim(), // <-- Ajoute ceci
                      ),
                    ),
                  );
                } else {
                  await _scannerCodeBarres();
                }
              },
              child: const Text('Scanner ou valider le code-barres'),
            ),
          ],
        ),
      ),
    );
  }
}

class ResultatEcranScan extends StatefulWidget {
  final String nomProduit;
  final String? imageUrl;
  final String? codeBarres;

  const ResultatEcranScan({
    Key? key,
    required this.nomProduit,
    this.imageUrl,
    this.codeBarres,
  }) : super(key: key);

  @override
  State<ResultatEcranScan> createState() => _ResultatEcranScanState();
}

class _ResultatEcranScanState extends State<ResultatEcranScan> {
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _codeBarresController = TextEditingController();
  File? _imageDate;
  String _texteReconnu = '';
  DateTime? _selectedDate;

  final ImagePicker _picker = ImagePicker();

  int _quantite = 1;

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
    String cleaned = text.replaceAll(RegExp(r'[^0-9\/\-\.\s]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), '');

    final List<RegExp> regexList = [
      RegExp(
        r'(\d{2}[\/\-\.]\d{2}[\/\-\.]\d{4})',
      ), // 12/06/2025 ou 12-06-2025 ou 12.06.2025
      RegExp(
        r'(\d{4}[\/\-\.]\d{2}[\/\-\.]\d{2})',
      ), // 2025/06/12 ou 2025-06-12 ou 2025.06.12
      RegExp(
        r'(\d{2}[\/\-\.]\d{2}[\/\-\.]\d{2})',
      ), // 12/06/25 ou 12-06-25 ou 12.06.25
    ];

    for (var regex in regexList) {
      final match = regex.firstMatch(cleaned);
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
      'quantite': _quantite,
    };

    Navigator.pop(context, produit);
    Navigator.pop(context, produit);
  }

  @override
  void initState() {
    super.initState();
    if (widget.codeBarres != null && widget.codeBarres!.isNotEmpty) {
      _codeBarresController.text = widget.codeBarres!;
    }
  }

  void dispose() {
    _dateController.dispose();
    _codeBarresController.dispose();
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Quantité : ', style: TextStyle(fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: _quantite > 1
                      ? () => setState(() => _quantite--)
                      : null,
                ),
                Text('$_quantite', style: const TextStyle(fontSize: 18)),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(() => _quantite++),
                ),
              ],
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
            // if (_texteReconnu.isNotEmpty) ...[
            //   const SizedBox(height: 20),
            //   const Text('Texte reconnu par OCR :'),
            //   const SizedBox(height: 8),
            //   Text(_texteReconnu),
            // ],
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
      final familleId = await getFamilleId();
      if (familleId == null) {
        setState(() {
          erreur = "Aucune famille associée à ce compte.";
          isLoading = false;
        });
        return;
      }
      final snapshot = await FirebaseFirestore.instance
          .collection('familles')
          .doc(familleId)
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
  Future<void> _supprimerCourse(String familleId, String docId) async {
    await FirebaseFirestore.instance
        .collection('familles')
        .doc(familleId)
        .collection('courses')
        .doc(docId)
        .delete();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Produit supprimé de la liste.")),
    );
  }

  Future<void> _toggleAchete(
    String familleId,
    String docId,
    bool actuel,
  ) async {
    await FirebaseFirestore.instance
        .collection('familles')
        .doc(familleId)
        .collection('courses')
        .doc(docId)
        .update({'achete': !actuel});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🛒 Liste de courses'),
        actions: const [
          ProfilAvatarButton(
            photoUrl: "https://cdn-icons-png.flaticon.com/512/149/149071.png",
          ),
        ],
      ),
      body: FutureBuilder<String?>(
        future: getFamilleId(),
        builder: (context, familleSnapshot) {
          if (familleSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final familleId = familleSnapshot.data;
          if (familleId == null) {
            return const Center(
              child: Text("Aucune famille associée à ce compte."),
            );
          }
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('familles')
                .doc(familleId)
                .collection('courses')
                .orderBy('date', descending: false)
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
                return const Center(
                  child: Text(
                    'Ta liste est vide 🥲',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                );
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
                  final achete = doc['achete'] ?? false;
                  final docId = doc.id;

                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    color: achete ? Colors.green[50] : Colors.white,
                    child: ListTile(
                      leading: Icon(
                        achete
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: achete ? Colors.green : Colors.grey,
                        size: 32,
                      ),
                      title: Text(
                        nom,
                        style: TextStyle(
                          decoration: achete
                              ? TextDecoration.lineThrough
                              : null,
                          color: achete ? Colors.grey : Colors.black,
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                      subtitle: date != null
                          ? Text(
                              'Ajouté le ${DateFormat('dd/MM/yyyy').format(date)}',
                              style: TextStyle(
                                color: achete ? Colors.grey : Colors.black54,
                              ),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
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
                            onPressed: () =>
                                _toggleAchete(familleId, docId, achete),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            tooltip: "Supprimer",
                            onPressed: () => _supprimerCourse(familleId, docId),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
    final familleId = await getFamilleId();
    if (familleId == null) return;
    final snapshot = await FirebaseFirestore.instance
        .collection('familles')
        .doc(familleId)
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
              firstDay: DateTime.now(),
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
                      p['date_de_peremption'] != null
                          ? (() {
                              DateTime? date;
                              try {
                                date = DateFormat(
                                  'dd/MM/yyyy',
                                ).parseStrict(p['date_de_peremption']);
                              } catch (_) {
                                try {
                                  date = DateTime.parse(
                                    p['date_de_peremption'],
                                  );
                                } catch (_) {}
                              }
                              return date != null
                                  ? 'Périme le ${DateFormat('dd/MM/yyyy').format(date)}'
                                  : 'Date invalide';
                            })()
                          : 'Date inconnue',
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
  String? familleId;

  final Map<String, bool> frequences = {
    "Le jour même": false,
    "1 jour avant": false,
    "3 jours avant": false,
    "1 semaine avant": false,
  };

  late final TextEditingController nomController;

  @override
  void initState() {
    super.initState();
    nomController = TextEditingController(text: nom);
    _chargerInfosUtilisateur();
  }

  void dispose() {
    nomController.dispose();
    super.dispose();
  }

  Future<void> enregistrerInfosUtilisateur({
    required String nom,
    required String email,
    required String photoUrl,
    String? familleId,
    Map<String, bool>? notificationFrequences,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('utilisateurs')
        .doc(user.uid)
        .set({
          'nom': nom,
          'email': email,
          'photoUrl': photoUrl,
          if (familleId != null) 'familleId': familleId,
          if (notificationFrequences != null)
            'notification_frequences': notificationFrequences,
        }, SetOptions(merge: true));
  }

  Future<void> _chargerInfosUtilisateur() async {
    final user = FirebaseAuth.instance.currentUser;
    nomController.text = nom;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          nom = data['nom'] ?? "Utilisateur";
          email = data['email'] ?? user.email ?? "utilisateur@email.com";
          photoUrl =
              data['photoUrl'] ??
              user.photoURL ??
              "https://cdn-icons-png.flaticon.com/512/149/149071.png";
          familleId = data['familleId'];
          if (data['notification_frequences'] != null) {
            final notif = Map<String, dynamic>.from(
              data['notification_frequences'],
            );
            notif.forEach((key, value) {
              if (frequences.containsKey(key)) {
                frequences[key] = value == true;
              }
            });
          }
        });
      }
    }
  }

  Future<String?> _demanderFamilleId(BuildContext context) async {
    String code = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rejoindre une famille'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Code famille',
            hintText: 'Entrez le code famille',
          ),
          onChanged: (value) => code = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, code),
            child: const Text('Rejoindre'),
          ),
        ],
      ),
    );
  }

  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundImage: NetworkImage(photoUrl),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.camera_alt,
                              color: Colors.blue,
                            ),
                            onPressed: () async {
                              final url = await _importerEtUploaderPhoto();
                              if (url != null) {
                                setState(() {
                                  photoUrl = url;
                                });
                                await enregistrerInfosUtilisateur(
                                  nom: nom,
                                  email: email,
                                  photoUrl: url,
                                  familleId: familleId,
                                  notificationFrequences: frequences,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Photo de profil mise à jour !",
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            nom,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            tooltip: "Modifier le nom",
                            onPressed: () async {
                              final controller = TextEditingController(
                                text: nom,
                              );
                              final nouveauNom = await showDialog<String>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text("Modifier le nom"),
                                  content: TextField(
                                    controller: controller,
                                    decoration: const InputDecoration(
                                      labelText: "Nouveau nom",
                                    ),
                                    autofocus: true,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text("Annuler"),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(
                                        context,
                                        controller.text.trim(),
                                      ),
                                      child: const Text("Enregistrer"),
                                    ),
                                  ],
                                ),
                              );
                              if (nouveauNom != null &&
                                  nouveauNom.isNotEmpty &&
                                  nouveauNom != nom) {
                                await enregistrerInfosUtilisateur(
                                  nom: nouveauNom,
                                  email: email,
                                  photoUrl: photoUrl,
                                  familleId: familleId,
                                  notificationFrequences: frequences,
                                );
                                setState(() {
                                  nom = nouveauNom;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Nom mis à jour !"),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text("Enregistrer le profil"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () async {
                          await enregistrerInfosUtilisateur(
                            nom: nomController.text.trim(),
                            email: email,
                            photoUrl: photoUrl,
                            familleId: familleId,
                            notificationFrequences: frequences,
                          );

                          await reprogrammerNotificationsPourTousLesProduits(
                            frequences,
                          );

                          setState(() {
                            nom = nomController.text.trim();
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Profil mis à jour !"),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Text(
              nom,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              email,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            if (familleId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  "Code famille : $familleId",
                  style: const TextStyle(fontSize: 16, color: Colors.blueGrey),
                ),
              ),
            const SizedBox(height: 30),
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
                      onPressed: () async {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                          await FirebaseFirestore.instance
                              .collection('utilisateurs')
                              .doc(user.uid)
                              .set({
                                'notification_frequences': frequences,
                              }, SetOptions(merge: true));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Préférences de notifications enregistrées.",
                              ),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Utilisateur non connecté."),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.notifications_active),
                      label: const Text("Enregistrer"),
                    ),
                    ElevatedButton(
                      onPressed: familleId != null
                          ? null
                          : () async {
                              final nomCtrl = TextEditingController();
                              final nom = await showDialog<String>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text("Nom de la famille"),
                                  content: TextField(
                                    controller: nomCtrl,
                                    decoration: const InputDecoration(
                                      labelText: "Nom de la famille",
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text("Annuler"),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(
                                        context,
                                        nomCtrl.text.trim(),
                                      ),
                                      child: const Text("Créer"),
                                    ),
                                  ],
                                ),
                              );
                              if (nom != null && nom.isNotEmpty) {
                                await creerFamille(nom);
                                await _chargerInfosUtilisateur();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Famille créée !"),
                                  ),
                                );
                              }
                            },
                      child: Text(
                        familleId != null
                            ? "Famille déjà créée"
                            : "Créer une famille",
                      ),
                    ),

                    ElevatedButton(
                      onPressed: () async {
                        final familleId = await _demanderFamilleId(context);
                        if (familleId != null && familleId.isNotEmpty) {
                          final ok = await rejoindreFamille(familleId);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? "Famille rejointe !"
                                    : "Famille introuvable",
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text("Rejoindre une famille"),
                    ),
                    ElevatedButton.icon(
                      onPressed: familleId == null
                          ? null
                          : () async {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user == null) return;
                              await FirebaseFirestore.instance
                                  .collection('familles')
                                  .doc(familleId)
                                  .update({
                                    'membres': FieldValue.arrayRemove([
                                      user.uid,
                                    ]),
                                  });
                              await FirebaseFirestore.instance
                                  .collection('utilisateurs')
                                  .doc(user.uid)
                                  .set({
                                    'familleId': FieldValue.delete(),
                                  }, SetOptions(merge: true));
                              setState(() {
                                this.familleId = null;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Vous avez quitté la famille."),
                                ),
                              );
                            },
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text("Quitter la famille"),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
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
