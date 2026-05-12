import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_preview/device_preview.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import 'data/backup_storage.dart';
import 'data/stock_database.dart';
import 'data/stock_seed.dart';

const defaultProductLocation = 'Stock principal';
const productCategories = <String>['Femme', 'Homme', 'Kids'];

void main() {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(
    kIsWeb && !kReleaseMode
        ? DevicePreview(
            enabled: true,
            builder: (context) => const StockApp(),
          )
        : const StockApp(),
  );
}

class StockApp extends StatelessWidget {
  const StockApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF0F766E);

    return MaterialApp(
      title: 'Stock Boutique',
      locale: kIsWeb && !kReleaseMode ? DevicePreview.locale(context) : null,
      builder: kIsWeb && !kReleaseMode ? DevicePreview.appBuilder : null,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8F7),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Color(0xFFF6F8F7),
          foregroundColor: Color(0xFF10201D),
          elevation: 0,
        ),
        cardTheme: CardTheme(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE0E7E4)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD4DED9)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD4DED9)),
          ),
        ),
        useMaterial3: true,
      ),
      home: const StockHomePage(),
    );
  }
}

class StockHomePage extends StatefulWidget {
  const StockHomePage({super.key});

  @override
  State<StockHomePage> createState() => _StockHomePageState();
}

const _databaseTimeout = Duration(seconds: 5);

class _StockHomePageState extends State<StockHomePage> {
  final StockDatabase _database = StockDatabase.instance;
  List<Product> _products = [];
  List<StockMovement> _movements = [];
  List<String> _categories = [];
  Map<String, String> _colorHexByName = {};
  bool _isLoading = true;
  String? _loadError;
  int _selectedIndex = 0;
  String? _filterType; // 'lowStock', 'outOfStock', or null
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  Future<void> _loadStock() async {
    try {
      // On lance la vérification du backup en arrière-plan
      _runBackupProcedure();

      final products = await _database.getProducts().timeout(_databaseTimeout);
      final movements =
          await _database.getMovements().timeout(_databaseTimeout);
      final categories =
          await _database.getCategories().timeout(_databaseTimeout);
      final colorHexByName =
          await _database.getColors().timeout(_databaseTimeout);

      if (!mounted) {
        return;
      }

      setState(() {
        _products = products;
        _movements = movements;
        _categories = categories;
        _colorHexByName = colorHexByName;
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      if (kIsWeb) {
        // Sur Chrome, on ignore l'erreur de base de données pour permettre
        // de tester l'interface (mode tablette via device_preview)
        final products = _seedProductsForWeb();
        setState(() {
          _products = products;
          _movements = _seedMovementsForWeb(products);
          _categories = _seedCategoriesForWeb();
          _colorHexByName = _seedColorsForWeb(products);
          _isLoading = false;
          _loadError = null;
        });
        return;
      }

      setState(() {
        _isLoading = false;
        _loadError =
            'Impossible de charger la base locale. Relance l\'app ou vérifie l\'installation Flutter.';
      });
    }
  }

  List<Product> _seedProductsForWeb() {
    return [
      for (var productIndex = 0;
          productIndex < stockSeedProducts.length;
          productIndex++)
        Product(
          id: 'web-product-$productIndex',
          name: stockSeedProducts[productIndex].name,
          sku: _seedSkuForWeb(stockSeedProducts[productIndex], productIndex),
          category: stockSeedProducts[productIndex].category,
          brand: '',
          location: 'Stock principal',
          variants: [
            for (var variantIndex = 0;
                variantIndex < stockSeedProducts[productIndex].variants.length;
                variantIndex++)
              ProductVariant(
                id: 'web-variant-$productIndex-$variantIndex',
                color: stockSeedProducts[productIndex]
                    .variants[variantIndex]
                    .color,
                colorHex: null,
                size:
                    stockSeedProducts[productIndex].variants[variantIndex].size,
                quantity: stockSeedProducts[productIndex]
                    .variants[variantIndex]
                    .quantity,
                minimumQuantity: 1,
              ),
          ],
        ),
    ];
  }

  List<String> _seedCategoriesForWeb() {
    return productCategories;
  }

  Map<String, String> _seedColorsForWeb(List<Product> products) {
    return {
      for (final product in products)
        for (final variant in product.variants)
          if (variant.colorHex != null)
            colorLookupKey(variant.color): variant.colorHex!,
    };
  }

  List<StockMovement> _seedMovementsForWeb(List<Product> products) {
    final movements = <StockMovement>[];
    final now = DateTime.now();

    for (final product in products) {
      for (final variant in product.variants) {
        if (variant.quantity <= 0) {
          continue;
        }

        movements.add(
          StockMovement(
            productName: product.name,
            variantLabel: variant.label,
            quantity: variant.quantity,
            type: MovementType.input,
            createdAt: now.subtract(Duration(minutes: movements.length)),
          ),
        );

        if (movements.length >= 100) {
          return movements;
        }
      }
    }

    return movements;
  }

  String _seedSkuForWeb(SeedProductData product, int index) {
    return '${seedSku(product)}-$index';
  }

  // --- GESTION DES BACKUPS ---

  Future<void> _runBackupProcedure() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastBackupMillis = prefs.getInt('last_backup_time') ?? 0;
      final lastBackup = DateTime.fromMillisecondsSinceEpoch(lastBackupMillis);
      final now = DateTime.now();

      // Créneaux prévus : Midi, milieu d'après-midi, fin de journée, fermeture
      final List<int> slots = [12, 15, 18, 21];
      bool shouldBackup = false;

      for (int hour in slots) {
        DateTime slotTime = DateTime(now.year, now.month, now.day, hour);
        // Si on a dépassé l'heure du créneau et que le dernier backup est antérieur à ce créneau
        if (now.isAfter(slotTime) && lastBackup.isBefore(slotTime)) {
          shouldBackup = true;
          break;
        }
      }

      if (shouldBackup) {
        final backupPath = await _executeBackup(now, prefs);
        if (backupPath != null && now.hour >= 18) {
          _showBackupReminder();
        }
      }
    } catch (e) {
      debugPrint('Erreur backup: $e');
    }
  }

  Future<String?> _executeBackup(DateTime now, SharedPreferences prefs) async {
    if (kIsWeb) {
      return null;
    }

    final dbPath = await _database.getDatabasePath();

    // Format : backup_2024-05-22_18h30.db
    final timestamp =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour}h${now.minute.toString().padLeft(2, '0')}";

    final backupPath = await createDatabaseBackup(
      databasePath: dbPath,
      timestamp: timestamp,
    );
    if (backupPath == null) {
      return null;
    }

    await prefs.setInt('last_backup_time', now.millisecondsSinceEpoch);
    return backupPath;
  }

  Future<void> _shareManualBackup() async {
    try {
      final now = DateTime.now();
      final backupPath = await _executeBackup(
        now,
        await SharedPreferences.getInstance(),
      );

      if (!mounted) {
        return;
      }

      if (backupPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sauvegarde indisponible sur cette plateforme.'),
          ),
        );
        return;
      }

      final fileName =
          'stock_boutique_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour}h${now.minute.toString().padLeft(2, '0')}.db';

      await Share.shareXFiles(
        [
          XFile(
            backupPath,
            mimeType: 'application/vnd.sqlite3',
          ),
        ],
        subject: 'Sauvegarde Stock Boutique',
        text:
            'Sauvegarde Stock Boutique du ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}.',
        fileNameOverrides: [fileName],
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur partage sauvegarde : $e')),
      );
    }
  }

  Future<void> _restoreBackupFromFile() async {
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
      );
      final backupPath = selected?.files.single.path;
      if (backupPath == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restaurer la sauvegarde ?'),
          content: const Text(
            'Cette action remplacera le stock actuel par le fichier sélectionné. Une copie de sécurité du stock actuel sera créée avant restauration.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Restaurer'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }

      setState(() {
        _isLoading = true;
        _loadError = null;
      });

      final now = DateTime.now();
      await _executeBackup(now, await SharedPreferences.getInstance());
      final dbPath = await _database.getDatabasePath();
      await _database.close();

      final restored = await restoreDatabaseBackup(
        backupPath: backupPath,
        databasePath: dbPath,
      );

      if (!mounted) {
        return;
      }

      if (!restored) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Restauration impossible : fichier introuvable.'),
          ),
        );
        return;
      }

      await _loadStock();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sauvegarde restaurée.'),
          backgroundColor: Color(0xFF0F766E),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur restauration : $e')),
      );
    }
  }

  void _showBackupReminder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Backup du soir créé. Pensez à partager une sauvegarde.'),
        duration: Duration(seconds: 10),
        backgroundColor: Color(0xFF0F766E),
      ),
    );
  }

  // --- FIN GESTION DES BACKUPS ---

  List<Product> get _filteredProducts {
    List<Product> productsToFilter = _products;

    if (_filterType == 'lowStock') {
      productsToFilter =
          productsToFilter.where((p) => p.lowStockCount > 0).toList();
    } else if (_filterType == 'outOfStock') {
      productsToFilter =
          productsToFilter.where((p) => p.outOfStockCount > 0).toList();
    }

    final normalizedQuery = _query.trim().toLowerCase();

    if (normalizedQuery.isEmpty) {
      return productsToFilter;
    }

    return productsToFilter.where((product) {
      final variantMatch = product.variants.any((variant) {
        return variant.color.toLowerCase().contains(normalizedQuery) ||
            variant.size.toLowerCase().contains(normalizedQuery);
      });

      return (product.name.toLowerCase().contains(normalizedQuery) ||
              product.sku.toLowerCase().contains(normalizedQuery) ||
              product.category.toLowerCase().contains(normalizedQuery) ||
              product.brand.toLowerCase().contains(normalizedQuery) ||
              variantMatch) &&
          (_filterType == null ||
              (_filterType == 'lowStock' && product.lowStockCount > 0) ||
              (_filterType == 'outOfStock' && product.outOfStockCount > 0));
    }).toList();
  }

  int get _totalUnits {
    return _products.fold(0, (total, product) => total + product.totalQuantity);
  }

  int get _lowVariantCount {
    return _products.fold(0, (total, product) => total + product.lowStockCount);
  }

  int get _outOfStockCount {
    return _products.fold(
        0, (total, product) => total + product.outOfStockCount);
  }

  Map<String, int> get _categoryProductCounts {
    final counts = {for (final category in _categories) category: 0};
    for (final product in _products) {
      counts[product.category] = (counts[product.category] ?? 0) + 1;
    }
    return counts;
  }

  void _onFilterSelected(String filterType) {
    setState(() {
      _filterType = filterType;
      _selectedIndex = 1; // Navigate to Products tab
      _query = ''; // Clear any existing text search
    });
  }

  void _onDashboardSearchSubmitted(String value) {
    setState(() {
      _filterType = null;
      _selectedIndex = 1;
      _query = value.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _DashboardView(
        products: _products,
        movements: _movements,
        totalUnits: _totalUnits,
        lowStockCount: _lowVariantCount,
        outOfStockCount: _outOfStockCount,
        onAddProduct: _openProductForm,
        onProductTap: _openProductDetails,
        onVariantStockChanged: _changeStock,
        onFilterSelected: _onFilterSelected,
        onSearchSubmitted: _onDashboardSearchSubmitted,
      ),
      _ProductsView(
        products: _filteredProducts,
        query: _query,
        activeFilterType: _filterType,
        onQueryChanged: (value) => setState(() => _query = value),
        onAddProduct: _openProductForm,
        onProductTap: _openProductDetails,
        onVariantStockChanged: _changeStock,
        onClearFilter: () => setState(() => _filterType = null),
      ),
      _MovementsView(movements: _movements),
      _SettingsView(
        categories: _categories,
        categoryProductCounts: _categoryProductCounts,
        onAddCategory: _addCategory,
        onRenameCategory: _renameCategory,
        onDeleteCategory: _deleteCategory,
        onExportBackup: _shareManualBackup,
        onRestoreBackup: _restoreBackupFromFile,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              _selectedIndex = 0;
              _query = '';
              _filterType = null;
            });
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Stock Boutique',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Ajouter',
            onPressed:
                _loadError == null && !_isLoading ? _openProductForm : null,
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? _LoadErrorView(
                    message: _loadError!,
                    onRetry: () {
                      setState(() => _isLoading = true);
                      _loadStock();
                    },
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: pages[_selectedIndex],
                  ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
            _query = ''; // Clear query when navigating
            _filterType = null; // Clear filter when navigating
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Produits',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_vert_circle_outlined),
            selectedIcon: Icon(Icons.swap_vert_circle),
            label: 'Mouvements',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Reglages',
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 1
          ? FloatingActionButton(
              tooltip: 'Ajouter un produit',
              onPressed: _openProductForm,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Future<void> _openProductForm([Product? product]) async {
    final result = await showModalBottomSheet<ProductFormResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return ProductFormSheet(
          product: product,
          categories: _categories,
          colorHexByName: _colorHexByName,
        );
      },
    );

    if (result == null) {
      return;
    }

    if (kIsWeb) {
      setState(() {
        if (product == null) {
          final newProduct = Product(
            id: 'web-product-${DateTime.now().microsecondsSinceEpoch}',
            name: result.name,
            sku: result.sku,
            category: result.category,
            brand: result.brand,
            location: defaultProductLocation,
            variants: [
              ProductVariant(
                id: 'web-variant-${DateTime.now().microsecondsSinceEpoch}',
                color: result.color,
                colorHex: result.colorHex,
                size: result.size,
                quantity: result.quantity,
                minimumQuantity: result.minimumQuantity,
              ),
            ],
          );
          _products.insert(0, newProduct);
          _addMovementForWeb(
            newProduct,
            newProduct.variants.first,
            result.quantity,
            MovementType.input,
          );
        } else {
          product
            ..name = result.name
            ..sku = result.sku
            ..category = result.category
            ..brand = result.brand;

          if (product.variants.isEmpty) {
            product.variants.add(
              ProductVariant(
                id: 'web-variant-${DateTime.now().microsecondsSinceEpoch}',
                color: result.color,
                colorHex: result.colorHex,
                size: result.size,
                quantity: result.quantity,
                minimumQuantity: result.minimumQuantity,
              ),
            );
          } else {
            product.variants.first
              ..color = result.color
              ..colorHex = result.colorHex
              ..size = result.size
              ..quantity = result.quantity
              ..minimumQuantity = result.minimumQuantity;
          }
        }

        _rememberColor(result.color, result.colorHex);
      });
      return;
    }

    if (product == null) {
      await _database.insertProduct(result);
    } else {
      await _database.updateProduct(product, result);
    }

    await _loadStock();
  }

  Future<void> _openProductDetails(Product product) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void updateVariant(ProductVariant variant, int delta) {
              _changeStock(product, variant, delta);
              setSheetState(() {});
            }

            Future<void> addVariant() async {
              final added = await _openVariantForm(product);
              if (added) {
                setSheetState(() {});
              }
            }

            Future<void> editVariant(ProductVariant variant) async {
              final updated = await _openVariantForm(product, variant);
              if (updated) {
                setSheetState(() {});
              }
            }

            return ProductDetailsSheet(
              product: product,
              onVariantStockChanged: updateVariant,
              onAddVariant: addVariant,
              onEditVariant: editVariant,
              onEdit: () {
                Navigator.of(context).pop();
                _openProductForm(product);
              },
              onDelete: () {
                Navigator.of(context).pop();
                _deleteProduct(product);
              },
            );
          },
        );
      },
    );
  }

  Future<bool> _openVariantForm(Product product,
      [ProductVariant? variant]) async {
    final result = await showModalBottomSheet<VariantFormResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return VariantFormSheet(
          variant: variant,
          colorHexByName: _colorHexByName,
        );
      },
    );

    if (result == null) {
      return false;
    }

    if (kIsWeb && variant != null) {
      setState(() {
        variant
          ..color = result.color
          ..colorHex = result.colorHex
          ..size = result.size
          ..quantity = result.quantity
          ..minimumQuantity = result.minimumQuantity;
        _rememberColor(result.color, result.colorHex);
      });
      return true;
    }

    if (kIsWeb) {
      final variant = ProductVariant(
        id: 'web-variant-${DateTime.now().microsecondsSinceEpoch}',
        color: result.color,
        colorHex: result.colorHex,
        size: result.size,
        quantity: result.quantity,
        minimumQuantity: result.minimumQuantity,
      );

      setState(() {
        product.variants.add(variant);
        _rememberColor(result.color, result.colorHex);
        _addMovementForWeb(
          product,
          variant,
          result.quantity,
          MovementType.input,
        );
      });
      return true;
    }

    if (variant != null) {
      await _database.updateVariant(product, variant, result);
      variant
        ..color = result.color
        ..colorHex = result.colorHex
        ..size = result.size
        ..quantity = result.quantity
        ..minimumQuantity = result.minimumQuantity;
      _rememberColor(result.color, result.colorHex);
      await _loadStock();
      return true;
    }

    final insertedVariant = await _database.insertVariant(product, result);
    setState(() {
      product.variants.add(insertedVariant);
    });
    await _loadStock();

    return true;
  }

  void _rememberColor(String name, String? hex) {
    final cleanHex = _normalizeColorHex(hex);
    if (cleanHex == null) {
      return;
    }
    _colorHexByName = {
      ..._colorHexByName,
      colorLookupKey(name): cleanHex,
    };
    for (final product in _products) {
      for (final variant in product.variants) {
        if (colorLookupKey(variant.color) == colorLookupKey(name)) {
          variant.colorHex = cleanHex;
        }
      }
    }
  }

  Future<void> _changeStock(
    Product product,
    ProductVariant variant,
    int delta,
  ) async {
    if (variant.quantity + delta < 0) {
      return;
    }

    setState(() {
      variant.quantity += delta;
      if (kIsWeb) {
        _addMovementForWeb(
          product,
          variant,
          delta.abs(),
          delta > 0 ? MovementType.input : MovementType.output,
        );
      }
    });

    if (kIsWeb) {
      return;
    }

    await _database.changeStock(product, variant, delta);
    await _loadStock();
  }

  Future<void> _deleteProduct(Product product) async {
    if (kIsWeb) {
      setState(() {
        _products.removeWhere((item) => item.id == product.id);
      });
      return;
    }

    await _database.deleteProduct(product);
    await _loadStock();
  }

  Future<bool> _addCategory(String name) async {
    final cleanName = normalizeProductCategory(name);
    if (cleanName.isEmpty || _categoryExists(cleanName)) {
      return false;
    }

    if (kIsWeb) {
      setState(() {
        _categories = [..._categories, cleanName]..sort();
      });
      return true;
    }

    await _database.insertCategory(cleanName);
    await _loadStock();
    return true;
  }

  Future<bool> _renameCategory(String oldName, String newName) async {
    final cleanName = normalizeProductCategory(newName);
    if (cleanName.isEmpty ||
        (colorLookupKey(oldName) != colorLookupKey(cleanName) &&
            _categoryExists(cleanName))) {
      return false;
    }

    if (kIsWeb) {
      setState(() {
        _categories = _categories
            .map((category) =>
                colorLookupKey(category) == colorLookupKey(oldName)
                    ? cleanName
                    : category)
            .toList()
          ..sort();
        for (final product in _products) {
          if (colorLookupKey(product.category) == colorLookupKey(oldName)) {
            product.category = cleanName;
          }
        }
      });
      return true;
    }

    await _database.renameCategory(oldName, cleanName);
    await _loadStock();
    return true;
  }

  Future<bool> _deleteCategory(String name) async {
    if ((_categoryProductCounts[name] ?? 0) > 0) {
      return false;
    }

    if (kIsWeb) {
      setState(() {
        _categories = _categories
            .where(
              (category) => colorLookupKey(category) != colorLookupKey(name),
            )
            .toList();
      });
      return true;
    }

    final deleted = await _database.deleteCategory(name);
    await _loadStock();
    return deleted;
  }

  bool _categoryExists(String name) {
    return _categories.any(
      (category) => colorLookupKey(category) == colorLookupKey(name),
    );
  }

  void _addMovementForWeb(
    Product product,
    ProductVariant variant,
    int quantity,
    MovementType type,
  ) {
    if (quantity <= 0) {
      return;
    }

    _movements = [
      StockMovement(
        productName: product.name,
        variantLabel: variant.label,
        quantity: quantity,
        type: type,
        createdAt: DateTime.now(),
      ),
      ..._movements,
    ].take(100).toList();
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({
    required this.products,
    required this.movements,
    required this.totalUnits,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.onAddProduct,
    required this.onProductTap,
    required this.onVariantStockChanged,
    required this.onFilterSelected,
    required this.onSearchSubmitted,
  });

  final List<Product> products;
  final List<StockMovement> movements;
  final int totalUnits;
  final int lowStockCount;
  final int outOfStockCount;
  final VoidCallback onAddProduct;
  final ValueChanged<Product> onProductTap;
  final void Function(Product product, ProductVariant variant, int delta)
      onVariantStockChanged; // Not used in _DashboardView, but passed to ProductTile
  final ValueChanged<String> onFilterSelected;
  final ValueChanged<String> onSearchSubmitted;

  @override
  Widget build(BuildContext context) {
    final lowProducts =
        products.where((product) => product.lowStockCount > 0).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Vue du stock',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            FilledButton.icon(
              onPressed: onAddProduct,
              icon: const Icon(Icons.add),
              label: const Text('Produit'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _MetricsGrid(
          metrics: [
            Metric('Modeles', products.length.toString(), Icons.category),
            Metric('Pieces', totalUnits.toString(), Icons.inventory),
            Metric(
              'Variantes bas',
              lowStockCount.toString(),
              Icons.warning_amber,
              onTap: () => onFilterSelected('lowStock'),
            ),
            Metric(
              'Ruptures',
              outOfStockCount.toString(),
              Icons.error_outline,
              onTap: () => onFilterSelected('outOfStock'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          onSubmitted: onSearchSubmitted,
          decoration: const InputDecoration(
            hintText: 'Rechercher un produit...',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 24),
        _SectionHeader(title: 'A surveiller', action: '${lowProducts.length}'),
        const SizedBox(height: 8),
        if (lowProducts.isEmpty)
          const _EmptyState(
            icon: Icons.verified_outlined,
            title: 'Aucune variante critique',
            message: 'Les seuils minimum sont respectes.',
          )
        else
          ...lowProducts.take(4).map(
                (product) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ProductTile(
                    product: product,
                    onTap: () => onProductTap(product),
                    activeFilterType: 'lowStock',
                    onVariantStockChanged: (variant, delta) {
                      onVariantStockChanged(product, variant, delta);
                    },
                  ),
                ),
              ),
        const SizedBox(height: 16),
        const _SectionHeader(title: 'Derniers mouvements'),
        const SizedBox(height: 8),
        if (movements.isEmpty)
          const _EmptyState(
            icon: Icons.swap_vert,
            title: 'Pas encore de mouvement',
            message: 'Les entrees et sorties apparaitront ici.',
          )
        else
          ...movements.take(4).map(
                (movement) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MovementTile(movement: movement),
                ),
              ),
      ],
    );
  }
}

class _ProductsView extends StatelessWidget {
  const _ProductsView({
    required this.products,
    required this.query,
    this.activeFilterType,
    required this.onQueryChanged,
    required this.onAddProduct,
    required this.onProductTap,
    required this.onVariantStockChanged,
    required this.onClearFilter,
  });

  final List<Product> products;
  final String query;
  final String? activeFilterType;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onAddProduct;
  final ValueChanged<Product> onProductTap;
  final void Function(Product product, ProductVariant variant, int delta)
      onVariantStockChanged;
  final VoidCallback onClearFilter;

  String get _hintText {
    if (activeFilterType == 'lowStock') {
      return 'Rechercher dans les variantes bas...';
    } else if (activeFilterType == 'outOfStock') {
      return 'Rechercher dans les ruptures...';
    }
    return 'Rechercher modele, SKU, taille, couleur';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              onChanged: onQueryChanged,
              decoration: InputDecoration(
                hintText: _hintText,
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (activeFilterType != null) ...[
              const SizedBox(height: 12),
              Wrap(
                children: [
                  InputChip(
                    label: Text(
                      activeFilterType == 'outOfStock'
                          ? 'Filtre : Ruptures'
                          : 'Filtre : Stock Bas',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onDeleted: onClearFilter,
                    deleteIconColor: Colors.white,
                    backgroundColor: activeFilterType == 'outOfStock'
                        ? Colors.red.shade700
                        : Colors.orange.shade800,
                    labelStyle: const TextStyle(color: Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _SectionHeader(title: 'Produits', action: products.length.toString()),
        const SizedBox(height: 8),
        if (products.isEmpty)
          _EmptyState(
            icon: Icons.inventory_2_outlined,
            title: query.isEmpty ? 'Aucun produit' : 'Aucun resultat',
            message: query.isEmpty
                ? 'Ajoute ton premier modele et sa premiere variante.'
                : 'Essaie avec un autre nom, SKU, taille ou couleur.',
            actionLabel: query.isEmpty ? 'Ajouter' : null,
            onActionPressed: query.isEmpty ? onAddProduct : null,
          )
        else
          ...products.map(
            (product) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ProductTile(
                product: product,
                activeFilterType: activeFilterType,
                onTap: () => onProductTap(product),
                onVariantStockChanged: (variant, delta) {
                  onVariantStockChanged(product, variant, delta);
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _MovementsView extends StatelessWidget {
  const _MovementsView({required this.movements});

  final List<StockMovement> movements;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Mouvements',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 16),
        if (movements.isEmpty)
          const _EmptyState(
            icon: Icons.swap_vert,
            title: 'Historique vide',
            message: 'Ajoute ou retire du stock pour creer une trace.',
          )
        else
          ...movements.map(
            (movement) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MovementTile(movement: movement),
            ),
          ),
      ],
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({
    required this.categories,
    required this.categoryProductCounts,
    required this.onAddCategory,
    required this.onRenameCategory,
    required this.onDeleteCategory,
    required this.onExportBackup,
    required this.onRestoreBackup,
  });
  final List<String> categories;
  final Map<String, int> categoryProductCounts;
  final Future<bool> Function(String name) onAddCategory;
  final Future<bool> Function(String oldName, String newName) onRenameCategory;
  final Future<bool> Function(String name) onDeleteCategory;
  final VoidCallback onExportBackup;
  final VoidCallback onRestoreBackup;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Reglages',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        const _InfoCard(
          icon: Icons.storage_outlined,
          title: 'Sauvegardes automatiques',
          message:
              '4 points de restauration par jour sont conservés sur 7 jours.',
        ),
        const SizedBox(height: 8),
        _InfoCard(
          icon: Icons.storefront_outlined,
          title: 'Stock Boutique',
          message:
              'Le stock est maintenant prepare pour les tailles, couleurs et collections.',
        ),
        const SizedBox(height: 24),
        _CategoryManagementSection(
          categories: categories,
          categoryProductCounts: categoryProductCounts,
          onAddCategory: onAddCategory,
          onRenameCategory: onRenameCategory,
          onDeleteCategory: onDeleteCategory,
        ),
        const SizedBox(height: 24),
        const _SectionHeader(title: 'Sécurité'),
        const SizedBox(height: 8),
        ListTile(
          tileColor: Colors.white,
          leading: const Icon(Icons.ios_share, color: Colors.blue),
          title: const Text('Partager une sauvegarde'),
          subtitle:
              const Text('Envoie la BDD vers un mobile ou une autre appli.'),
          onTap: onExportBackup,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        const SizedBox(height: 8),
        ListTile(
          tileColor: Colors.white,
          leading: const Icon(Icons.restore, color: Color(0xFF0F766E)),
          title: const Text('Restaurer une sauvegarde'),
          subtitle: const Text('Remplace le stock actuel par un fichier .db.'),
          onTap: onRestoreBackup,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        const SizedBox(height: 8),
        ListTile(
          tileColor: Colors.white,
          leading: const Icon(Icons.power_settings_new, color: Colors.red),
          title: const Text("Fermer l'application"),
          subtitle: const Text(
              "Quitte l'application et revient à l'accueil Android."),
          onTap: SystemNavigator.pop,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ],
    );
  }
}

class _CategoryManagementSection extends StatelessWidget {
  const _CategoryManagementSection({
    required this.categories,
    required this.categoryProductCounts,
    required this.onAddCategory,
    required this.onRenameCategory,
    required this.onDeleteCategory,
  });

  final List<String> categories;
  final Map<String, int> categoryProductCounts;
  final Future<bool> Function(String name) onAddCategory;
  final Future<bool> Function(String oldName, String newName) onRenameCategory;
  final Future<bool> Function(String name) onDeleteCategory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Catégories',
          actionWidget: IconButton.filledTonal(
            tooltip: 'Ajouter une catégorie',
            onPressed: () => _showCategoryDialog(context),
            icon: const Icon(Icons.add),
          ),
        ),
        const SizedBox(height: 8),
        if (categories.isEmpty)
          _EmptyState(
            icon: Icons.category_outlined,
            title: 'Aucune catégorie',
            message: 'Ajoute au moins une catégorie pour créer des produits.',
            actionLabel: 'Ajouter',
            onActionPressed: () => _showCategoryDialog(context),
          )
        else
          ...categories.map(
            (category) {
              final productCount = categoryProductCounts[category] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  tileColor: Colors.white,
                  leading: const Icon(
                    Icons.category_outlined,
                    color: Color(0xFF0F766E),
                  ),
                  title: Text(category),
                  subtitle: Text(
                    productCount == 0
                        ? 'Aucun produit'
                        : '$productCount produit(s)',
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Modifier',
                        onPressed: () =>
                            _showCategoryDialog(context, category: category),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        onPressed: productCount == 0
                            ? () => _confirmDelete(context, category)
                            : null,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _showCategoryDialog(
    BuildContext context, {
    String? category,
  }) async {
    final isEditing = category != null;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _CategoryDialog(
        initialName: category ?? '',
        isEditing: isEditing,
      ),
    );

    final cleanName = normalizeProductCategory(result ?? '');
    if (cleanName.isEmpty) {
      return;
    }

    final success = isEditing
        ? await onRenameCategory(category, cleanName)
        : await onAddCategory(cleanName);
    if (!context.mounted) {
      return;
    }
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catégorie déjà existante ou invalide.')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, String category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la catégorie ?'),
        content: Text('La catégorie "$category" sera supprimée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final success = await onDeleteCategory(category);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Catégorie supprimée.'
              : 'Impossible de supprimer une catégorie utilisée.',
        ),
      ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.initialName,
    required this.isEditing,
  });

  final String initialName;
  final bool isEditing;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isEditing ? 'Modifier la catégorie' : 'Nouvelle catégorie',
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Nom'),
        onSubmitted: _submit,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => _submit(_controller.text),
          child: Text(widget.isEditing ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }

  void _submit(String value) {
    Navigator.of(context).pop(value);
  }
}

class _LoadErrorView extends StatelessWidget {
  const _LoadErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.storage_outlined,
                    size: 44,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Base locale indisponible',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reessayer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.onTap,
    required this.onVariantStockChanged,
    this.activeFilterType,
  });

  final Product product;
  final VoidCallback onTap;
  final void Function(ProductVariant variant, int delta) onVariantStockChanged;
  final String? activeFilterType;

  @override
  Widget build(BuildContext context) {
    final status = StockStatus.fromProduct(product);

    // Filtrage intelligent des variantes affichées sur la carte
    List<ProductVariant> visibleVariants;
    if (activeFilterType == 'outOfStock') {
      visibleVariants =
          product.variants.where((v) => v.quantity == 0).take(3).toList();
    } else if (activeFilterType == 'lowStock') {
      visibleVariants =
          product.variants.where((v) => v.isLowStock).take(3).toList();
    } else {
      visibleVariants = product.variants.take(3).toList();
    }

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: status.color.withValues(alpha: 0.12),
                    foregroundColor: status.color,
                    child: Icon(status.icon),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${product.sku} · Categorie:${product.category}${product.brand.isNotEmpty && product.brand.toLowerCase() != 'reassort' ? ' · ${product.brand}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        product.totalQuantity.toString(),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(
                        status.label,
                        style: TextStyle(
                          color: status.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...visibleVariants.map(
                (variant) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: VariantStockRow(
                    variant: variant,
                    compact: true,
                    onAdd: () => onVariantStockChanged(variant, 1),
                    onRemove: variant.quantity == 0
                        ? null
                        : () => onVariantStockChanged(variant, -1),
                  ),
                ),
              ),
              if (product.variants.length > visibleVariants.length)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '+ ${product.variants.length - visibleVariants.length} variante(s)',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class VariantStockRow extends StatelessWidget {
  const VariantStockRow({
    super.key,
    required this.variant,
    required this.onAdd,
    required this.onRemove,
    this.onEdit,
    this.compact = false,
  });

  final ProductVariant variant;
  final VoidCallback onAdd;
  final VoidCallback? onRemove;
  final VoidCallback? onEdit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final status = StockStatus.fromVariant(variant);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E7E4)),
      ),
      child: Row(
        children: [
          _ColorDot(label: variant.color, colorHex: variant.colorHex),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${variant.color} / ${variant.size}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (!compact)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                status.label,
                style: TextStyle(
                  color: status.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (!compact && onEdit != null)
            IconButton(
              tooltip: 'Modifier la variante',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          _StockStepper(
            quantity: variant.quantity,
            onAdd: onAdd,
            onRemove: onRemove,
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.label, this.colorHex});

  final String label;
  final String? colorHex;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: _colorFromHex(colorHex) ?? _colorFromName(label),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFCAD8D2)),
      ),
    );
  }
}

class _StockStepper extends StatelessWidget {
  const _StockStepper({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Quantite en stock',
      value: quantity.toString(),
      child: Container(
        constraints: const BoxConstraints(minWidth: 116),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD4DED9)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Retirer un article',
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 34,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: Text(
                  quantity.toString(),
                  key: ValueKey(quantity),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Ajouter un article',
              visualDensity: VisualDensity.compact,
              onPressed: onAdd,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

class NumberStepperFormField extends StatefulWidget {
  const NumberStepperFormField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;

  @override
  State<NumberStepperFormField> createState() => _NumberStepperFormFieldState();
}

class _NumberStepperFormFieldState extends State<NumberStepperFormField> {
  void _changeBy(int delta) {
    final currentValue = int.tryParse(widget.controller.text) ?? 0;
    final nextValue = currentValue + delta;

    if (nextValue < 0) {
      return;
    }

    widget.controller.text = nextValue.toString();
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(widget.controller.text) ?? 0;

    return TextFormField(
      controller: widget.controller,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: widget.validator,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: IconButton(
          tooltip: 'Diminuer',
          onPressed: value == 0 ? null : () => _changeBy(-1),
          icon: const Icon(Icons.remove),
        ),
        suffixIcon: IconButton(
          tooltip: 'Augmenter',
          onPressed: () => _changeBy(1),
          icon: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.movement});

  final StockMovement movement;

  @override
  Widget build(BuildContext context) {
    final isInput = movement.type == MovementType.input;
    final color = isInput ? const Color(0xFF0F766E) : const Color(0xFFB45309);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          child: Icon(isInput ? Icons.arrow_downward : Icons.arrow_upward),
        ),
        title: Text(
          movement.productName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
            '${movement.variantLabel} · ${_formatDate(movement.createdAt)}'),
        trailing: Text(
          '${isInput ? '+' : '-'}${movement.quantity}',
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class ProductDetailsSheet extends StatelessWidget {
  const ProductDetailsSheet({
    super.key,
    required this.product,
    required this.onVariantStockChanged,
    required this.onAddVariant,
    required this.onEditVariant,
    required this.onEdit,
    required this.onDelete,
  });

  final Product product;
  final void Function(ProductVariant variant, int delta) onVariantStockChanged;
  final VoidCallback onAddVariant;
  final ValueChanged<ProductVariant> onEditVariant;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final status = StockStatus.fromProduct(product);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text('${product.sku} · ${product.category} · ${product.brand}'),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Pieces disponibles'),
                          Text(
                            product.totalQuantity.toString(),
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            '${product.variants.length} variante(s) · ${product.location}',
                          ),
                        ],
                      ),
                    ),
                    Chip(
                      avatar: Icon(status.icon, color: status.color, size: 18),
                      label: Text(status.label),
                      side: BorderSide(
                          color: status.color.withValues(alpha: 0.35)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Variantes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: onAddVariant,
                  icon: const Icon(Icons.add),
                  label: const Text('Variante'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...product.variants.map(
              (variant) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: VariantStockRow(
                  variant: variant,
                  onAdd: () => onVariantStockChanged(variant, 1),
                  onRemove: variant.quantity == 0
                      ? null
                      : () => onVariantStockChanged(variant, -1),
                  onEdit: () => onEditVariant(variant),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Supprimer',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class ProductFormSheet extends StatefulWidget {
  const ProductFormSheet({
    super.key,
    this.product,
    required this.categories,
    required this.colorHexByName,
  });

  final Product? product;
  final List<String> categories;
  final Map<String, String> colorHexByName;

  @override
  State<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _brandController;
  late final TextEditingController _colorController;
  late final TextEditingController _colorHexController;
  late final TextEditingController _sizeController;
  late final TextEditingController _quantityController;
  late final TextEditingController _minimumController;
  String? _selectedCategory;
  bool _colorHexFromName = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    final variant = product?.variants.firstOrNull;

    _nameController = TextEditingController(text: product?.name ?? '');
    _skuController = TextEditingController(text: product?.sku ?? '');
    _brandController = TextEditingController(text: product?.brand ?? '');
    _colorController = TextEditingController(text: variant?.color ?? '');
    final colorHexFromName = _colorHexForName(variant?.color ?? '');
    _colorHexFromName = variant?.colorHex == null && colorHexFromName != null;
    _colorHexController = TextEditingController(
      text: variant?.colorHex ?? colorHexFromName ?? '',
    );
    _sizeController = TextEditingController(text: variant?.size ?? '');
    _quantityController =
        TextEditingController(text: '${variant?.quantity ?? 0}');
    _minimumController =
        TextEditingController(text: '${variant?.minimumQuantity ?? 1}');
    _selectedCategory = product?.category ??
        (widget.categories.isNotEmpty ? widget.categories.first : null);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _brandController.dispose();
    _colorController.dispose();
    _colorHexController.dispose();
    _sizeController.dispose();
    _quantityController.dispose();
    _minimumController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.product != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEditing ? 'Modifier le modele' : 'Nouveau modele',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nom du modele'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _skuController,
                decoration: const InputDecoration(labelText: 'Reference / SKU'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: const InputDecoration(labelText: 'Categorie'),
                      items: widget.categories.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedCategory = value);
                      },
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Champ obligatoire';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _brandController,
                      decoration: const InputDecoration(labelText: 'Marque'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isEditing ? 'Premiere variante' : 'Variante initiale',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _colorController,
                      decoration: const InputDecoration(labelText: 'Couleur'),
                      validator: _required,
                      onChanged: _onColorNameChanged,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sizeController,
                      decoration: const InputDecoration(labelText: 'Taille'),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ColorPickerField(
                label: _colorController.text,
                colorHex: _colorHexController.text,
                onPickColor: _pickColor,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: NumberStepperFormField(
                      controller: _quantityController,
                      label: 'Quantite',
                      validator: _positiveNumber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NumberStepperFormField(
                      controller: _minimumController,
                      label: 'Minimum',
                      validator: _positiveNumber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon: Icon(isEditing ? Icons.check : Icons.add),
                  label: Text(isEditing ? 'Enregistrer' : 'Ajouter'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Champ obligatoire';
    }
    return null;
  }

  String? _positiveNumber(String? value) {
    final number = int.tryParse(value ?? '');
    if (number == null || number < 0) {
      return 'Nombre invalide';
    }
    return null;
  }

  void _onColorNameChanged(String value) {
    final knownHex = _colorHexForName(value);
    setState(() {
      if (knownHex != null) {
        _colorHexController.text = knownHex;
        _colorHexFromName = true;
      } else if (_colorHexFromName) {
        _colorHexController.clear();
        _colorHexFromName = false;
      }
    });
  }

  String? _colorHexForName(String name) {
    return widget.colorHexByName[colorLookupKey(name)];
  }

  Future<void> _pickColor() async {
    final colorHex = await _showColorPicker(
      context,
      currentHex: _colorHexController.text,
      onColorChanged: _setPickedColor,
    );
    if (colorHex == null) {
      return;
    }
    _setPickedColor(colorHex);
  }

  void _setPickedColor(String colorHex) {
    if (!mounted) {
      return;
    }
    final normalizedHex = _normalizeColorHex(colorHex) ?? '';
    setState(() {
      _colorHexController.text = normalizedHex;
      _colorHexFromName = false;
      final currentColorText = _colorController.text.trim();
      if (normalizedHex.isNotEmpty &&
          (currentColorText.isEmpty ||
              _normalizeColorHex(currentColorText) != null)) {
        _colorController.text = normalizedHex;
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    String brand = _brandController.text.trim();
    // On vide le champ si l'utilisateur a saisi "réassort" par habitude
    if (brand.toLowerCase() == 'reassort' ||
        brand.toLowerCase() == 'réassort') {
      brand = '';
    }

    Navigator.of(context).pop(
      ProductFormResult(
        name: _nameController.text.trim(),
        sku: _skuController.text.trim(),
        category: _selectedCategory!.trim(),
        brand: brand,
        color: _colorController.text.trim(),
        colorHex: _normalizeColorHex(_colorHexController.text),
        size: _sizeController.text.trim(),
        quantity: int.parse(_quantityController.text),
        minimumQuantity: int.parse(_minimumController.text),
      ),
    );
  }
}

class VariantFormSheet extends StatefulWidget {
  const VariantFormSheet({
    super.key,
    this.variant,
    required this.colorHexByName,
  });

  final ProductVariant? variant;
  final Map<String, String> colorHexByName;

  @override
  State<VariantFormSheet> createState() => _VariantFormSheetState();
}

class _VariantFormSheetState extends State<VariantFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _colorController;
  late final TextEditingController _colorHexController;
  late final TextEditingController _sizeController;
  late final TextEditingController _quantityController;
  late final TextEditingController _minimumController;
  bool _colorHexFromName = false;

  @override
  void initState() {
    super.initState();
    final variant = widget.variant;
    final colorHexFromName = _colorHexForName(variant?.color ?? '');
    _colorHexFromName = variant?.colorHex == null && colorHexFromName != null;
    _colorController = TextEditingController(text: variant?.color ?? '');
    _colorHexController = TextEditingController(
      text: variant?.colorHex ?? colorHexFromName ?? '',
    );
    _sizeController = TextEditingController(text: variant?.size ?? '');
    _quantityController =
        TextEditingController(text: '${variant?.quantity ?? 0}');
    _minimumController =
        TextEditingController(text: '${variant?.minimumQuantity ?? 1}');
  }

  @override
  void dispose() {
    _colorController.dispose();
    _colorHexController.dispose();
    _sizeController.dispose();
    _quantityController.dispose();
    _minimumController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.variant != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEditing ? 'Modifier la variante' : 'Nouvelle variante',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _colorController,
                      decoration: const InputDecoration(labelText: 'Couleur'),
                      validator: _required,
                      onChanged: _onColorNameChanged,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sizeController,
                      decoration: const InputDecoration(labelText: 'Taille'),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ColorPickerField(
                label: _colorController.text,
                colorHex: _colorHexController.text,
                onPickColor: _pickColor,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: NumberStepperFormField(
                      controller: _quantityController,
                      label: 'Quantite',
                      validator: _positiveNumber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NumberStepperFormField(
                      controller: _minimumController,
                      label: 'Minimum',
                      validator: _positiveNumber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon: Icon(isEditing ? Icons.check : Icons.add),
                  label: Text(isEditing ? 'Enregistrer' : 'Ajouter'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Champ obligatoire';
    }
    return null;
  }

  String? _positiveNumber(String? value) {
    final number = int.tryParse(value ?? '');
    if (number == null || number < 0) {
      return 'Nombre invalide';
    }
    return null;
  }

  void _onColorNameChanged(String value) {
    final knownHex = _colorHexForName(value);
    setState(() {
      if (knownHex != null) {
        _colorHexController.text = knownHex;
        _colorHexFromName = true;
      } else if (_colorHexFromName) {
        _colorHexController.clear();
        _colorHexFromName = false;
      }
    });
  }

  String? _colorHexForName(String name) {
    return widget.colorHexByName[colorLookupKey(name)];
  }

  Future<void> _pickColor() async {
    final colorHex = await _showColorPicker(
      context,
      currentHex: _colorHexController.text,
      onColorChanged: _setPickedColor,
    );
    if (colorHex == null) {
      return;
    }
    _setPickedColor(colorHex);
  }

  void _setPickedColor(String colorHex) {
    if (!mounted) {
      return;
    }
    final normalizedHex = _normalizeColorHex(colorHex) ?? '';
    setState(() {
      _colorHexController.text = normalizedHex;
      _colorHexFromName = false;
      final currentColorText = _colorController.text.trim();
      if (normalizedHex.isNotEmpty &&
          (currentColorText.isEmpty ||
              _normalizeColorHex(currentColorText) != null)) {
        _colorController.text = normalizedHex;
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      VariantFormResult(
        color: _colorController.text.trim(),
        colorHex: _normalizeColorHex(_colorHexController.text),
        size: _sizeController.text.trim(),
        quantity: int.parse(_quantityController.text),
        minimumQuantity: int.parse(_minimumController.text),
      ),
    );
  }
}

class _ColorPickerField extends StatelessWidget {
  const _ColorPickerField({
    required this.label,
    required this.colorHex,
    required this.onPickColor,
  });

  final String label;
  final String colorHex;
  final VoidCallback onPickColor;

  @override
  Widget build(BuildContext context) {
    final normalizedHex = _normalizeColorHex(colorHex);
    final displayText = normalizedHex ?? 'Choisir une couleur';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onPickColor,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Couleur visuelle',
          suffixIcon: Icon(Icons.palette_outlined),
        ),
        child: Row(
          children: [
            _ColorDot(label: label, colorHex: normalizedHex),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _showColorPicker(
  BuildContext context, {
  required String currentHex,
  required ValueChanged<String> onColorChanged,
}) {
  final initialColor = _colorFromHex(currentHex) ?? const Color(0xFF3AA6B9);
  Color pickedColor = initialColor;

  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final colorHex = _hexFromColor(pickedColor);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choisir une couleur',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  ColorPicker(
                    pickerColor: pickedColor,
                    onColorChanged: (color) {
                      final colorHex = _hexFromColor(color);
                      onColorChanged(colorHex);
                      setModalState(() => pickedColor = color);
                    },
                    enableAlpha: false,
                    displayThumbColor: true,
                    pickerAreaHeightPercent: 0.65,
                    labelTypes: const [],
                    portraitOnly: true,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _ColorDot(label: '', colorHex: colorHex),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          colorHex,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            onColorChanged('');
                            Navigator.of(context).pop('');
                          },
                          icon: const Icon(Icons.close),
                          label: const Text('Aucune'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop(colorHex),
                          icon: const Icon(Icons.check),
                          label: const Text('Valider'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics});

  final List<Metric> metrics;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;

    return GridView.builder(
      itemCount: metrics.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 4 : 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: isTablet ? 1.65 : 1.45,
      ),
      itemBuilder: (context, index) {
        final metric = metrics[index];

        return Card(
          child: Padding(
            padding: EdgeInsets.zero,
            child: InkWell(
              onTap: metric.onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      metric.icon,
                      size: 22,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      metric.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      metric.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.actionWidget});

  final String title;
  final String? action;
  final Widget? actionWidget;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        if (actionWidget != null)
          actionWidget!
        else if (action != null)
          Text(
            action!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onActionPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onActionPressed,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(message),
      ),
    );
  }
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.category,
    required this.brand,
    required this.location,
    required this.variants,
  });

  final String id;
  String name;
  String sku;
  String category;
  String brand;
  String location;
  final List<ProductVariant> variants;

  int get totalQuantity {
    return variants.fold(0, (total, variant) => total + variant.quantity);
  }

  int get lowStockCount {
    return variants.where((variant) => variant.isLowStock).length;
  }

  int get outOfStockCount {
    return variants.where((variant) => variant.quantity == 0).length;
  }
}

class ProductVariant {
  ProductVariant({
    required this.id,
    required this.color,
    this.colorHex,
    required this.size,
    required this.quantity,
    required this.minimumQuantity,
  });

  final String id;
  String color;
  String? colorHex;
  String size;
  int quantity;
  int minimumQuantity;

  bool get isLowStock {
    return quantity > 0 && quantity <= minimumQuantity;
  }

  String get label {
    return '$color / $size';
  }
}

class ProductFormResult {
  const ProductFormResult({
    required this.name,
    required this.sku,
    required this.category,
    required this.brand,
    required this.color,
    this.colorHex,
    required this.size,
    required this.quantity,
    required this.minimumQuantity,
  });

  final String name;
  final String sku;
  final String category;
  final String brand;
  final String color;
  final String? colorHex;
  final String size;
  final int quantity;
  final int minimumQuantity;
}

class VariantFormResult {
  const VariantFormResult({
    required this.color,
    this.colorHex,
    required this.size,
    required this.quantity,
    required this.minimumQuantity,
  });

  final String color;
  final String? colorHex;
  final String size;
  final int quantity;
  final int minimumQuantity;
}

class StockMovement {
  const StockMovement({
    required this.productName,
    required this.variantLabel,
    required this.quantity,
    required this.type,
    required this.createdAt,
  });

  final String productName;
  final String variantLabel;
  final int quantity;
  final MovementType type;
  final DateTime createdAt;
}

class Metric {
  const Metric(this.label, this.value, this.icon, {this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
}

class StockStatus {
  const StockStatus({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  factory StockStatus.fromProduct(Product product) {
    if (product.totalQuantity == 0) {
      return const StockStatus(
        label: 'Rupture',
        color: Color(0xFFB91C1C),
        icon: Icons.error_outline,
      );
    }

    if (product.lowStockCount > 0) {
      return const StockStatus(
        label: 'A surveiller',
        color: Color(0xFFB45309),
        icon: Icons.warning_amber,
      );
    }

    return const StockStatus(
      label: 'OK',
      color: Color(0xFF0F766E),
      icon: Icons.check_circle_outline,
    );
  }

  factory StockStatus.fromVariant(ProductVariant variant) {
    if (variant.quantity == 0) {
      return const StockStatus(
        label: 'Rupture',
        color: Color(0xFFB91C1C),
        icon: Icons.error_outline,
      );
    }

    if (variant.isLowStock) {
      return const StockStatus(
        label: 'Bas',
        color: Color(0xFFB45309),
        icon: Icons.warning_amber,
      );
    }

    return const StockStatus(
      label: 'OK',
      color: Color(0xFF0F766E),
      icon: Icons.check_circle_outline,
    );
  }
}

enum MovementType { input, output }

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');

  return '$day/$month/${date.year} a $hour:$minute';
}

Color _colorFromName(String label) {
  final normalized = label.trim().toLowerCase();

  if (normalized.contains('bleu') || normalized.contains('marine')) {
    return const Color(0xFF2563EB);
  }
  if (normalized.contains('blanc')) {
    return Colors.white;
  }
  if (normalized.contains('corail')) {
    return const Color(0xFFF97362);
  }
  if (normalized.contains('sable') || normalized.contains('beige')) {
    return const Color(0xFFD8C29D);
  }
  if (normalized.contains('noir')) {
    return const Color(0xFF111827);
  }
  if (normalized.contains('rouge')) {
    return const Color(0xFFDC2626);
  }
  if (normalized.contains('vert')) {
    return const Color(0xFF16A34A);
  }

  return const Color(0xFF94A3B8);
}

String? _normalizeColorHex(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final withoutHash = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(withoutHash)) {
    return null;
  }

  return '#${withoutHash.toUpperCase()}';
}

String colorLookupKey(String value) {
  return value.trim().toLowerCase();
}

String seedSku(SeedProductData product) {
  final prefix = product.category.substring(0, 1).toUpperCase();
  final normalizedName = product.name
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  final cleanName = product.category.toLowerCase() == 'kids'
      ? normalizedName.replaceFirst(RegExp(r'-KID$'), '')
      : normalizedName;

  return '$prefix-$cleanName';
}

String normalizeProductCategory(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  final normalized = trimmed.toLowerCase();
  for (final category in productCategories) {
    if (category.toLowerCase() == normalized) {
      return category;
    }
  }

  return trimmed;
}

Color? _colorFromHex(String? value) {
  final normalized = _normalizeColorHex(value);
  if (normalized == null) {
    return null;
  }

  return Color(int.parse('FF${normalized.substring(1)}', radix: 16));
}

String _hexFromColor(Color color) {
  final red = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
  final green = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
  final blue = (color.b * 255).round().toRadixString(16).padLeft(2, '0');

  return '#${red.toUpperCase()}${green.toUpperCase()}${blue.toUpperCase()}';
}
