import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/library_page.dart';

void main() => runApp(const ProviderScope(child: EnglishLearningPlayer()));

class EnglishLearningPlayer extends StatelessWidget {
  const EnglishLearningPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Learning Player',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const LibraryPage(),
    );
  }
}
