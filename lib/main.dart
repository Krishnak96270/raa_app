import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:math';

void main() {
  runApp(MyApp());
}

class Alert {
  int? id;
  double lat;
  double lon;
  String type;

  Alert({this.id, required this.lat, required this.lon, required this.type});

  Map<String, dynamic> toMap() {
    return {'id': id, 'lat': lat, 'lon': lon, 'type': type};
  }
}

class Category {
  int? id;
  String name;

  Category({this.id, required this.name});

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name};
  }
}

class DBHelper {
  static Database? _db;

  static Future<Database> getDB() async {
    if (_db != null) return _db!;

    String path = join(await getDatabasesPath(), 'raa.db');

    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute(
          'CREATE TABLE alerts(id INTEGER PRIMARY KEY, lat REAL, lon REAL, type TEXT)');
      await db.execute(
          'CREATE TABLE categories(id INTEGER PRIMARY KEY, name TEXT)');

      await db.insert('categories', {'name': 'Speed Breaker'});
      await db.insert('categories', {'name': 'Speed Camera'});
      await db.insert('categories', {'name': 'Village'});
    });

    return _db!;
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'RAA', home: HomePage());
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Alert> alerts = [];
  List<Category> categories = [];
  FlutterTts tts = FlutterTts();
  double alertDistance = 80;
  bool isMuted = false;

  @override
  void initState() {
    super.initState();
    loadData();
    startTracking();
  }

  Future<void> loadData() async {
    final db = await DBHelper.getDB();

    final alertData = await db.query('alerts');
    final catData = await db.query('categories');

    setState(() {
      alerts = alertData
          .map((e) => Alert(
              id: e['id'] as int,
              lat: e['lat'] as double,
              lon: e['lon'] as double,
              type: e['type'] as String))
          .toList();

      categories = catData
          .map((e) => Category(id: e['id'] as int, name: e['name'] as String))
          .toList();
    });
  }

  Future<void> addCategory(String name) async {
    final db = await DBHelper.getDB();
    await db.insert('categories', {'name': name});
    loadData();
  }

  Future<void> deleteCategory(int id) async {
    final db = await DBHelper.getDB();
    await db.delete('categories', where: 'id=?', whereArgs: [id]);
    loadData();
  }

  Future<void> addAlert(String type) async {
    Position pos = await Geolocator.getCurrentPosition();

    final db = await DBHelper.getDB();
    await db.insert('alerts',
        {'lat': pos.latitude, 'lon': pos.longitude, 'type': type});

    loadData();

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("$type saved")));
  }

  Future<void> deleteAlert(int id) async {
    final db = await DBHelper.getDB();
    await db.delete('alerts', where: 'id=?', whereArgs: [id]);
    loadData();
  }

  double distance(lat1, lon1, lat2, lon2) {
    const R = 6371000;
    double dLat = (lat2 - lat1) * pi / 180;
    double dLon = (lon2 - lon1) * pi / 180;

    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  void startTracking() {
    Geolocator.getPositionStream().listen((pos) {
      for (var a in alerts) {
        double d = distance(pos.latitude, pos.longitude, a.lat, a.lon);

        if (d < alertDistance && !isMuted) {
          tts.speak("${a.type} ahead");
        }
      }
    });
  }

  void showAddCategory() {
    TextEditingController c = TextEditingController();

    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: Text("Add Category"),
              content: TextField(controller: c),
              actions: [
                ElevatedButton(
                    onPressed: () {
                      addCategory(c.text);
                      Navigator.pop(context);
                    },
                    child: Text("Add"))
              ],
            ));
  }

  void showAddAlert() {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: Text("Select Category"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: categories
                    .map((c) => ListTile(
                          title: Text(c.name),
                          trailing: IconButton(
                              icon: Icon(Icons.delete),
                              onPressed: () => deleteCategory(c.id!)),
                          onTap: () {
                            addAlert(c.name);
                            Navigator.pop(context);
                          },
                        ))
                    .toList(),
              ),
              actions: [
                ElevatedButton(
                    onPressed: showAddCategory,
                    child: Text("Add New Category"))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("RAA"),
        actions: [
          IconButton(
              icon: Icon(isMuted ? Icons.volume_off : Icons.volume_up),
              onPressed: () => setState(() => isMuted = !isMuted))
        ],
      ),
      body: Column(
        children: [
          Text("Total Alerts: ${alerts.length}"),
          ElevatedButton(
              onPressed: showAddAlert, child: Text("Add Alert")),
          Expanded(
            child: ListView.builder(
                itemCount: alerts.length,
                itemBuilder: (_, i) {
                  var a = alerts[i];
                  return ListTile(
                    title: Text("${i + 1}. ${a.type}"),
                    subtitle: Text("${a.lat}, ${a.lon}"),
                    trailing: IconButton(
                        icon: Icon(Icons.delete),
                        onPressed: () => deleteAlert(a.id!)),
                  );
                }),
          )
        ],
      ),
    );
  }
}
