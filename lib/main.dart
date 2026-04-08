import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
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
}

class Category {
  int? id;
  String name;

  Category({this.id, required this.name});
}

class AlertState {
  bool l1 = false;
  bool l2 = false;
  bool l3 = false;
}

class DBHelper {
  static Database? _db;

  static Future<Database> getDB() async {
    if (_db != null) return _db!;

    String path = p.join(await getDatabasesPath(), 'raa.db');

    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute(
          'CREATE TABLE alerts(id INTEGER PRIMARY KEY AUTOINCREMENT, lat REAL, lon REAL, type TEXT)');
      await db.execute(
          'CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');

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
    return MaterialApp(
      title: 'RAA',
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Alert> alerts = [];
  List<Category> categories = [];
  Map<int, AlertState> alertStates = {};

  FlutterTts tts = FlutterTts();
  Position? currentPosition;

  double d1 = 60, d2 = 30, d3 = 10, resetDistance = 25;

  // 🔇 DEFAULT MUTED
  bool isMuted = true;

  @override
  void initState() {
    super.initState();
    initLocation();
    loadData();
  }

  Future<void> initLocation() async {
    await Geolocator.requestPermission();
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

      for (var a in alerts) {
        if (a.id != null) {
          alertStates[a.id!] = AlertState();
        }
      }
    });
  }

  Future<void> addAlert(String type) async {
    Position pos = await Geolocator.getCurrentPosition();

    final db = await DBHelper.getDB();
    await db.insert(
        'alerts', {'lat': pos.latitude, 'lon': pos.longitude, 'type': type});

    loadData();

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("$type saved")));
  }

  Future<void> deleteAlert(int id) async {
    final db = await DBHelper.getDB();
    await db.delete('alerts', where: 'id=?', whereArgs: [id]);
    loadData();
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

  void speak(String text) async {
    if (!isMuted) {
      await tts.setSpeechRate(0.5);
      await tts.speak(text);
    }
  }

  void startTracking() {
    Geolocator.getPositionStream(
      locationSettings:
          LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5),
    ).listen((pos) {
      setState(() {
        currentPosition = pos;
      });

      for (var a in alerts) {
        if (a.id == null) continue;

        double d = distance(pos.latitude, pos.longitude, a.lat, a.lon);
        var state = alertStates[a.id!] ?? AlertState();

        if (d < d1 && !state.l1) {
          speak("${a.type} ahead");
          state.l1 = true;
        }

        if (d < d2 && !state.l2) {
          speak("Approaching ${a.type}");
          state.l2 = true;
        }

        if (d < d3 && !state.l3) {
          speak("${a.type} now");
          state.l3 = true;
        }

        if (d > resetDistance) {
          alertStates[a.id!] = AlertState();
        } else {
          alertStates[a.id!] = state;
        }
      }
    });
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
                          onTap: () {
                            addAlert(c.name);
                            Navigator.pop(context);
                          },
                        ))
                    .toList(),
              ),
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
            onPressed: () {
              setState(() {
                isMuted = !isMuted;
              });
            },
          )
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  currentPosition == null
                      ? "Getting location..."
                      : "Lat: ${currentPosition!.latitude.toStringAsFixed(5)}\nLon: ${currentPosition!.longitude.toStringAsFixed(5)}",
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
            SizedBox(height: 10),
            Text("Total Alerts: ${alerts.length}",
                style: TextStyle(fontSize: 18)),
            SizedBox(height: 10),
            ElevatedButton(
                onPressed: showAddAlert, child: Text("Add Alert")),
            Expanded(
              child: ListView.builder(
                  itemCount: alerts.length,
                  itemBuilder: (_, i) {
                    var a = alerts[i];
                    return Card(
                      child: ListTile(
                        title: Text("${i + 1}. ${a.type}"),
                        subtitle: Text("${a.lat}, ${a.lon}"),
                        trailing: IconButton(
                            icon: Icon(Icons.delete),
                            onPressed: () => deleteAlert(a.id!)),
                      ),
                    );
                  }),
            )
          ],
        ),
      ),
    );
  }
}
