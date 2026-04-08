import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:io';

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

class AlertState {
  bool l1 = false, l2 = false, l3 = false;
}

class DBHelper {
  static Database? _db;

  static Future<Database> getDB() async {
    if (_db != null) return _db!;

    String path = p.join(await getDatabasesPath(), 'raa.db');

    _db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute(
          'CREATE TABLE alerts(id INTEGER PRIMARY KEY AUTOINCREMENT, lat REAL, lon REAL, type TEXT)');
    });

    return _db!;
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, home: HomePage());
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Alert> alerts = [];
  Map<int, AlertState> states = {};

  FlutterTts tts = FlutterTts();
  Position? currentPosition;

  bool isMuted = true;

  double d1 = 60, d2 = 30, d3 = 10, resetDistance = 25;

  double threshold = 12;
  DateTime lastDetection = DateTime.now();

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    await Geolocator.requestPermission();
    loadData();
    track();
    detectMotion();
  }

  Future<void> loadData() async {
    final db = await DBHelper.getDB();
    final data = await db.query('alerts');

    setState(() {
      alerts = data
          .map((e) => Alert(
              id: e['id'] as int,
              lat: e['lat'] as double,
              lon: e['lon'] as double,
              type: e['type'] as String))
          .toList();

      for (var a in alerts) {
        states[a.id!] = AlertState();
      }
    });
  }

  double distance(a, b, c, d) {
    const R = 6371000;
    double dLat = (c - a) * pi / 180;
    double dLon = (d - b) * pi / 180;
    double x = sin(dLat / 2) * sin(dLat / 2) +
        cos(a * pi / 180) *
            cos(c * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return R * 2 * atan2(sqrt(x), sqrt(1 - x));
  }

  Future<void> saveAlert(double lat, double lon, String type) async {
    final db = await DBHelper.getDB();
    final data = await db.query('alerts');

    for (var e in data) {
      if (distance(lat, lon, e['lat'], e['lon']) < 15) return;
    }

    await db.insert('alerts', {'lat': lat, 'lon': lon, 'type': type});
    loadData();
  }

  void detectMotion() {
    accelerometerEvents.listen((e) async {
      if (e.z > threshold &&
          DateTime.now().difference(lastDetection).inSeconds > 5) {
        lastDetection = DateTime.now();

        if (currentPosition != null) {
          String type = e.z > 15 ? "Speed Breaker" : "Pothole";
          await saveAlert(
              currentPosition!.latitude, currentPosition!.longitude, type);

          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("$type detected & saved")));
        }
      }
    });
  }

  void track() {
    Geolocator.getPositionStream().listen((pos) {
      setState(() => currentPosition = pos);

      for (var a in alerts) {
        double d = distance(pos.latitude, pos.longitude, a.lat, a.lon);
        var s = states[a.id!] ?? AlertState();

        if (d < d1 && !s.l1) {
          speak("${a.type} ahead");
          s.l1 = true;
        }
        if (d < d2 && !s.l2) {
          speak("Approaching ${a.type}");
          s.l2 = true;
        }
        if (d < d3 && !s.l3) {
          speak("${a.type} now");
          s.l3 = true;
        }

        if (d > resetDistance) {
          states[a.id!] = AlertState();
        } else {
          states[a.id!] = s;
        }
      }
    });
  }

  void speak(String text) async {
    if (!isMuted) await tts.speak(text);
  }

  Future<void> deleteAlert(int id) async {
    final db = await DBHelper.getDB();
    await db.delete('alerts', where: 'id=?', whereArgs: [id]);
    loadData();
  }

  Future<void> exportData() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/raa_backup.json");

    await file.writeAsString(jsonEncode(alerts
        .map((e) => {'lat': e.lat, 'lon': e.lon, 'type': e.type})
        .toList()));

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("Exported")));
  }

  void manualAdd() async {
    if (currentPosition != null) {
      await saveAlert(currentPosition!.latitude,
          currentPosition!.longitude, "Manual");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("RAA"),
        actions: [
          IconButton(
              icon: Icon(isMuted ? Icons.volume_off : Icons.volume_up),
              onPressed: () => setState(() => isMuted = !isMuted)),
          IconButton(icon: Icon(Icons.download), onPressed: exportData),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: manualAdd,
        child: Icon(Icons.add),
      ),
      body: Column(
        children: [
          SizedBox(height: 10),
          Text(currentPosition == null
              ? "Getting location..."
              : "Lat: ${currentPosition!.latitude.toStringAsFixed(5)} | Lon: ${currentPosition!.longitude.toStringAsFixed(5)}"),
          Text("Total Alerts: ${alerts.length}"),
          Expanded(
            child: ListView.builder(
                itemCount: alerts.length,
                itemBuilder: (_, i) {
                  var a = alerts[i];
                  return Card(
                    child: ListTile(
                      title: Text("${i + 1}. ${a.type}"),
                      subtitle: Text("${a.lat}, ${a.lon}"),
                      trailing: PopupMenuButton(
                        itemBuilder: (context) => [
                          PopupMenuItem(
                              child: Text("Delete"),
                              onTap: () => deleteAlert(a.id!))
                        ],
                      ),
                    ),
                  );
                }),
          )
        ],
      ),
    );
  }
}
