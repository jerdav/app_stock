import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../main.dart';
import 'stock_seed.dart';

class StockDatabase {
  StockDatabase._();

  static final StockDatabase instance = StockDatabase._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final databasePath = await getDatabasesPath();
    final path = p.join(databasePath, 'stock_pilot.db');

    _database = await openDatabase(
      path,
      version: 6,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _create,
      onUpgrade: _upgrade,
    );

    return _database!;
  }

  Future<String> getDatabasePath() async {
    final databasePath = await getDatabasesPath();
    return p.join(databasePath, 'stock_pilot.db');
  }

  Future<void> close() async {
    final db = _database;
    if (db == null) {
      return;
    }

    await db.close();
    _database = null;
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sku TEXT NOT NULL,
        category_id INTEGER NOT NULL,
        brand TEXT NOT NULL,
        location TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE variants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        color TEXT NOT NULL,
        color_hex TEXT,
        size TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        minimum_quantity INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    await _createColorsTable(db);

    await db.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        variant_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        variant_label TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
        FOREIGN KEY (variant_id) REFERENCES variants (id) ON DELETE CASCADE
      )
    ''');

    await _seed(db);
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE variants ADD COLUMN color_hex TEXT');
    }
    if (oldVersion < 4) {
      await _createColorsTable(db);
      await _seedColorsFromVariants(db);
    }
    if (oldVersion < 5) {
      await _normalizeKidsSku(db);
    }
    if (oldVersion < 6) {
      await _syncProductCategories(db);
    }
  }

  Future<void> _normalizeKidsSku(DatabaseExecutor db) async {
    await db.rawUpdate('''
      UPDATE products
      SET sku = REPLACE(sku, '-KID', '')
      WHERE sku LIKE 'K-%-KID'
    ''');
  }

  Future<void> _syncProductCategories(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();
    for (final category in productCategories) {
      await db.insert(
        'categories',
        {'name': category, 'created_at': now},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    final allowedRows = await db.query(
      'categories',
      columns: ['id'],
      where:
          'name IN (${List.filled(productCategories.length, '?').join(', ')})',
      whereArgs: productCategories,
    );
    final allowedIds = allowedRows.map((row) => row['id'] as int).toList();
    final defaultCategoryId = await _categoryId(db, productCategories.first);

    if (allowedIds.isNotEmpty) {
      await db.update(
        'products',
        {'category_id': defaultCategoryId},
        where:
            'category_id NOT IN (${List.filled(allowedIds.length, '?').join(', ')})',
        whereArgs: allowedIds,
      );
    }

    await db.delete(
      'categories',
      where:
          'name NOT IN (${List.filled(productCategories.length, '?').join(', ')})',
      whereArgs: productCategories,
    );
  }

  Future<void> _createColorsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS colors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        hex TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _seedColorsFromVariants(DatabaseExecutor db) async {
    final rows = await db.rawQuery('''
      SELECT color, color_hex
      FROM variants
      WHERE color_hex IS NOT NULL AND TRIM(color_hex) != ''
      GROUP BY LOWER(TRIM(color))
    ''');

    for (final row in rows) {
      final name = row['color'] as String?;
      final hex = row['color_hex'] as String?;
      if (name == null || hex == null) {
        continue;
      }
      await _upsertColor(db, name: name, hex: hex);
    }
  }

  Future<void> _seed(Database db) async {
    for (final category in productCategories) {
      await db.insert('categories', {
        'name': category,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    for (final product in stockSeedProducts) {
      await _insertSeedProduct(
        db,
        product: product,
        categoryId: await _categoryId(db, product.category),
      );
    }
  }

  Future<int> _categoryId(DatabaseExecutor db, String name) async {
    final rows = await db.query(
      'categories',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );

    return rows.first['id'] as int;
  }

  Future<void> _insertSeedProduct(
    Database db, {
    required SeedProductData product,
    required int categoryId,
  }) async {
    final now = DateTime.now().toIso8601String();
    final productId = await db.insert('products', {
      'name': product.name,
      'sku': _seedSku(product),
      'category_id': categoryId,
      'brand': 'Reassort',
      'location': 'Stock principal',
      'created_at': now,
    });

    for (final variant in product.variants) {
      final variantId = await db.insert('variants', {
        'product_id': productId,
        'color': variant.color,
        'color_hex': null,
        'size': variant.size,
        'quantity': variant.quantity,
        'minimum_quantity': 1,
        'created_at': now,
      });

      if (variant.quantity > 0) {
        await db.insert('stock_movements', {
          'product_id': productId,
          'variant_id': variantId,
          'product_name': product.name,
          'variant_label': '${variant.color} / ${variant.size}',
          'quantity': variant.quantity,
          'type': MovementType.input.name,
          'created_at': now,
        });
      }
    }
  }

  String _seedSku(SeedProductData product) {
    return seedSku(product);
  }

  Future<List<String>> getCategories() async {
    final db = await database;
    final rows = await db.query('categories', orderBy: 'name ASC');
    return rows.map((row) => row['name'] as String).toList();
  }

  Future<void> insertCategory(String name) async {
    final db = await database;
    final cleanName = normalizeProductCategory(name);
    if (cleanName.isEmpty) {
      return;
    }

    await db.insert(
      'categories',
      {
        'name': cleanName,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> renameCategory(String oldName, String newName) async {
    final db = await database;
    final cleanName = normalizeProductCategory(newName);
    if (cleanName.isEmpty) {
      return;
    }

    await db.update(
      'categories',
      {'name': cleanName},
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [oldName.trim()],
    );
  }

  Future<bool> deleteCategory(String name) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(products.id) AS product_count
      FROM categories
      LEFT JOIN products ON products.category_id = categories.id
      WHERE categories.name = ? COLLATE NOCASE
      ''',
      [name.trim()],
    );
    final productCount = Sqflite.firstIntValue(rows) ?? 0;
    if (productCount > 0) {
      return false;
    }

    await db.delete(
      'categories',
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [name.trim()],
    );
    return true;
  }

  Future<Map<String, String>> getColors() async {
    final db = await database;
    return _colorHexByName(db);
  }

  Future<Map<String, String>> _colorHexByName(DatabaseExecutor db) async {
    final rows = await db.query('colors', orderBy: 'name ASC');

    return {
      for (final row in rows)
        colorLookupKey(row['name'] as String): row['hex'] as String,
    };
  }

  Future<List<Product>> getProducts() async {
    final db = await database;
    final productRows = await db.rawQuery('''
      SELECT products.*, categories.name AS category_name
      FROM products
      JOIN categories ON categories.id = products.category_id
      ORDER BY products.created_at DESC
    ''');
    final colorHexByName = await _colorHexByName(db);

    final products = <Product>[];

    for (final row in productRows) {
      final productId = row['id'] as int;
      final variantRows = await db.query(
        'variants',
        where: 'product_id = ?',
        whereArgs: [productId],
        orderBy: 'color ASC, size ASC',
      );

      products.add(
        Product(
          id: productId.toString(),
          name: row['name'] as String,
          sku: row['sku'] as String,
          category: row['category_name'] as String,
          brand: row['brand'] as String,
          location: row['location'] as String,
          variants: variantRows
              .map((row) => _variantFromRow(row, colorHexByName))
              .toList(),
        ),
      );
    }

    return products;
  }

  Future<List<StockMovement>> getMovements() async {
    final db = await database;
    final rows = await db.query(
      'stock_movements',
      orderBy: 'created_at DESC',
      limit: 100,
    );

    return rows.map((row) {
      return StockMovement(
        productName: row['product_name'] as String,
        variantLabel: row['variant_label'] as String,
        quantity: row['quantity'] as int,
        type: _movementType(row['type'] as String),
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }

  Future<Product> insertProduct(ProductFormResult result) async {
    final db = await database;
    final productId = await db.transaction<int>((txn) async {
      final categoryId = await _upsertCategory(txn, result.category);
      await _upsertColorFromForm(txn, result.color, result.colorHex);
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('products', {
        'name': result.name,
        'sku': result.sku,
        'category_id': categoryId,
        'brand': result.brand,
        'location': defaultProductLocation,
        'created_at': now,
      });

      final variantId = await txn.insert('variants', {
        'product_id': id,
        'color': result.color,
        'color_hex': result.colorHex,
        'size': result.size,
        'quantity': result.quantity,
        'minimum_quantity': result.minimumQuantity,
        'created_at': now,
      });

      if (result.quantity > 0) {
        await _insertMovement(
          txn,
          productId: id,
          variantId: variantId,
          productName: result.name,
          variantLabel: '${result.color} / ${result.size}',
          quantity: result.quantity,
          type: MovementType.input,
        );
      }

      return id;
    });

    final products = await getProducts();
    return products.firstWhere((product) => product.id == productId.toString());
  }

  Future<void> updateProduct(Product product, ProductFormResult result) async {
    final db = await database;
    await db.transaction<void>((txn) async {
      final categoryId = await _upsertCategory(txn, result.category);
      await _upsertColorFromForm(txn, result.color, result.colorHex);
      final productId = int.parse(product.id);

      await txn.update(
        'products',
        {
          'name': result.name,
          'sku': result.sku,
          'category_id': categoryId,
          'brand': result.brand,
          'location': product.location,
        },
        where: 'id = ?',
        whereArgs: [productId],
      );

      if (product.variants.isEmpty) {
        await txn.insert('variants', {
          'product_id': productId,
          'color': result.color,
          'color_hex': result.colorHex,
          'size': result.size,
          'quantity': result.quantity,
          'minimum_quantity': result.minimumQuantity,
          'created_at': DateTime.now().toIso8601String(),
        });
      } else {
        await txn.update(
          'variants',
          {
            'color': result.color,
            'color_hex': result.colorHex,
            'size': result.size,
            'quantity': result.quantity,
            'minimum_quantity': result.minimumQuantity,
          },
          where: 'id = ?',
          whereArgs: [int.parse(product.variants.first.id)],
        );
      }
    });
  }

  Future<ProductVariant> insertVariant(
    Product product,
    VariantFormResult result,
  ) async {
    final db = await database;
    final productId = int.parse(product.id);
    final variantId = await db.transaction<int>((txn) async {
      await _upsertColorFromForm(txn, result.color, result.colorHex);
      final id = await txn.insert('variants', {
        'product_id': productId,
        'color': result.color,
        'color_hex': result.colorHex,
        'size': result.size,
        'quantity': result.quantity,
        'minimum_quantity': result.minimumQuantity,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (result.quantity > 0) {
        await _insertMovement(
          txn,
          productId: productId,
          variantId: id,
          productName: product.name,
          variantLabel: '${result.color} / ${result.size}',
          quantity: result.quantity,
          type: MovementType.input,
        );
      }

      return id;
    });

    return ProductVariant(
      id: variantId.toString(),
      color: result.color,
      colorHex: result.colorHex,
      size: result.size,
      quantity: result.quantity,
      minimumQuantity: result.minimumQuantity,
    );
  }

  Future<void> updateVariant(
    Product product,
    ProductVariant variant,
    VariantFormResult result,
  ) async {
    final db = await database;
    await db.transaction<void>((txn) async {
      await _upsertColorFromForm(txn, result.color, result.colorHex);
      await txn.update(
        'variants',
        {
          'color': result.color,
          'color_hex': result.colorHex,
          'size': result.size,
          'quantity': result.quantity,
          'minimum_quantity': result.minimumQuantity,
        },
        where: 'id = ?',
        whereArgs: [int.parse(variant.id)],
      );
    });
  }

  Future<void> changeStock(
    Product product,
    ProductVariant variant,
    int delta,
  ) async {
    if (variant.quantity + delta < 0) {
      return;
    }

    final db = await database;
    await db.transaction<void>((txn) async {
      final newQuantity = variant.quantity + delta;
      await txn.update(
        'variants',
        {'quantity': newQuantity},
        where: 'id = ?',
        whereArgs: [int.parse(variant.id)],
      );

      await _insertMovement(
        txn,
        productId: int.parse(product.id),
        variantId: int.parse(variant.id),
        productName: product.name,
        variantLabel: variant.label,
        quantity: delta.abs(),
        type: delta > 0 ? MovementType.input : MovementType.output,
      );
    });
  }

  Future<void> deleteProduct(Product product) async {
    final db = await database;
    await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [int.parse(product.id)],
    );
  }

  Future<int> _upsertCategory(Transaction txn, String name) async {
    final cleanName = normalizeProductCategory(name);
    if (cleanName.isEmpty) {
      return _categoryId(txn, productCategories.first);
    }
    final rows = await txn.query(
      'categories',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [cleanName],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      return rows.first['id'] as int;
    }

    return txn.insert('categories', {
      'name': cleanName,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _upsertColorFromForm(
    DatabaseExecutor db,
    String name,
    String? hex,
  ) async {
    final cleanName = name.trim();
    final cleanHex = hex?.trim();
    if (cleanName.isEmpty || cleanHex == null || cleanHex.isEmpty) {
      return;
    }

    await _upsertColor(db, name: cleanName, hex: cleanHex);
  }

  Future<void> _upsertColor(
    DatabaseExecutor db, {
    required String name,
    required String hex,
  }) async {
    final cleanName = name.trim();
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'colors',
      columns: ['id'],
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [cleanName],
      limit: 1,
    );

    if (rows.isEmpty) {
      await db.insert('colors', {
        'name': cleanName,
        'hex': hex,
        'created_at': now,
        'updated_at': now,
      });
      await db.update(
        'variants',
        {'color_hex': hex},
        where: 'color = ? COLLATE NOCASE',
        whereArgs: [cleanName],
      );
      return;
    }

    await db.update(
      'colors',
      {
        'hex': hex,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );

    await db.update(
      'variants',
      {'color_hex': hex},
      where: 'color = ? COLLATE NOCASE',
      whereArgs: [cleanName],
    );
  }

  Future<void> _insertMovement(
    Transaction txn, {
    required int productId,
    required int variantId,
    required String productName,
    required String variantLabel,
    required int quantity,
    required MovementType type,
  }) async {
    if (quantity == 0) {
      return;
    }

    await txn.insert('stock_movements', {
      'product_id': productId,
      'variant_id': variantId,
      'product_name': productName,
      'variant_label': variantLabel,
      'quantity': quantity,
      'type': type.name,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  ProductVariant _variantFromRow(
    Map<String, Object?> row,
    Map<String, String> colorHexByName,
  ) {
    final color = row['color'] as String;

    return ProductVariant(
      id: (row['id'] as int).toString(),
      color: color,
      colorHex:
          row['color_hex'] as String? ?? colorHexByName[colorLookupKey(color)],
      size: row['size'] as String,
      quantity: row['quantity'] as int,
      minimumQuantity: row['minimum_quantity'] as int,
    );
  }

  MovementType _movementType(String value) {
    return MovementType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => MovementType.input,
    );
  }
}
