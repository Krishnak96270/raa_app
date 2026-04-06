import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:math';

void main() {
  runApp(MyApp());
}

class AlertPoint {
  double lat;
  double lon;
  String type;

  AlertPoint(this.lat, this.lon, this.type);
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RAA',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<AlertPoint> points = [];
  FlutterTts tts = FlutterTts();

  double alertDistance = 80;
  bool isMuted = false;

  @override
  void initState() {
    super.initState();
    initLocation();
  }

  // Initialize permissions
  Future<void> initLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }

    startTracking();
  }

  // Add alert point
  Future<void> addPoint(String type) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enable GPS")),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Location permission denied")),
      );
      return;
    }

    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        points.add(AlertPoint(pos.latitude, pos.longitude, type));
      });

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "$type saved at (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})"),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error getting location")),
      );
    }
  }

  // Distance calculation
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

  // Voice alert
  void speak(String text) async {
    if (!isMuted) {
      await tts.setVolume(1.0);
      await tts.setSpeechRate(0.5);
      await tts.speak(text);
    }
  }

  // Background tracking
  void startTracking() {
    Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((Position pos) {
      for (var p in points) {
        double d = distance(pos.latitude, pos.longitude, p.lat, p.lon);

        if (d < alertDistance) {
          speak("${p.type} ahead");
        }
      }
    });
  }

  // Add dialog
  void showAddDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Add Alert"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
                onPressed: () => addPoint("Speed breaker"),
                child: Text("Speed Breaker")),
            ElevatedButton(
                onPressed: () => addPoint("Speed camera"),
                child: Text("Speed Camera")),
            ElevatedButton(
                onPressed: () => addPoint("Village area"),
                child: Text("Village Area")),
          ],
        ),
      ),
    );
  }

  // Change distance
  void changeDistance() {
    showDialog(
      context: context,
      builder: (_) {
        TextEditingController controller =
            TextEditingController(text: alertDistance.toString());

        return AlertDialog(
          title: Text("Set Distance (meters)"),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                setState(() {
                  alertDistance = double.tryParse(controller.text) ?? 80;
                });
                Navigator.pop(context);
              },
              child: Text("Save"),
            )
          ],
        );
      },
    );
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Total Alerts: ${points.length}",
                style: TextStyle(fontSize: 18)),
            SizedBox(height: 20),
            ElevatedButton(
                onPressed: showAddDialog, child: Text("Add Alert")),
            SizedBox(height: 10),
            ElevatedButton(
                onPressed: changeDistance,
                child: Text("Set Distance (${alertDistance.toInt()} m)")),
          ],
        ),
      ),
    );
  }
}
