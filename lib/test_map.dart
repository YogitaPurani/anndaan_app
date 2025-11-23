import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TestMap extends StatelessWidget {
  const TestMap({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map Test')),
      body: const GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(28.6139, 77.2090), // Delhi
          zoom: 12,
        ),
      ),
    );
  }
}
