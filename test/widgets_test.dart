import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitpush/models/git_file.dart';
import 'package:gitpush/utils/url_utils.dart';
import 'package:gitpush/widgets/file_card.dart';

void main() {
  testWidgets('Mod B kart senkronu: yol dışarıdan değişince metin alanı da güncellenir', (tester) async {
    final file = GitFileItem(
      localPath: 'a.dart',
      repoPath: 'a.dart',
      sourceName: 'a.dart',
      size: 1,
      bytes: Uint8List(1),
    );
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return FileCard(
                file: file,
                onSelectPath: () {},
                onPathChanged: (_) {},
                onDelete: () {},
              );
            },
          ),
        ),
      ),
    );

    // path picker / öneri çipi / kısayol / metin komutu bunu provider üzerinden yapar
    rebuild(() => file.repoPath = 'lib/screens/a.dart');
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'lib/screens/a.dart');
  });

  testWidgets('link açılamazsa SnackBar ve Kopyala eylemi görünür', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openExternalUrl(context, ''),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Link açılamadı.'), findsOneWidget);
    expect(find.text('Kopyala'), findsOneWidget);
  });
}
