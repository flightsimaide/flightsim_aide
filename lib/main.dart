import 'package:flutter/material.dart';

import 'app.dart';
import 'config/dependencies_production.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(App(providers: productionProviders()));
}
