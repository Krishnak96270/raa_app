import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:sensors_plus/sensors_plus.dart';
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
  Map<int, AlertState> alertStates = {};

  FlutterTts tts = FlutterTts();
  Position? currentPosition;

  double d1 = 60, d2 = 30, d3 = 10, resetDistance = 25;

  bool isMuted = true;

  // Motion detection
  double threshold = 12.0;
  DateTime lastDetection = DateTime.now();

  @override
  void initState() {
    super.initState();
    initLocation();
    loadData();
    startMotionDetection();
  }

  Future<void> initLocation() async {
    await Geolocator.requestPermission();
    startTracking();
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
        alertStates[a.id!] = AlertState();
      }
    });
  }

  Future<void> saveAlert(double lat, double lon) async {
    final db = await DBHelper.getDB();
    await db.insert('alerts',
        {'lat': lat, 'lon': lon, 'type': 'Speed Breaker'});
    loadData();
  }

  void startMotionDetection() {
    accelerometerEvents.listen((event) async {
      double z = event.z;

      if (z > threshold &&
          DateTime.now().difference(lastDetection).inSeconds > 5) {
        lastDetection = DateTime.now();

        if (currentPosition != null) {
          await saveAlert(
              currentPosition!.latitude, currentPosition!.longitude);

          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Bump detected & saved")));
        }
      }
    });
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
      await tts.speak(text);
    }
  }

  void startTracking() {
    Geolocator.getPositionStream().listen((pos) {
      setState(() {
        currentPosition = pos;
      });

      for (var a in alerts) {
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
      body: Column(
        children: [
          SizedBox(height: 10),
          Text(
            currentPosition == null
                ? "Getting location..."
                : "Lat: ${currentPosition!.latitude.toStringAsFixed(5)} | Lon: ${currentPosition!.longitude.toStringAsFixed(5)}",
          ),
          Text("Total Alerts: ${alerts.length}"),
        ],
      ),
    );
  }
}
