import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: IntroPage(),
  ));
}

//////////////////////////////////////////////////////
/// MODEL: HARD PHYSICS BOID
//////////////////////////////////////////////////////

class Boid {
  double x, y, vx, vy;
  double mass;

  static const double areaSize = 500.0;
  static const double radius = 8.0;

  Boid(this.x, this.y, this.vx, this.vy, {this.mass = 1.0});

  void update() {
    x += vx;
    y += vy;

    // Hard wall bounce
    if (x < radius) {
      x = radius;
      vx *= -0.8;
    }
    if (x > areaSize - radius) {
      x = areaSize - radius;
      vx *= -0.8;
    }
    if (y < radius) {
      y = radius;
      vy *= -0.8;
    }
    if (y > areaSize - radius) {
      y = areaSize - radius;
      vy *= -0.8;
    }
  }

  void resolveCollision(Boid other) {
    double dx = other.x - x;
    double dy = other.y - y;
    double distance = sqrt(dx * dx + dy * dy);
    double minDistance = radius * 2;

    if (distance < minDistance && distance > 0) {
      double overlap = (minDistance - distance) / 2;
      double nx = dx / distance;
      double ny = dy / distance;

      x -= nx * overlap;
      y -= ny * overlap;
      other.x += nx * overlap;
      other.y += ny * overlap;

      double rvx = other.vx - vx;
      double rvy = other.vy - vy;

      double velAlongNormal = rvx * nx + rvy * ny;
      if (velAlongNormal > 0) return;

      double e = 0.9;

      double j = -(1 + e) * velAlongNormal;
      j /= (1 / mass + 1 / other.mass);

      double impulseX = j * nx;
      double impulseY = j * ny;

      vx -= (1 / mass) * impulseX;
      vy -= (1 / mass) * impulseY;
      other.vx += (1 / other.mass) * impulseX;
      other.vy += (1 / other.mass) * impulseY;
    }
  }

  Map<String, double> toJson() => {
        'x': x,
        'y': y,
      };
}

//////////////////////////////////////////////////////
/// CLIENT PAGE (LOCAL PHYSICS ENGINE)
//////////////////////////////////////////////////////

class ClientPage extends StatefulWidget {
  const ClientPage({super.key});

  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  late List<Boid> boids;
  Timer? timer;

  @override
  void initState() {
    super.initState();

    final r = Random();
    boids = List.generate(30, (_) {
      return Boid(
        r.nextDouble() * 400 + 50,
        r.nextDouble() * 400 + 50,
        r.nextDouble() * 10 - 5,
        r.nextDouble() * 10 - 5,
      );
    });

    timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _updatePhysics();
    });
  }

  void _updatePhysics() {
    for (int i = 0; i < boids.length; i++) {
      for (int j = i + 1; j < boids.length; j++) {
        boids[i].resolveCollision(boids[j]);
      }
    }

    for (var b in boids) {
      b.update();
    }

    setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomPaint(
        painter: HardPainter(boids),
        size: Size.infinite,
      ),
    );
  }
}

//////////////////////////////////////////////////////
/// PAINTER
//////////////////////////////////////////////////////

class HardPainter extends CustomPainter {
  final List<Boid> boids;

  HardPainter(this.boids);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;

    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var b in boids) {
      double dx = (b.x / 500.0) * size.width;
      double dy = (b.y / 500.0) * size.height;

      canvas.drawCircle(Offset(dx, dy), 8, fill);
      canvas.drawCircle(Offset(dx, dy), 8, border);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

//////////////////////////////////////////////////////
/// INTRO PAGE
//////////////////////////////////////////////////////

class IntroPage extends StatelessWidget {
  const IntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ClientPage()),
            );
          },
          child: const Text("START FLOCK"),
        ),
      ),
    );
  }
}