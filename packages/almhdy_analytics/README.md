# AlmHdy Analytics Flutter SDK

Cross-platform telemetry SDK for Flutter apps across Android, iOS, and Windows Desktop.

## Features
- **Cross-Platform**: Android, iOS, Windows, macOS, Linux.
- **Offline Resilient**: Local disk persistence during network disconnects.
- **Automatic Batching**: Collects events and flushes periodically or when batch size is reached.
- **Session Management**: Automatically rotates sessions on 30 minutes of inactivity.
- **Privacy First**: Zero plaintext PII. Automatically filters sensitive keys.
- **Opt-Out Compliant**: In-app opt-out synchronization with server.

## Installation

Add to your `pubspec.yaml`:
```yaml
dependencies:
  almhdy_analytics:
    path: path/to/sdk/flutter
```

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:almhdy_analytics/almhdy_analytics.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AlmHdyAnalytics.instance.initialize(
    projectKey: 'ak_live_your_project_key',
    appVersion: '1.2.0',
    debug: false,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Cashirak POS')),
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              AlmHdyAnalytics.instance.track(
                'receipt_printed',
                properties: {
                  'item_count': 5,
                  'payment_method': 'cash',
                },
              );
            },
            child: const Text('Print Receipt'),
          ),
        ),
      ),
    );
  }
}
```

## Development & Verification

When developing on a workstation or CI environment with the Flutter / Dart SDK installed:

```bash
# Analyze package code for lint and type warnings
dart analyze sdk/flutter/

# Format code
dart format sdk/flutter/

# Run unit tests
flutter test sdk/flutter/test/
```
