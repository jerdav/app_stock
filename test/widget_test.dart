import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_app/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('shows stock dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const StockApp());
    await pumpUntilFound(tester, find.text('Vue du stock'));

    expect(find.text('Stock Boutique'), findsOneWidget);
    expect(find.text('Vue du stock'), findsOneWidget);
    expect(find.text('Produits'), findsWidgets);
    expect(find.byIcon(Icons.dashboard), findsOneWidget);
  });

  testWidgets('opens the product form', (WidgetTester tester) async {
    await tester.pumpWidget(const StockApp());
    await pumpUntilFound(tester, find.text('Vue du stock'));

    await tester.tap(find.byTooltip('Ajouter'));
    await pumpUntilFound(tester, find.text('Nouveau modele'));

    expect(find.text('Nouveau modele'), findsOneWidget);
    expect(find.text('Nom du modele'), findsOneWidget);
    expect(find.text('Couleur'), findsOneWidget);
    expect(find.text('Taille'), findsOneWidget);
  });
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 40,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  expect(finder, findsOneWidget);
}
