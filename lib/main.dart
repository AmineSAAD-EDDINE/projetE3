import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
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
    final datePeremption = data['date_de_peremption'];
    DateTime? date;
    if (datePeremption is String && datePeremption.isNotEmpty) {
      try {
        date = DateTime.parse(datePeremption);
      } catch (_) {
        try {
          date = DateFormat('dd/MM/yyyy').parseStrict(datePeremption);
        } catch (_) {}
      }
    } else if (datePeremption is Timestamp) {
      date = datePeremption.toDate();
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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        scaffoldBackgroundColor: Colors.grey[100],
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
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    AccueilEcran(),
    RecettesEcran(),
    ListeCoursesEcran(),
    CalendrierEcran(),
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
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Accueil'),
          BottomNavigationBarItem(
            icon: Icon(Icons.restaurant),
            label: 'Recettes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Liste de courses',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Calendrier',
          ),
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

      if (expirationDate != null && expirationDate.isBefore(currentDate)) {
        await flutterLocalNotificationsPlugin.show(
          data['nom'].hashCode,
          'Produit périmé',
          '${data['nom']} est déjà périmé !',
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
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            tooltip: 'Paramètres',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilEcran()),
              );
            },
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.kitchen, color: Colors.green[400], size: 48),
                    const SizedBox(width: 12),
                    Text(
                      "Bienvenue dans MonFrigo+",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              );
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
                                      DateTime? datePeremption;
                                      final rawDate = p['date_de_peremption'];
                                      if (rawDate is String &&
                                          rawDate.isNotEmpty) {
                                        try {
                                          datePeremption = DateTime.parse(
                                            rawDate,
                                          );
                                        } catch (_) {
                                          try {
                                            datePeremption = DateFormat(
                                              'dd/MM/yyyy',
                                            ).parseStrict(rawDate);
                                          } catch (_) {}
                                        }
                                      } else if (rawDate is Timestamp) {
                                        datePeremption = rawDate.toDate();
                                      }
                                      final maintenant = DateTime.now();
                                      final statsRef = FirebaseFirestore
                                          .instance
                                          .collection('familles')
                                          .doc(familleId)
                                          .collection('stats')
                                          .doc('global');
                                      final quantiteSupprimee = (result ?? 1);

                                      if (datePeremption != null) {
                                        if (maintenant.isBefore(
                                          datePeremption,
                                        )) {
                                          await statsRef.set({
                                            'total_non_gaspilles':
                                                FieldValue.increment(
                                                  quantiteSupprimee,
                                                ),
                                          }, SetOptions(merge: true));
                                        } else {
                                          await statsRef.set({
                                            'total_gaspilles':
                                                FieldValue.increment(
                                                  quantiteSupprimee,
                                                ),
                                          }, SetOptions(merge: true));
                                        }
                                      }
                                      await statsRef.set({
                                        'total_ajoutes': FieldValue.increment(
                                          quantiteSupprimee,
                                        ),
                                      }, SetOptions(merge: true));
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
                                      DateTime? datePeremption;
                                      final rawDate = p['date_de_peremption'];
                                      if (rawDate is String &&
                                          rawDate.isNotEmpty) {
                                        try {
                                          datePeremption = DateTime.parse(
                                            rawDate,
                                          );
                                        } catch (_) {
                                          try {
                                            datePeremption = DateFormat(
                                              'dd/MM/yyyy',
                                            ).parseStrict(rawDate);
                                          } catch (_) {}
                                        }
                                      } else if (rawDate is Timestamp) {
                                        datePeremption = rawDate.toDate();
                                      }
                                      final maintenant = DateTime.now();
                                      final statsRef = FirebaseFirestore
                                          .instance
                                          .collection('familles')
                                          .doc(familleId)
                                          .collection('stats')
                                          .doc('global');
                                      final quantiteSupprimee = (quantite ?? 1);

                                      if (datePeremption != null) {
                                        if (maintenant.isBefore(
                                          datePeremption,
                                        )) {
                                          await statsRef.set({
                                            'total_non_gaspilles':
                                                FieldValue.increment(
                                                  quantiteSupprimee,
                                                ),
                                          }, SetOptions(merge: true));
                                        } else {
                                          await statsRef.set({
                                            'total_gaspilles':
                                                FieldValue.increment(
                                                  quantiteSupprimee,
                                                ),
                                          }, SetOptions(merge: true));
                                        }
                                      }
                                      await statsRef.set({
                                        'total_ajoutes': FieldValue.increment(
                                          quantiteSupprimee,
                                        ),
                                      }, SetOptions(merge: true));
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
                                  DateTime? datePeremption;
                                  final rawDate = p['date_de_peremption'];
                                  if (rawDate is String && rawDate.isNotEmpty) {
                                    try {
                                      datePeremption = DateTime.parse(rawDate);
                                    } catch (_) {
                                      try {
                                        datePeremption = DateFormat(
                                          'dd/MM/yyyy',
                                        ).parseStrict(rawDate);
                                      } catch (_) {}
                                    }
                                  } else if (rawDate is Timestamp) {
                                    datePeremption = rawDate.toDate();
                                  }
                                  final maintenant = DateTime.now();

                                  final statsRef = FirebaseFirestore.instance
                                      .collection('familles')
                                      .doc(familleId)
                                      .collection('stats')
                                      .doc('global');

                                  final quantiteSupprimee = (quantite ?? 1);

                                  if (datePeremption != null) {
                                    if (maintenant.isBefore(datePeremption)) {
                                      await statsRef.set({
                                        'total_non_gaspilles':
                                            FieldValue.increment(
                                              quantiteSupprimee,
                                            ),
                                      }, SetOptions(merge: true));
                                    } else {
                                      await statsRef.set({
                                        'total_gaspilles': FieldValue.increment(
                                          quantiteSupprimee,
                                        ),
                                      }, SetOptions(merge: true));
                                    }
                                  }
                                  await statsRef.set({
                                    'total_ajoutes': FieldValue.increment(
                                      quantiteSupprimee,
                                    ),
                                  }, SetOptions(merge: true));
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
                        codeBarres: codeBarresController.text.trim(), //
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
      RegExp(r'(\d{2}[\/\-\.]\d{2}[\/\-\.]\d{4})'),
      RegExp(r'(\d{2}[\/\-\.]\d{2}[\/\-\.]\d{2})'),
      RegExp(r'(\d{4}[\/\-\.]\d{2}[\/\-\.]\d{2})'),
      RegExp(r'(\d{2}[\/\-\.]\d{2})'),
      RegExp(r'(\d{8})'),
      RegExp(r'(\d{6})'),
      RegExp(r'(\d{4})'),
    ];

    for (var regex in regexList) {
      final match = regex.firstMatch(cleaned);
      if (match != null) {
        String? raw = match.group(0);
        if (raw != null) {
          List<String> formats = [
            'dd/MM/yyyy',
            'dd-MM-yyyy',
            'dd.MM.yyyy',
            'dd/MM/yy',
            'dd-MM-yy',
            'dd.MM.yy',
            'yyyy/MM/dd',
            'yyyy-MM-dd',
            'yyyy.MM.dd',
            'dd/MM',
            'dd-MM',
            'dd.MM',
            'ddMMyyyy',
            'ddMMyy',
          ];
          for (var f in formats) {
            try {
              DateTime d = DateFormat(f).parseStrict(raw);
              return DateFormat('dd/MM/yyyy').format(d);
            } catch (_) {}
          }
        }
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

    List<String> formats = [
      'dd-MM-yy',
      'dd/MM/yy',
      'dd-MM-yyyy',
      'dd/MM/yyyy',
      'dd-MM',
      'dd/MM',
      'ddMMyy',
      'ddMMyyyy',
      'ddMM',
    ];
    List<DateFormat> tryFormats = formats.map((f) => DateFormat(f)).toList();

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
                  firstDate: DateTime.now(),
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

enum TriType {
  nomCroissant,
  nomDecroissant,
  ingredientsCroissant,
  ingredientsDecroissant,
  nouveaute,
}

enum FiltreIngredients {
  tous,
  aucunManquant,
  unManquant,
  deuxManquants,
  troisManquants,
  favoris,
}

class RecettesEcran extends StatefulWidget {
  const RecettesEcran({super.key});

  @override
  State<RecettesEcran> createState() => _RecettesEcranState();
}

class _RecettesEcranState extends State<RecettesEcran> {
  List<Map<String, dynamic>> _allRecettes = [];
  List<Map<String, dynamic>> _displayedRecettes = [];
  List<String> _ingredientsPossedes = [];
  List<String> _favorisTitres = [];

  TriType _triType = TriType.nouveaute;
  FiltreIngredients _filtre = FiltreIngredients.tous;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRecettesEtDonnees();
  }

  Future<void> _loadRecettesEtDonnees() async {
    final jsonString = await rootBundle.loadString('assets/recettes.json');
    final List<dynamic> jsonData = json.decode(jsonString);
    _allRecettes = List<Map<String, dynamic>>.from(jsonData).where((recette) {
      final imageUrl = (recette['image_url'] ?? '').toString();
      final ingredients = recette['ingredients'] as List? ?? [];
      return imageUrl !=
              'https://static.afcdn.com/relmrtn/Front/Vendor/img/default-recipe-picture_80x80.jpg' &&
          imageUrl.isNotEmpty &&
          ingredients.length > 3;
    }).toList();

    final familleId = await getFamilleId();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (familleId != null && uid != null) {
      final snapshot = await FirebaseFirestore.instance
          .collection('familles')
          .doc(familleId)
          .collection('produits')
          .get();

      _ingredientsPossedes = snapshot.docs
          .map((doc) => doc['nom'].toString().toLowerCase())
          .toList();

      final favorisSnap = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(uid)
          .collection('favoris')
          .get();

      _favorisTitres = favorisSnap.docs.map((doc) => doc.id).toList();
    }

    _filtrerEtTrier();
  }

  void _onTriChanged(TriType selected) {
    setState(() {
      _triType = selected;
      _filtrerEtTrier();
    });
  }

  void _onFiltreChanged(FiltreIngredients selected) {
    setState(() {
      _filtre = selected;
      _filtrerEtTrier();
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _filtrerEtTrier();
    });
  }

  void _filtrerEtTrier() {
    List<Map<String, dynamic>> temp = List.from(_allRecettes);

    if (_searchQuery.isNotEmpty) {
      temp = temp
          .where(
            (r) =>
                r['titre']?.toString().toLowerCase().contains(_searchQuery) ??
                false,
          )
          .toList();
    }

    temp = temp.where((recette) {
      final List ingredients = recette['ingredients'] ?? [];
      final titre = recette['titre'].toString();

      final missing = ingredients
          .where(
            (i) => !_ingredientsPossedes.contains(i.toString().toLowerCase()),
          )
          .length;

      switch (_filtre) {
        case FiltreIngredients.aucunManquant:
          return missing == 0;
        case FiltreIngredients.unManquant:
          return missing <= 1;
        case FiltreIngredients.deuxManquants:
          return missing <= 2;
        case FiltreIngredients.troisManquants:
          return missing <= 3;
        case FiltreIngredients.favoris:
          return _favorisTitres.contains(titre);
        case FiltreIngredients.tous:
        default:
          return true;
      }
    }).toList();

    temp.sort((a, b) {
      switch (_triType) {
        case TriType.nomCroissant:
          return a['titre'].toString().toLowerCase().compareTo(
            b['titre'].toString().toLowerCase(),
          );
        case TriType.nomDecroissant:
          return b['titre'].toString().toLowerCase().compareTo(
            a['titre'].toString().toLowerCase(),
          );
        case TriType.ingredientsCroissant:
          return (a['ingredients'] as List).length.compareTo(
            (b['ingredients'] as List).length,
          );
        case TriType.ingredientsDecroissant:
          return (b['ingredients'] as List).length.compareTo(
            (a['ingredients'] as List).length,
          );
        case TriType.nouveaute:
          return _allRecettes.indexOf(b).compareTo(_allRecettes.indexOf(a));
      }
    });

    setState(() {
      _displayedRecettes = temp;
    });
  }

  Future<void> _toggleFavori(String titre) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final favRef = FirebaseFirestore.instance
        .collection('utilisateurs')
        .doc(uid)
        .collection('favoris')
        .doc(titre);

    if (_favorisTitres.contains(titre)) {
      await favRef.delete();
      _favorisTitres.remove(titre);
    } else {
      await favRef.set({'ajoute_le': FieldValue.serverTimestamp()});
      _favorisTitres.add(titre);
    }

    _filtrerEtTrier();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recettes'),
        foregroundColor: Colors.black,
        actions: [_buildTriMenu(), _buildFiltreMenu()],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _displayedRecettes.isEmpty
                ? const Center(child: Text('Aucune recette disponible'))
                : ListView.builder(
                    itemCount: _displayedRecettes.length,
                    itemBuilder: (context, index) {
                      final recette = _displayedRecettes[index];
                      final titre = recette['titre'].toString();
                      final isFavori = _favorisTitres.contains(titre);
                      final ingredients = (recette['ingredients'] as List)
                          .cast<String>();

                      final possedesCount = ingredients
                          .where(
                            (i) =>
                                _ingredientsPossedes.contains(i.toLowerCase()),
                          )
                          .length;

                      return ListTile(
                        leading: recette['image_url'] != null
                            ? Image.network(
                                recette['image_url'],
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.image),
                        title: Text(titre),
                        subtitle: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${ingredients.length} ingrédients'),
                            Text(
                              '$possedesCount/${ingredients.length}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            isFavori ? Icons.favorite : Icons.favorite_border,
                            color: isFavori ? Colors.red : null,
                          ),
                          onPressed: () => _toggleFavori(titre),
                        ),
                        onTap: () => _showRecetteDialog(context, recette),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTriMenu() {
    return PopupMenuButton<TriType>(
      onSelected: _onTriChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(value: TriType.nomCroissant, child: Text('Nom A-Z')),
        PopupMenuItem(value: TriType.nomDecroissant, child: Text('Nom Z-A')),
        PopupMenuItem(
          value: TriType.ingredientsCroissant,
          child: Text('Ingrédients ↑'),
        ),
        PopupMenuItem(
          value: TriType.ingredientsDecroissant,
          child: Text('Ingrédients ↓'),
        ),
        PopupMenuItem(value: TriType.nouveaute, child: Text('Nouveauté')),
      ],
      icon: const Icon(Icons.sort, color: Colors.black),
    );
  }

  Widget _buildFiltreMenu() {
    return PopupMenuButton<FiltreIngredients>(
      onSelected: _onFiltreChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(value: FiltreIngredients.tous, child: Text('Toutes')),
        PopupMenuItem(
          value: FiltreIngredients.favoris,
          child: Text('Favoris ❤️'),
        ),
        PopupMenuItem(
          value: FiltreIngredients.aucunManquant,
          child: Text('0 manquant'),
        ),
        PopupMenuItem(
          value: FiltreIngredients.unManquant,
          child: Text('≤ 1 manquant'),
        ),
        PopupMenuItem(
          value: FiltreIngredients.deuxManquants,
          child: Text('≤ 2 manquants'),
        ),
        PopupMenuItem(
          value: FiltreIngredients.troisManquants,
          child: Text('≤ 3 manquants'),
        ),
      ],
      icon: const Icon(Icons.filter_alt, color: Colors.black),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextField(
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Rechercher une recette...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  void _showRecetteDialog(BuildContext context, Map<String, dynamic> recette) {
    final titre = recette['titre'] ?? '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recette['image_url'] != null)
              Image.network(recette['image_url']),
            const SizedBox(height: 10),
            const Text(
              'Ingrédients',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ...List<Widget>.from(
              (recette['ingredients'] as List).map((i) => Text('• $i')),
            ),
            const SizedBox(height: 10),
            const Text(
              'Préparation',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ...List<Widget>.from(
              (recette['etapes'] as List).map((e) => Text('• $e')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
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

  List<Map<String, dynamic>> _suggestions = [];
  String _rechercheTexte = '';
  bool _chargementSuggestions = false;
  final TextEditingController _rechercheController = TextEditingController();

  Future<void> _fetchSuggestions(String query) async {
    if (query.length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _chargementSuggestions = true);
    final url = Uri.parse(
      'https://world.openfoodfacts.org/cgi/search.pl?search_terms=$query&search_simple=1&action=process&json=1&page_size=10',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final products = (data['products'] as List)
          .map(
            (p) => {
              'name': p['product_name'] ?? '',
              'image': p['image_thumb_url'],
            },
          )
          .where((p) => p['name'] != '')
          .toList();
      setState(() => _suggestions = products);
    } else {
      setState(() => _suggestions = []);
    }
    setState(() => _chargementSuggestions = false);
  }

  Future<void> _ajouterProduitCourse(Map<String, dynamic> produit) async {
    final familleId = await getFamilleId();
    if (familleId == null) return;
    await FirebaseFirestore.instance
        .collection('familles')
        .doc(familleId)
        .collection('courses')
        .add({
          'nom': produit['name'],
          'image': produit['image'],
          'achete': false,
          'date': DateTime.now().toIso8601String(),
        });
    setState(() {
      _suggestions = [];
    });
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

  void _ouvrirAjoutProduit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 24,
        ),
        child: _AjoutProduitListeCourse(
          onProduitAjoute: (produit) {
            _ajouterProduitCourse(produit);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liste de courses'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            tooltip: 'Paramètres',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilEcran()),
              );
            },
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

          return Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
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
                                      color: achete
                                          ? Colors.grey
                                          : Colors.black54,
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
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  tooltip: "Supprimer",
                                  onPressed: () =>
                                      _supprimerCourse(familleId, docId),
                                ),
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
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _ouvrirAjoutProduit(context),
        child: const Icon(Icons.add),
        tooltip: "Ajouter un produit",
      ),
    );
  }
}

class _AjoutProduitListeCourse extends StatefulWidget {
  final Function(Map<String, dynamic>) onProduitAjoute;
  const _AjoutProduitListeCourse({required this.onProduitAjoute});

  @override
  State<_AjoutProduitListeCourse> createState() =>
      _AjoutProduitListeCourseState();
}

class _AjoutProduitListeCourseState extends State<_AjoutProduitListeCourse> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;
  String _searchText = '';

  Future<void> _fetchSuggestions(String query) async {
    if (query.length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _isLoading = true);
    final url = Uri.parse(
      'https://world.openfoodfacts.org/cgi/search.pl?search_terms=$query&search_simple=1&action=process&json=1&page_size=10',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final products = (data['products'] as List)
          .map(
            (p) => {
              'name': p['product_name'] ?? '',
              'image': p['image_thumb_url'],
            },
          )
          .where((p) => p['name'] != '')
          .toList();
      setState(() => _suggestions = products);
    } else {
      setState(() => _suggestions = []);
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Rechercher un produit...',
              border: OutlineInputBorder(),
            ),
            onChanged: (val) {
              setState(() {
                _searchText = val;
              });
              _fetchSuggestions(val);
            },
            onSubmitted: (val) {
              if (val.trim().isNotEmpty) {
                widget.onProduitAjoute({'name': val.trim(), 'image': null});
              }
            },
          ),
          if (_isLoading) const LinearProgressIndicator(),
          if (_suggestions.isNotEmpty)
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final prod = _suggestions[index];
                  return ListTile(
                    leading: prod['image'] != null
                        ? Image.network(prod['image'], width: 40, height: 40)
                        : const Icon(Icons.fastfood),
                    title: Text(prod['name']),
                    onTap: () => widget.onProduitAjoute(prod),
                  );
                },
              ),
            ),
          if (_suggestions.isEmpty && _searchText.length >= 3 && !_isLoading)
            ListTile(
              leading: const Icon(Icons.add),
              title: Text('Ajouter "$_searchText" à la liste'),
              onTap: () =>
                  widget.onProduitAjoute({'name': _searchText, 'image': null}),
            ),
          const SizedBox(height: 16),
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
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            tooltip: 'Paramètres',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilEcran()),
              );
            },
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
              Expanded(
                child: ListView.builder(
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
                  ],
                ),
              ),
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
                              onPressed: () =>
                                  Navigator.pop(context, nomCtrl.text.trim()),
                              child: const Text("Créer"),
                            ),
                          ],
                        ),
                      );
                      if (nom != null && nom.isNotEmpty) {
                        await creerFamille(nom);
                        await _chargerInfosUtilisateur();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Famille créée !")),
                        );
                      }
                    },
              child: Text(
                familleId != null ? "Famille déjà créée" : "Créer une famille",
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
                        ok ? "Famille rejointe !" : "Famille introuvable",
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
                            'membres': FieldValue.arrayRemove([user.uid]),
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
            ElevatedButton.icon(
              icon: const Icon(Icons.bar_chart),
              label: const Text('Statistiques'),
              onPressed: () async {
                final familleId = await getFamilleId();
                if (familleId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StatistiquesEcran(familleId: familleId),
                    ),
                  );
                }
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.info_outline),
              label: const Text("À propos de nous"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AProposEcran()),
                );
              },
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

class AProposEcran extends StatelessWidget {
  const AProposEcran({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('À propos de nous')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MonFrigo+',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Application créée pour lutter contre le gaspillage alimentaire et faciliter la gestion de votre frigo.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            const Text(
              'Les codeurs :',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: CircleAvatar(child: Text('A')),
              title: Text('Daryl Coddeville'),
              subtitle: Text(
                'Daryl, 22 ans, étudiant à Esiee Paris en filière Data et Application. J ai choisi de travailler sur cette application car elle répond aux besoins concrets des utilisateurs et elle permet de lutter contre le gaspillage alimentaire.',
              ),
            ),
            ListTile(
              leading: CircleAvatar(child: Text('B')),
              title: Text('Maxence Delehelle'),
              subtitle: Text(
                'étudiant ingénieur à ESIEE PARIS en filière Data et Applications. Je suis convaincu que les enjeux environnementaux et societaux sont les défis de demain pour les ingénieurs',
              ),
            ),
            ListTile(
              leading: CircleAvatar(child: Text('C')),
              title: Text('Amine El Mouttaki'),
              subtitle: Text(
                "Étudiant en informatique à l’ESIEE Paris, j’ai géré la partie back-end de MonFrigo+, notamment l’intégration de Firebase et la gestion du frigo partagé. Passionné de musculation et de football, je suis motivé par les projets concrets et collaboratifs.",
              ),
            ),
            ListTile(
              leading: CircleAvatar(child: Text('C')),
              title: Text('Amine Saad-Eddine'),
              subtitle: Text(
                "Étudiant en ingénierie à l’ESIEE Paris, je me spécialise en Data et Applications. Passionné par la technologie et soucieux des enjeux environnementaux, j’ai co-développé MonFrigo+, une application mobile destinée à lutter contre le gaspillage alimentaire.",
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Merci d\'utiliser notre application !',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

class StatistiquesEcran extends StatelessWidget {
  final String familleId;
  const StatistiquesEcran({Key? key, required this.familleId})
    : super(key: key);

  Future<Map<String, int>> getStats() async {
    final doc = await FirebaseFirestore.instance
        .collection('familles')
        .doc(familleId)
        .collection('stats')
        .doc('global')
        .get();
    final data = doc.data() ?? {};
    return {
      'total_ajoutes': data['total_ajoutes'] ?? 0,
      'total_non_gaspilles': data['total_non_gaspilles'] ?? 0,
      'total_gaspilles': data['total_gaspilles'] ?? 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: FutureBuilder<Map<String, int>>(
        future: getStats(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snapshot.data!;
          final total = stats['total_ajoutes']!;
          final nonGaspilles = stats['total_non_gaspilles']!;
          final gaspilles = stats['total_gaspilles']!;
          final pourcentage = total > 0
              ? (nonGaspilles / total * 100).toStringAsFixed(1)
              : '0';

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Vos statistiques anti-gaspillage',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Produits ajoutés : $total',
                      style: const TextStyle(fontSize: 18),
                    ),
                    Text(
                      'Non gaspillés : $nonGaspilles',
                      style: const TextStyle(fontSize: 18),
                    ),
                    Text(
                      'Gaspillés : $gaspilles',
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: total > 0 ? nonGaspilles / total : 0,
                      minHeight: 12,
                      backgroundColor: Colors.grey[200],
                      color: Colors.green,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$pourcentage % de produits non gaspillés !',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
