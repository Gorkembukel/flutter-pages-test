import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() => runApp(const MaterialApp(home: IntroPage(), debugShowCheckedModeBanner: false));

//////////////////////////////////////////////////////
/// MODEL: HARD PHYSICS BOID
//////////////////////////////////////////////////////
class Boid {
  double x, y, vx, vy;
  double mass; // Kütle (Boyuta göre değişebilir)
  static const double areaSize = 500.0;
  static const double radius = 8.0;

  Boid(this.x, this.y, this.vx, this.vy, {this.mass = 1.0});

  void update() {
    x += vx;
    y += vy;

    // Duvarlardan Sekme (Hard Bounce) - Wrap yerine sektirme daha "hard" hissettirir
    if (x < radius) { x = radius; vx *= -0.8; }
    if (x > areaSize - radius) { x = areaSize - radius; vx *= -0.8; }
    if (y < radius) { y = radius; vy *= -0.8; }
    if (y > areaSize - radius) { y = areaSize - radius; vy *= -0.8; }

    // Sürtünme (Hava Direnci)
    vx *= 1.0;//0.995;
    vy *= 1.0;//0.995;
  }

  // HARD COLLISION: Elastic Collision & Impulse Resolution
  void resolveCollision(Boid other) {
    double dx = other.x - x;
    double dy = other.y - y;
    double distance = sqrt(dx * dx + dy * dy);
    double minDistance = radius * 2;

    if (distance < minDistance && distance > 0) {
      // 1. STATİK ÇÖZÜM: Birbirlerinin içine girmelerini engelle
      double overlap = (minDistance - distance) / 2;
      double nx = dx / distance; // Normal X
      double ny = dy / distance; // Normal Y
      
      x -= nx * overlap;
      y -= ny * overlap;
      other.x += nx * overlap;
      other.y += ny * overlap;

      // 2. DİNAMİK ÇÖZÜM: Momentum Transferi (Impulse)
      // Bağıl Hız
      double rvx = other.vx - vx;
      double rvy = other.vy - vy;
      
      // Normal doğrultusundaki hız (Dot Product)
      double velAlongNormal = rvx * nx + rvy * ny;

      // Eğer zaten uzaklaşıyorlarsa işlem yapma
      if (velAlongNormal > 0) return;

      // Esneklik (Restitution): 1.0 tam seker, 0.0 yapışır
      double e = 0.9; 

      // Impulse scalar (J)
      double j = -(1 + e) * velAlongNormal;
      j /= (1 / mass + 1 / other.mass);

      // Impulse vektörlerini uygula
      double impulseX = j * nx;
      double impulseY = j * ny;

      vx -= (1 / mass) * impulseX;
      vy -= (1 / mass) * impulseY;
      other.vx += (1 / other.mass) * impulseX;
      other.vy += (1 / other.mass) * impulseY;
    }
  }

  Map<String, double> toJson() => {'x': x, 'y': y, 'vx': vx, 'vy': vy};
}

//////////////////////////////////////////////////////
/// SERVER: PHYSICS ENGINE
//////////////////////////////////////////////////////
class FlockingServer {
  static final FlockingServer _instance = FlockingServer._internal();
  factory FlockingServer() => _instance;
  FlockingServer._internal();

  final Set<WebSocketChannel> _clients = {};
  bool isRunning = false;
  final List<Boid> boids = List.generate(30, (_) {
    var r = Random();
    return Boid(
      r.nextDouble() * 400 + 50, 
      r.nextDouble() * 400 + 50, 
      r.nextDouble() * 10 - 5, 
      r.nextDouble() * 10 - 5
    );
  });

  Future<void> start() async {
    if (isRunning) return;
    final router = shelf_router.Router();
    router.get('/ws', webSocketHandler((WebSocketChannel socket) {
      _clients.add(socket);
      socket.stream.listen((_) {}, onDone: () => _clients.remove(socket));
    }));

    await io.serve(const Pipeline().addHandler(router), InternetAddress.anyIPv4, 8080);
    isRunning = true;

    // Hard Physics Loop (60 FPS)
    Timer.periodic(const Duration(milliseconds: 16), (timer) {
      // Çarpışmaları çöz (Çift döngü)
      for (int i = 0; i < boids.length; i++) {
        for (int j = i + 1; j < boids.length; j++) {
          boids[i].resolveCollision(boids[j]);
        }
      }
      // Hareketleri güncelle
      for (var b in boids) b.update();
      _broadcast();
    });
  }

  void _broadcast() {
    if (_clients.isEmpty) return;
    final data = jsonEncode(boids.map((b) => b.toJson()).toList());
    for (var client in _clients.toList()) {
      try { client.sink.add(data); } catch (e) { _clients.remove(client); }
    }
  }
}

//////////////////////////////////////////////////////
/// UI: CLIENT & PAINTER
//////////////////////////////////////////////////////
class ClientPage extends StatefulWidget {
  const ClientPage({super.key});
  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  WebSocketChannel? channel;
  List<dynamic> boids = [];
  final _ipController = TextEditingController(text: "10.113.16.201");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          SafeArea(child: TextField(controller: _ipController, style: const TextStyle(color: Colors.white))),
          ElevatedButton(onPressed: () {
            channel = WebSocketChannel.connect(Uri.parse("ws://${_ipController.text}:8080/ws"));
            channel!.stream.listen((data) => setState(() => boids = jsonDecode(data)));
          }, child: const Text("HARD CONNECT")),
          Expanded(child: CustomPaint(painter: HardPainter(boids), size: Size.infinite)),
        ],
      ),
    );
  }
}

class HardPainter extends CustomPainter {
  final List<dynamic> boids;
  HardPainter(this.boids);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.redAccent..style = PaintingStyle.fill;
    final border = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1;

    for (var b in boids) {
      double dx = (b['x'] / 500.0) * size.width;
      double dy = (b['y'] / 500.0) * size.height;
      canvas.drawCircle(Offset(dx, dy), 8, p);
      canvas.drawCircle(Offset(dx, dy), 8, border);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class IntroPage extends StatelessWidget {
  const IntroPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(onPressed: () => FlockingServer().start(), child: const Text("START HARD ENGINE")),
            ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ClientPage())), child: const Text("OPEN MONITOR")),
          ],
        ),
      ),
    );
  }
}