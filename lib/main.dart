import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pdf_text_shaper/pdf_text_shaper.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'ui_translation.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UiTranslation.load();
  await AppData.instance.load();
  runApp(const MyApp());
}

// Keep all user-facing dates consistent across the POS.
String _formatDateOnly(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

// Safely read dates from JSON backups. Stored ISO timestamps remain unchanged.
DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return DateTime.tryParse(value.toString());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'POS System',
      theme: ThemeData(
        // Keep Burmese/Myanmar glyphs available throughout the Flutter UI while
        // still allowing Latin text and numbers to render normally. The first
        // family is preferred when installed/bundled by the platform.
        fontFamily: 'Noto Sans Myanmar', // Bundled in assets/fonts/ for deterministic Myanmar rendering.

        fontFamilyFallback: const [
          'Pyidaungsu',
          'Padauk',
          'Myanmar Text',
          'Noto Sans',
          'sans-serif',
        ],
      ),
      home: const PosDashboardScreen(),
    );
  }
}

// =====================================================================
// DATA MODELS
// =====================================================================

class Product {
  Product({
    this.id = '',
    required this.name,
    this.type = '',
    this.subType = '',
    this.measurement = '',
    this.incomingUnit = 'unit',
    this.saleUnit = 'unit',
    this.stock = 0,
    this.sellingPrice1 = 0,
    this.sellingPrice2 = 0,
    this.sellingPrice3 = 0,
    this.cost = 0,
    this.supplier = '',
    this.lastIncomingDate,
    this.subtractFromParentStock = false,
    this.parentProductId = '',
    this.incomingStockUnitsPerInput = 1,
    this.saleStockUnitsPerUnit = 1,
    this.saleConsumptionMode = 'fixed',
  });

  String id;
  String name;
  String type;
  String subType;

  /// Unit of the physical stock held by this product.
  /// LPG inventory is stored in `kg`.
  String measurement;

  /// What the user counts when receiving this product.
  /// LPG stock is received in kilograms only, so LPG uses `kg`.
  String incomingUnit;

  /// What the user counts when selling this product.
  /// Example: `kg`, `220g`, `viss`, or `unit`.
  String saleUnit;

  /// Stock quantity stored in this product's stock unit.
  double stock;

  double sellingPrice1;
  double sellingPrice2;
  double sellingPrice3;

  /// Cost used by the sales engine for one direct sale unit.
  /// For LPG main stock, this is the latest cost of the direct sale unit.
  double cost;

  String supplier;
  DateTime? lastIncomingDate;

  /// When true, this product is a selling variant whose physical stock comes
  /// from another product instead of having its own independent stock.
  bool subtractFromParentStock;
  String parentProductId;

  /// How many stock units are added by one incoming input.
  /// LPG uses kg input, so this is `1` for LPG.
  double incomingStockUnitsPerInput;

  /// For fixed-conversion sales, how many parent stock units are consumed by
  /// one sale unit. Example: 220g LPG consumes 0.22kg of parent stock.
  double saleStockUnitsPerUnit;

  /// `fixed` or `kg_or_viss`.
  /// `kg_or_viss` is used for products such as loose LPG where the customer
  /// may buy by kg or viss at the time of sale.
  String saleConsumptionMode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'subType': subType,
        'measurement': measurement,
        'incomingUnit': incomingUnit,
        'saleUnit': saleUnit,
        'stock': stock,
        'sellingPrice1': sellingPrice1,
        'sellingPrice2': sellingPrice2,
        'sellingPrice3': sellingPrice3,
        'cost': cost,
        'supplier': supplier,
        'lastIncomingDate': lastIncomingDate?.toIso8601String(),
        'subtractFromParentStock': subtractFromParentStock,
        'parentProductId': parentProductId,
        'incomingStockUnitsPerInput': incomingStockUnitsPerInput,
        'saleStockUnitsPerUnit': saleStockUnitsPerUnit,
        'saleConsumptionMode': saleConsumptionMode,
      };

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String? ?? AppData.newId(),
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? '',
        subType: j['subType'] as String? ?? '',
        measurement: j['measurement'] as String? ?? '',
        incomingUnit: j['incomingUnit'] as String? ??
            (j['measurement'] as String? ?? 'unit'),
        saleUnit: j['saleUnit'] as String? ??
            (j['subType'] as String? ?? 'unit'),
        stock: (j['stock'] as num?)?.toDouble() ?? 0,
        sellingPrice1: (j['sellingPrice1'] as num?)?.toDouble() ?? 0,
        sellingPrice2: (j['sellingPrice2'] as num?)?.toDouble() ?? 0,
        sellingPrice3: (j['sellingPrice3'] as num?)?.toDouble() ?? 0,
        cost: (j['cost'] as num?)?.toDouble() ?? 0,
        supplier: j['supplier'] as String? ?? '',
        lastIncomingDate: _parseDateTime(j['lastIncomingDate']),
        subtractFromParentStock: j['subtractFromParentStock'] as bool? ?? false,
        parentProductId: j['parentProductId'] as String? ?? '',
        incomingStockUnitsPerInput:
            (j['incomingStockUnitsPerInput'] as num?)?.toDouble() ?? 1,
        saleStockUnitsPerUnit:
            (j['saleStockUnitsPerUnit'] as num?)?.toDouble() ?? 1,
        saleConsumptionMode: j['saleConsumptionMode'] as String? ?? 'fixed',
      );
}

class Person {
  Person({
    required this.name,
    required this.category,
    this.phone = '',
    this.address = '',
  });

  String name;
  String category; // 'Supplier' or 'Customer'
  String phone;
  String address;

  String get type => '';

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category,
        'phone': phone,
        'address': address,
      };

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        name: j['name'] as String? ?? '',
        category: j['category'] as String? ?? 'Customer',
        phone: j['phone'] as String? ?? '',
        address: j['address'] as String? ?? '',
      );
}

class SaleItem {
  SaleItem({
    required this.saleVoucherNumber,
    required this.product,
    this.productId = '',
    required this.quantity,
    required this.sellingPrice,
    this.profit = 0,
    this.saleUnit = '',
    this.inventoryProductId = '',
    this.stockDeduction = 0,
  });

  String saleVoucherNumber;
  String product;

  /// Product that the customer selected.
  String productId;

  double quantity;
  double sellingPrice;
  double profit;

  /// Exact selling unit used for this sale, e.g. kg, viss, 220g.
  String saleUnit;

  /// The actual stock-holding product whose stock was reduced.
  String inventoryProductId;

  /// Exact amount removed from the inventory product's stock unit.
  double stockDeduction;

  double get amount => sellingPrice * quantity;

  String get name => product;
  double get price => sellingPrice;
  num get qty => quantity == quantity.roundToDouble()
      ? quantity.toInt()
      : quantity;

  Map<String, dynamic> toJson() => {
        'saleVoucherNumber': saleVoucherNumber,
        'product': product,
        'productId': productId,
        'quantity': quantity,
        'sellingPrice': sellingPrice,
        'profit': profit,
        'saleUnit': saleUnit,
        'inventoryProductId': inventoryProductId,
        'stockDeduction': stockDeduction,
      };

  factory SaleItem.fromJson(
    Map<String, dynamic> j, {
    String? fallbackVoucherNumber,
  }) => SaleItem(
        saleVoucherNumber:
            j['saleVoucherNumber'] as String? ?? fallbackVoucherNumber ?? '',
        product: j['product'] as String? ?? j['name'] as String? ?? '',
        productId: j['productId'] as String? ?? '',
        quantity: (j['quantity'] as num?)?.toDouble() ??
            (j['qty'] as num?)?.toDouble() ??
            0,
        sellingPrice: (j['sellingPrice'] as num?)?.toDouble() ??
            (j['price'] as num?)?.toDouble() ??
            0,
        profit: (j['profit'] as num?)?.toDouble() ?? 0,
        saleUnit: j['saleUnit'] as String? ?? '',
        inventoryProductId: j['inventoryProductId'] as String? ?? '',
        stockDeduction: (j['stockDeduction'] as num?)?.toDouble() ?? 0,
      );
}

class Sale {
  Sale({
    required this.voucherNumber,
    required this.customer,
    required this.date,
    this.paid = 0,
    this.paymentMethod = '',
    this.cylinderLedger = '',
    this.paymentDate,
  });

  String voucherNumber;
  String customer;
  DateTime date;
  double paid;
  String paymentMethod;
  String cylinderLedger;
  DateTime? paymentDate;

  String get id => voucherNumber;
  String get customerName => customer;

  Map<String, dynamic> toJson() => {
        'voucherNumber': voucherNumber,
        'customer': customer,
        'date': date.toIso8601String(),
        'paid': paid,
        'paymentMethod': paymentMethod,
        'cylinderLedger': cylinderLedger,
        'paymentDate': paymentDate?.toIso8601String(),
      };

  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        voucherNumber:
            j['voucherNumber'] as String? ?? j['id'] as String? ?? '',
        customer: j['customer'] as String? ??
            j['customerName'] as String? ??
            '',
        date: _parseDateTime(j['date']) ?? DateTime.now(),
        paid: (j['paid'] as num?)?.toDouble() ?? 0,
        paymentMethod: j['paymentMethod'] as String? ?? '',
        cylinderLedger: j['cylinderLedger'] as String? ?? '',
        paymentDate: _parseDateTime(j['paymentDate']),
      );
}

typedef Voucher = Sale;

class Expense {
  Expense({
    this.id = '',
    required this.date,
    required this.reason,
    required this.amount,
  });

  String id;
  DateTime date;
  String reason;
  double amount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'reason': reason,
        'amount': amount,
      };

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as String? ?? AppData.newId(),
        date: _parseDateTime(j['date']) ?? DateTime.now(),
        reason: j['reason'] as String? ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
      );
}

class IncomingSupply {
  IncomingSupply({
    this.id = '',
    this.productId = '',
    required this.product,
    required this.supplier,
    required this.date,
    required this.quantity,
    required this.costPerUnit,
    this.inputUnit = '',
    this.stockAdded = 0,
    this.paidAmount = 0,
    this.paymentDate,
  });

  String id;
  String productId;
  String product;
  String supplier;
  DateTime date;

  /// User-entered incoming quantity, e.g. 480 kg.
  double quantity;
  double costPerUnit;

  /// Human-readable input unit captured with the transaction.
  String inputUnit;

  /// Exact quantity added to product stock after conversion.
  double stockAdded;

  double paidAmount;
  DateTime? paymentDate;

  double get total => quantity * costPerUnit;
  double get balance =>
      (total - paidAmount).clamp(0, double.infinity).toDouble();
  bool get paid => balance <= 0.005;

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'product': product,
        'supplier': supplier,
        'date': date.toIso8601String(),
        'quantity': quantity,
        'costPerUnit': costPerUnit,
        'inputUnit': inputUnit,
        'stockAdded': stockAdded,
        'paidAmount': paidAmount,
        'paymentDate': paymentDate?.toIso8601String(),
        'paid': paid,
      };

  factory IncomingSupply.fromJson(Map<String, dynamic> j) {
    final quantity = (j['quantity'] as num?)?.toDouble() ?? 0;
    final cost = (j['costPerUnit'] as num?)?.toDouble() ?? 0;
    final oldPaid = j['paid'] as bool? ?? false;
    final storedPaid = (j['paidAmount'] as num?)?.toDouble();
    return IncomingSupply(
      id: j['id'] as String? ?? '',
      productId: j['productId'] as String? ?? '',
      product: j['product'] as String? ?? '',
      supplier: j['supplier'] as String? ?? '',
      date: _parseDateTime(j['date']) ?? DateTime.now(),
      quantity: quantity,
      costPerUnit: cost,
      inputUnit: j['inputUnit'] as String? ?? '',
      stockAdded: (j['stockAdded'] as num?)?.toDouble() ?? 0,
      paidAmount: storedPaid ?? (oldPaid ? quantity * cost : 0),
      paymentDate: _parseDateTime(j['paymentDate']),
    );
  }
}

class PaymentTransaction {
  PaymentTransaction({
    required this.id,
    required this.linkedType,
    required this.linkedId,
    required this.amount,
    required this.date,
    this.method = '',
    this.note = '',
  });

  String id;
  String linkedType; // 'sale' or 'supply'
  String linkedId;
  double amount; // positive payment; negative amount is an adjustment/reversal
  DateTime date;
  String method;
  String note;

  bool get isAdjustment => amount < 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'linkedType': linkedType,
        'linkedId': linkedId,
        'amount': amount,
        'date': date.toIso8601String(),
        'method': method,
        'note': note,
      };

  factory PaymentTransaction.fromJson(Map<String, dynamic> j) =>
      PaymentTransaction(
        id: j['id'] as String? ?? AppData.newId(),
        linkedType: j['linkedType'] as String? ?? '',
        linkedId: j['linkedId'] as String? ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        date: _parseDateTime(j['date']) ?? DateTime.now(),
        method: j['method'] as String? ?? '',
        note: j['note'] as String? ?? '',
      );
}

class LedgerEntry {
  LedgerEntry({
    required this.id,
    required this.name,
    this.note = '',
    required this.amount,
    required this.date,
    this.type = '',
  });

  final String id;
  String name;
  String note;
  double amount;
  DateTime date;
  String type;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'amount': amount,
        'date': date.toIso8601String(),
        'type': type,
      };

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: j['id'] as String? ?? AppData.newId(),
        name: j['name'] as String? ?? '',
        note: j['note'] as String? ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        date: _parseDateTime(j['date']) ?? DateTime.now(),
        type: j['type'] as String? ?? '',
      );
}

class CylinderRowData {
  CylinderRowData({
    required this.no,
    this.name = '',
    this.toReceiveProduct = '',
    this.toReceiveQty = '',
    this.toGiveBackProduct = '',
    this.toGiveBackQty = '',
  });

  int no;
  String name;
  String toReceiveProduct;
  String toReceiveQty;
  String toGiveBackProduct;
  String toGiveBackQty;

  Map<String, dynamic> toJson() => {
        'no': no,
        'name': name,
        'toReceiveProduct': toReceiveProduct,
        'toReceiveQty': toReceiveQty,
        'toGiveBackProduct': toGiveBackProduct,
        'toGiveBackQty': toGiveBackQty,
      };

  factory CylinderRowData.fromJson(Map<String, dynamic> j) => CylinderRowData(
        no: (j['no'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        toReceiveProduct: j['toReceiveProduct'] as String? ?? '',
        toReceiveQty: j['toReceiveQty'] as String? ?? '',
        toGiveBackProduct: j['toGiveBackProduct'] as String? ?? '',
        toGiveBackQty: j['toGiveBackQty'] as String? ?? '',
      );
}


class CylinderType {
  CylinderType({
    this.id = '',
    required this.baseType,
    required this.name,
    this.totalQuantity = 0,
  });

  String id;
  String baseType; // '48kg' or '10v'
  String name;

  /// Current physical quantity of this type in our possession.
  /// Cycle records automatically adjust this number when saved/deleted.
  double totalQuantity;

  Map<String, dynamic> toJson() => {
        'id': id,
        'baseType': baseType,
        'name': name,
        'totalQuantity': totalQuantity,
      };

  factory CylinderType.fromJson(Map<String, dynamic> j) => CylinderType(
      id: j['id'] as String? ?? AppData.newId(),
      baseType: j['baseType'] as String? ?? '48kg',
      name: j['name'] as String? ?? '',
      totalQuantity: (j['totalQuantity'] as num?)?.toDouble() ??
          (j['quantityInOurPossession'] as num?)?.toDouble() ??
          0,
    );
}

class CylinderCycle {
  CylinderCycle({
    this.id = '',
    this.cylinderTypeId = '',
    required this.customer,
    required this.product,
    required this.givenQuantity,
    required this.receivedQuantity,
    required this.date,
  });

  String id;
  String cylinderTypeId;
  String customer;
  String product; // Snapshot of the cylinder type name for history.
  double givenQuantity;
  double receivedQuantity;
  DateTime date;

  double get balance => givenQuantity - receivedQuantity;

  Map<String, dynamic> toJson() => {
        'id': id,
        'cylinderTypeId': cylinderTypeId,
        'customer': customer,
        'product': product,
        'givenQuantity': givenQuantity,
        'receivedQuantity': receivedQuantity,
        'date': date.toIso8601String(),
      };

  factory CylinderCycle.fromJson(Map<String, dynamic> j) => CylinderCycle(
        id: j['id'] as String? ?? AppData.newId(),
        cylinderTypeId: j['cylinderTypeId'] as String? ?? '',
        customer: j['customer'] as String? ?? '',
        product: j['product'] as String? ?? '48 kg',
        givenQuantity: (j['givenQuantity'] as num?)?.toDouble() ??
            (j['giveQuantity'] as num?)?.toDouble() ??
            0,
        receivedQuantity: (j['receivedQuantity'] as num?)?.toDouble() ??
            (j['receiveQuantity'] as num?)?.toDouble() ??
            0,
        date: _parseDateTime(j['date']) ?? DateTime.now(),
      );
}

// =====================================================================
// APP-WIDE DATA STORE
// =====================================================================

class AppData {
  AppData._internal() {
    _ensureDefaultCylinderTypes();
  }
  static final AppData instance = AppData._internal();

  static int _counter = 0;
  static String newId() {
    _counter++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_counter';
  }

  String newVoucherNumber() {
    var max = 0;
    final pattern = RegExp(r'^V-(\d+)$');
    for (final sale in sales) {
      final match = pattern.firstMatch(sale.voucherNumber);
      if (match != null) {
        final number = int.tryParse(match.group(1)!) ?? 0;
        if (number > max) max = number;
      }
    }
    return 'V-${(max + 1).toString().padLeft(6, '0')}';
  }

  static const _storageKey = 'pos_app_data_v1';
  static const _backupStorageKey = 'pos_app_data_v1_backup';
  static const _tempStorageKey = 'pos_app_data_v1_temp';

  final List<Product> products = [];
  final List<Person> people = [];

  final List<Sale> sales = [];
  final List<SaleItem> saleItems = [];

  final List<IncomingSupply> incomingSupplies = [];
  final List<PaymentTransaction> paymentTransactions = [];
  final List<Expense> expenses = [];

  List<LedgerEntry> get payYanEntries => _buildPayYanEntries();
  List<LedgerEntry> get yaYanEntries => _buildYaYanEntries();

  List<LedgerEntry> get cashEntries => _buildCashEntries();

  final List<LedgerEntry> incomeExpenseEntries = [];

  // Legacy table data is kept for backup compatibility.
  List<CylinderRowData> cylinderRows =
      List.generate(17, (i) => CylinderRowData(no: i + 1));

  final List<CylinderType> cylinderTypes = [];
  final List<CylinderCycle> cylinderCycles = [];

  bool _loaded = false;
  String? loadError;
  String? lastSaveError;
  String _lastKnownGoodJson = '{}';
  Future<void> _saveChain = Future<void>.value();

  List<Sale> get vouchers => sales;

  Map<String, dynamic> _snapshot() => {
        'products': products.map((p) => p.toJson()).toList(),
        'people': people.map((p) => p.toJson()).toList(),
        'sales': sales.map((s) => s.toJson()).toList(),
        'saleItems': saleItems.map((i) => i.toJson()).toList(),
        'incomingSupplies':
            incomingSupplies.map((s) => s.toJson()).toList(),
        'paymentTransactions':
            paymentTransactions.map((p) => p.toJson()).toList(),
        'expenses': expenses.map((e) => e.toJson()).toList(),
        'incomeExpense': incomeExpenseEntries.map((e) => e.toJson()).toList(),
        'cylinderRows': cylinderRows.map((r) => r.toJson()).toList(),
        'cylinderTypes': cylinderTypes.map((t) => t.toJson()).toList(),
        'cylinderCycles': cylinderCycles.map((c) => c.toJson()).toList(),
      };

  void _replaceStateFrom(AppData source) {
    products
      ..clear()
      ..addAll(source.products);
    people
      ..clear()
      ..addAll(source.people);
    sales
      ..clear()
      ..addAll(source.sales);
    saleItems
      ..clear()
      ..addAll(source.saleItems);
    incomingSupplies
      ..clear()
      ..addAll(source.incomingSupplies);
    paymentTransactions
      ..clear()
      ..addAll(source.paymentTransactions);
    expenses
      ..clear()
      ..addAll(source.expenses);
    incomeExpenseEntries
      ..clear()
      ..addAll(source.incomeExpenseEntries);
    cylinderRows = List<CylinderRowData>.from(source.cylinderRows);
    cylinderTypes
      ..clear()
      ..addAll(source.cylinderTypes);
    cylinderCycles
      ..clear()
      ..addAll(source.cylinderCycles);
  }

  AppData _parseIntoTemporary(String raw) {
    var cleaned = raw.replaceFirst('\uFEFF', '').trim();
    if (cleaned.startsWith('```')) {
      final firstNewline = cleaned.indexOf('\n');
      if (firstNewline >= 0) {
        cleaned = cleaned.substring(firstNewline + 1);
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
      cleaned = cleaned.trim();
    }

    if (cleaned.isEmpty) {
      throw const FormatException('Backup is empty.');
    }

    dynamic decoded = jsonDecode(cleaned);

    // Some note/backup apps save JSON as a JSON-encoded string. Accept that
    // form as well, but only unwrap it once to avoid accepting arbitrary data.
    if (decoded is String) {
      decoded = jsonDecode(decoded);
    }

    // Accept a simple {"data": {...}} or {"backup": {...}} wrapper too.
    if (decoded is Map && decoded['data'] is Map) {
      decoded = decoded['data'];
    } else if (decoded is Map && decoded['backup'] is Map) {
      decoded = decoded['backup'];
    }

    if (decoded is! Map) {
      throw const FormatException('Backup root must be a JSON object.');
    }

    final map = Map<String, dynamic>.from(decoded);
    const knownKeys = <String>{
      'products',
      'people',
      'sales',
      'saleItems',
      'vouchers',
      'incomingSupplies',
      'paymentTransactions',
      'expenses',
      'incomeExpense',
      'cylinderRows',
      'cylinderTypes',
      'cylinderCycles',
    };
    if (!map.keys.any(knownKeys.contains)) {
      throw const FormatException(
        'This does not look like a POS backup. No recognized data sections were found.',
      );
    }

    final temp = AppData._internal();
    temp._restoreFrom(map);
    return temp;
  }

  void _restoreFrom(Map<String, dynamic> map) {
    products
      ..clear()
      ..addAll(
        ((map['products'] as List?) ?? [])
            .map((e) => Product.fromJson(e as Map<String, dynamic>)),
      );

    people
      ..clear()
      ..addAll(
        ((map['people'] as List?) ?? [])
            .map((e) => Person.fromJson(e as Map<String, dynamic>)),
      );

    _migrateProductInventorySettings();

    sales.clear();
    saleItems.clear();

    final newSales = map['sales'] as List?;
    final newSaleItems = map['saleItems'] as List?;

    if (newSales != null) {
      sales.addAll(
        newSales.map((e) => Sale.fromJson(e as Map<String, dynamic>)),
      );
      if (newSaleItems != null) {
        saleItems.addAll(
          newSaleItems.map(
            (e) => SaleItem.fromJson(e as Map<String, dynamic>),
          ),
        );
      }
    } else {
      final oldVouchers = map['vouchers'] as List?;
      if (oldVouchers != null) {
        for (final raw in oldVouchers) {
          final voucherMap = raw as Map<String, dynamic>;
          final sale = Sale.fromJson(voucherMap);
          sales.add(sale);

          final oldItems = voucherMap['items'] as List? ?? const [];
          for (final item in oldItems) {
            saleItems.add(
              SaleItem.fromJson(
                item as Map<String, dynamic>,
                fallbackVoucherNumber: sale.voucherNumber,
              ),
            );
          }
        }
      }
    }

    for (final item in saleItems) {
      final product = _productForSaleItem(item);
      if (product == null) continue;
      item.productId = product.id;
      final inventory = inventoryProductForSale(product);
      if (inventory != null && item.inventoryProductId.isEmpty) {
        item.inventoryProductId = inventory.id;
      }
      if (item.saleUnit.trim().isEmpty) {
        if (product.saleConsumptionMode == 'kg_or_viss') {
          final measurement = product.measurement.toLowerCase();
          item.saleUnit = measurement.contains('viss') || measurement.contains('ပိသာ')
              ? 'viss'
              : 'kg';
        } else {
          item.saleUnit = product.saleUnit;
        }
      }
      if (item.stockDeduction <= 0) {
        try {
          item.stockDeduction = stockConsumptionForSale(
            product,
            item.quantity,
            saleUnit: item.saleUnit,
          );
        } catch (_) {
          // Keep legacy zero when the old record does not contain enough
          // information to reconstruct its stock unit safely.
        }
      }
    }

    incomingSupplies
      ..clear()
      ..addAll(
        ((map['incomingSupplies'] as List?) ?? []).map(
          (e) => IncomingSupply.fromJson(e as Map<String, dynamic>),
        ),
      );
    for (final supply in incomingSupplies) {
      if (supply.id.isEmpty) supply.id = newId();
      final product = supply.productId.isEmpty
          ? _productForSupply(supply)
          : productById(supply.productId);
      if (product != null) {
        supply.productId = product.id;
        supply.product = product.name;
        if (supply.inputUnit.trim().isEmpty) {
          supply.inputUnit = product.incomingUnit.trim().isEmpty
              ? 'unit'
              : product.incomingUnit.trim();
        }
        if (supply.stockAdded <= 0) {
          supply.stockAdded = supply.quantity *
              (product.incomingStockUnitsPerInput > 0
                  ? product.incomingStockUnitsPerInput
                  : 1);
        }
      }
    }

    paymentTransactions
      ..clear()
      ..addAll(
        ((map['paymentTransactions'] as List?) ?? []).map(
          (e) => PaymentTransaction.fromJson(e as Map<String, dynamic>),
        ),
      );

    _migrateLegacyPayments();

    expenses
      ..clear()
      ..addAll(
        ((map['expenses'] as List?) ?? []).map(
          (e) => Expense.fromJson(e as Map<String, dynamic>),
        ),
      );

    incomeExpenseEntries
      ..clear()
      ..addAll(
        ((map['incomeExpense'] as List?) ?? [])
            .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>)),
      );

    if (expenses.isEmpty) {
      for (final entry in incomeExpenseEntries) {
        if (entry.type == 'expense') {
          expenses.add(
            Expense(
              id: entry.id,
              date: entry.date,
              reason: entry.name,
              amount: entry.amount,
            ),
          );
        }
      }
    }

    cylinderTypes
      ..clear()
      ..addAll(
        ((map['cylinderTypes'] as List?) ?? const []).map(
          (e) => CylinderType.fromJson(e as Map<String, dynamic>),
        ),
      );
    _ensureDefaultCylinderTypes();
    for (final type in cylinderTypes) {
      if (!type.totalQuantity.isFinite || type.totalQuantity < 0) {
        type.totalQuantity = 0;
      }
    }

    final rows = map['cylinderRows'] as List?;
    if (rows != null && rows.isNotEmpty) {
      cylinderRows = rows
          .map((e) => CylinderRowData.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    final storedCylinderCycles = map['cylinderCycles'] as List?;
    cylinderCycles
      ..clear()
      ..addAll(
        (storedCylinderCycles ?? const []).map(
          (e) => CylinderCycle.fromJson(e as Map<String, dynamic>),
        ),
      );

    // Convert the old 17-row cylinder table to the new transaction model
    // once, so existing outstanding balances are not lost after an update.
    if (storedCylinderCycles == null) {
      for (final row in cylinderRows) {
        final customer = row.name.trim();
        if (customer.isEmpty) continue;

        final receiveProduct = _normalizeCylinderProduct(row.toReceiveProduct);
        final giveProduct = _normalizeCylinderProduct(row.toGiveBackProduct);
        final receiveQty = double.tryParse(row.toReceiveQty.trim()) ?? 0;
        final giveQty = double.tryParse(row.toGiveBackQty.trim()) ?? 0;

        if (receiveProduct != null && receiveQty > 0) {
          cylinderCycles.add(
            CylinderCycle(
              id: 'legacy-cylinder:${row.no}:receive',
              customer: customer,
              product: receiveProduct,
              givenQuantity: 0,
              receivedQuantity: receiveQty,
              date: DateTime.now(),
            ),
          );
        }
        if (giveProduct != null && giveQty > 0) {
          cylinderCycles.add(
            CylinderCycle(
              id: 'legacy-cylinder:${row.no}:give',
              customer: customer,
              product: giveProduct,
              givenQuantity: giveQty,
              receivedQuantity: 0,
              date: DateTime.now(),
            ),
          );
        }
      }
    }

    _migrateCylinderCycleTypeIds();
  }

  void _migrateProductInventorySettings() {
    // LPG main-stock inventory is now kg-only. This is a metadata migration:
    // it changes only how NEW incoming quantities are entered. Existing stock
    // values and old incoming transactions keep their stored quantities.
    for (final product in products) {
      final isLpgMainStock =
          product.type.trim().toLowerCase() == 'lpg' &&
          !product.subtractFromParentStock;

      if (isLpgMainStock) {
        product.incomingUnit = 'kg';
        product.incomingStockUnitsPerInput = 1;
      } else if (product.incomingUnit.trim().isEmpty) {
        product.incomingUnit = product.measurement.trim().isEmpty
            ? 'unit'
            : product.measurement.trim();
      }
      if (product.saleUnit.trim().isEmpty) {
        product.saleUnit = product.subType.trim().isEmpty
            ? (product.measurement.trim().isEmpty ? 'unit' : product.measurement.trim())
            : product.subType.trim();
      }
      if (product.incomingStockUnitsPerInput <= 0) {
        product.incomingStockUnitsPerInput = 1;
      }
      if (product.saleStockUnitsPerUnit <= 0 &&
          product.saleConsumptionMode == 'fixed') {
        product.saleStockUnitsPerUnit = 1;
      }
    }
  }

  static String _normalizeSaleUnit(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'viss' || value == 'vis' || value == 'ပိသာ') return 'viss';
    if (value == 'kg' || value == 'kgs' || value == 'kilogram' || value == 'kilograms') {
      return 'kg';
    }
    return raw.trim();
  }

  static String? _normalizeCylinderProduct(String raw) {
    final value = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (value == '48' || value == '48kg' || value == '48kgs') {
      return '48kg';
    }
    if (value == '10v' || value == '10viss') {
      return '10v';
    }
    return null;
  }

  void _ensureDefaultCylinderTypes() {
    if (cylinderTypes.isEmpty) {
      cylinderTypes.addAll([
        CylinderType(
          id: 'default-cylinder-48kg',
          baseType: '48kg',
          name: '48 kg',
        ),
        CylinderType(
          id: 'default-cylinder-10v',
          baseType: '10v',
          name: '10v',
        ),
      ]);
    }

    for (final type in cylinderTypes) {
      if (type.id.isEmpty) type.id = newId();
      type.baseType = type.baseType.trim().toLowerCase();
    }
  }

  void _migrateCylinderCycleTypeIds() {
    _ensureDefaultCylinderTypes();
    for (final cycle in cylinderCycles) {
      if (cycle.id.isEmpty) cycle.id = newId();
      if (cycle.cylinderTypeId.isNotEmpty &&
          cylinderTypes.any((type) => type.id == cycle.cylinderTypeId)) {
        continue;
      }

      final normalized = _normalizeCylinderProduct(cycle.product);
      CylinderType? match;
      if (normalized != null) {
        for (final type in cylinderTypes) {
          if (type.baseType == normalized) {
            match = type;
            break;
          }
        }
      }
      match ??= cylinderTypes.firstWhere(
        (type) => type.name.toLowerCase() == cycle.product.toLowerCase(),
        orElse: () => cylinderTypes.first,
      );
      cycle.cylinderTypeId = match.id;
      cycle.product = cycle.product.trim().isEmpty ? match.name : cycle.product;
    }
  }

  CylinderType? cylinderTypeById(String id) {
    for (final type in cylinderTypes) {
      if (type.id == id) return type;
    }
    return null;
  }

  String cylinderTypeNameFor(CylinderCycle cycle) =>
      cylinderTypeById(cycle.cylinderTypeId)?.name ?? cycle.product;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    loadError = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);

      if (raw == null || raw.isEmpty) {
        _lastKnownGoodJson = jsonEncode(_snapshot());
        return;
      }

      AppData parsed;
      try {
        parsed = _parseIntoTemporary(raw);
      } catch (_) {
        final temp = prefs.getString(_tempStorageKey);
        final backup = prefs.getString(_backupStorageKey);
        if (temp != null && temp.isNotEmpty) {
          try {
            parsed = _parseIntoTemporary(temp);
          } catch (_) {
            if (backup == null || backup.isEmpty) rethrow;
            parsed = _parseIntoTemporary(backup);
          }
        } else {
          if (backup == null || backup.isEmpty) rethrow;
          parsed = _parseIntoTemporary(backup);
        }

        // The primary copy was bad; restore a complete, independently parsed
        // copy. Never restore a partially parsed primary document.
        _replaceStateFrom(parsed);
        final goodJson = jsonEncode(_snapshot());
        await prefs.setString(_storageKey, goodJson);
        await prefs.remove(_tempStorageKey);
        _lastKnownGoodJson = goodJson;
        return;
      }

      _replaceStateFrom(parsed);
      _lastKnownGoodJson = raw;

      // Persist migrations only after the complete document parsed successfully.
      if (!raw.contains('"paymentTransactions"') ||
          !raw.contains('"cylinderCycles"') ||
          !raw.contains('"cylinderTypes"')) {
        final migrated = await save();
        if (!migrated) {
          // save() already restored the previous known-good state.
          loadError = 'Data loaded, but the migration could not be saved.';
        }
      }
    } catch (e) {
      loadError = 'Stored data could not be loaded safely: $e';
      debugPrint(loadError);
      // Do not save here. In particular, never replace a damaged/unknown
      // on-device database with the empty in-memory state.
      _lastKnownGoodJson = jsonEncode(_snapshot());
    }
  }

  Future<bool> save() {
    final operation = _saveChain.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final json = jsonEncode(_snapshot());
        final current = prefs.getString(_storageKey);
        if (current != null && current.isNotEmpty) {
          // Keep the previous successfully stored document as the rollback copy.
          await prefs.setString(_backupStorageKey, current);
        }

        // Write the new document to a temporary key first, then replace the
        // primary document. The temporary copy also survives a failed primary write.
        await prefs.setString(_tempStorageKey, json);
        final wrote = await prefs.setString(_storageKey, json);
        if (!wrote) {
          throw StateError('SharedPreferences rejected the database write.');
        }
        await prefs.remove(_tempStorageKey);

        _lastKnownGoodJson = json;
        lastSaveError = null;
        return true;
      } catch (e) {
        lastSaveError = 'Could not save data: $e';
        debugPrint(lastSaveError);

        // Roll the in-memory state back to the last document known to be
        // persisted. This prevents a later save from silently overwriting
        // the stored database with an unsaved/partially changed state.
        try {
          final rollback = _parseIntoTemporary(_lastKnownGoodJson);
          _replaceStateFrom(rollback);
        } catch (rollbackError) {
          debugPrint('Rollback failed: $rollbackError');
        }

        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(uiT('Save failed. Your last saved data was kept.')),
            action: SnackBarAction(
              label: uiT('OK'),
              onPressed: () {},
            ),
          ),
        );
        return false;
      }
    });

    _saveChain = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  String exportJson() =>
      const JsonEncoder.withIndent('  ').convert(_snapshot());

  Future<void> importJson(String raw) async {
    // Parse the complete backup into an isolated object first. Nothing in
    // the live database changes until every record has been parsed.
    final parsed = _parseIntoTemporary(raw);
    final previous = _lastKnownGoodJson;

    _replaceStateFrom(parsed);
    final saved = await save();

    if (!saved) {
      // save() rolls back to the previous persisted state.
      _lastKnownGoodJson = previous;
      throw StateError('Imported data could not be saved.');
    }
  }

  Future<void> clearAll() async {
    products.clear();
    people.clear();
    sales.clear();
    saleItems.clear();
    incomingSupplies.clear();
    paymentTransactions.clear();
    expenses.clear();
    incomeExpenseEntries.clear();
    cylinderRows = List.generate(17, (i) => CylinderRowData(no: i + 1));
    cylinderTypes
      ..clear()
      ..addAll([
        CylinderType(id: 'default-cylinder-48kg', baseType: '48kg', name: '48 kg'),
        CylinderType(id: 'default-cylinder-10v', baseType: '10v', name: '10v'),
      ]);
    cylinderCycles.clear();
    if (!await save()) {
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }

  // ---- Products (master catalog) ----
  Product? productById(String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  Product? _findDuplicateProduct(Product candidate, {String? excludingId}) {
    final name = candidate.name.trim().toLowerCase();
    final type = candidate.type.trim().toLowerCase();
    final subType = candidate.subType.trim().toLowerCase();

    for (final existing in products) {
      if (excludingId != null && existing.id == excludingId) continue;
      if (existing.name.trim().toLowerCase() == name &&
          existing.type.trim().toLowerCase() == type &&
          existing.subType.trim().toLowerCase() == subType) {
        return existing;
      }
    }
    return null;
  }

  Future<void> addProduct(Product product) async {
    product.name = product.name.trim();
    product.type = product.type.trim();
    product.subType = product.subType.trim();
    product.measurement = product.measurement.trim();
    product.incomingUnit = product.incomingUnit.trim();
    product.saleUnit = product.saleUnit.trim();
    product.supplier = product.supplier.trim();
    product.saleConsumptionMode =
        product.saleConsumptionMode.trim().isEmpty ? 'fixed' : product.saleConsumptionMode.trim();

    if (product.type.toLowerCase() == 'lpg' && !product.subtractFromParentStock) {
      product.measurement = 'kg';
      product.incomingUnit = 'kg';
      product.incomingStockUnitsPerInput = 1;
    }

    if (product.name.isEmpty) {
      throw StateError('Product name cannot be empty.');
    }
    if (product.incomingStockUnitsPerInput <= 0) {
      throw StateError('Incoming stock conversion must be greater than zero.');
    }
    if (product.subtractFromParentStock) {
      if (product.parentProductId.isEmpty) {
        throw StateError('Select the parent stock product for this selling variant.');
      }
      final parent = productById(product.parentProductId);
      if (parent == null) {
        throw StateError('The selected parent stock product was not found.');
      }
      if (parent.id == product.id) {
        throw StateError('A product cannot subtract its own stock.');
      }
      if (parent.subtractFromParentStock) {
        throw StateError('A selling variant cannot use another selling variant as its parent. Choose the main stock product.');
      }
      if (product.saleConsumptionMode == 'fixed' && product.saleStockUnitsPerUnit <= 0) {
        throw StateError('Stock used per sale unit must be greater than zero.');
      }
    } else {
      product.parentProductId = '';
      if (product.saleStockUnitsPerUnit <= 0) {
        product.saleStockUnitsPerUnit = 1;
      }
    }
    if (_findDuplicateProduct(product) != null) {
      throw StateError('A product with the same name, type, and sub type already exists.');
    }

    product.id = product.id.isEmpty ? newId() : product.id;
    // A master product does not receive stock when it is created.
    // Stock enters only through an Incoming Products transaction.
    product.stock = 0;
    product.lastIncomingDate = null;
    products.add(product);

    if (!await save()) {
      throw StateError('Product could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> updateProduct(Product updated) async {
    final index = products.indexWhere((product) => product.id == updated.id);
    if (index < 0) throw StateError('Product was not found.');

    updated.name = updated.name.trim();
    updated.type = updated.type.trim();
    updated.subType = updated.subType.trim();
    updated.measurement = updated.measurement.trim();
    updated.incomingUnit = updated.incomingUnit.trim();
    updated.saleUnit = updated.saleUnit.trim();
    updated.supplier = updated.supplier.trim();
    updated.saleConsumptionMode =
        updated.saleConsumptionMode.trim().isEmpty ? 'fixed' : updated.saleConsumptionMode.trim();

    if (updated.type.toLowerCase() == 'lpg' && !updated.subtractFromParentStock) {
      updated.measurement = 'kg';
      updated.incomingUnit = 'kg';
      updated.incomingStockUnitsPerInput = 1;
    }

    if (updated.name.isEmpty) {
      throw StateError('Product name cannot be empty.');
    }
    if (updated.incomingStockUnitsPerInput <= 0) {
      throw StateError('Incoming stock conversion must be greater than zero.');
    }
    if (updated.subtractFromParentStock) {
      if (updated.parentProductId.isEmpty) {
        throw StateError('Select the parent stock product for this selling variant.');
      }
      final parent = productById(updated.parentProductId);
      if (parent == null) throw StateError('The selected parent stock product was not found.');
      if (parent.id == updated.id) throw StateError('A product cannot subtract its own stock.');
      if (parent.subtractFromParentStock) {
        throw StateError('A selling variant cannot use another selling variant as its parent. Choose the main stock product.');
      }
      if (updated.saleConsumptionMode == 'fixed' && updated.saleStockUnitsPerUnit <= 0) {
        throw StateError('Stock used per sale unit must be greater than zero.');
      }
    } else {
      updated.parentProductId = '';
      if (updated.saleStockUnitsPerUnit <= 0) updated.saleStockUnitsPerUnit = 1;
    }
    if (_findDuplicateProduct(updated, excludingId: updated.id) != null) {
      throw StateError('Another product already has the same name, type, and sub type.');
    }

    final existing = products[index];
    // Stock and lastIncomingDate belong to inventory transactions, so they
    // cannot be overwritten from the master-product edit form.
    updated.stock = existing.stock;
    updated.lastIncomingDate = existing.lastIncomingDate;
    products[index] = updated;

    if (!await save()) {
      throw StateError('Product could not be updated. Your previous saved data was kept.');
    }
  }

  Future<void> addIncomingProduct({
    required IncomingSupply supply,
    String paymentMethod = '',
  }) async {
    if (supply.id.isEmpty) supply.id = newId();
    if (supply.quantity <= 0) {
      throw StateError('Incoming quantity must be greater than zero.');
    }
    if (supply.costPerUnit < 0) {
      throw StateError('Incoming cost cannot be negative.');
    }

    Product? actualProduct = productById(supply.productId);
    actualProduct ??= _productForSupply(supply);
    if (actualProduct == null) {
      throw StateError('Select an existing main stock product before recording incoming stock.');
    }
    if (actualProduct.subtractFromParentStock) {
      throw StateError(
        'This product is a selling variant. Receive stock into its parent product instead.',
      );
    }

    supply.productId = actualProduct.id;
    supply.product = actualProduct.name;

    final isLpgMainStock =
        actualProduct.type.trim().toLowerCase() == 'lpg' &&
        !actualProduct.subtractFromParentStock;

    // LPG receiving is intentionally kg-only. There is no cylinder input mode.
    if (isLpgMainStock) {
      actualProduct.incomingUnit = 'kg';
      actualProduct.incomingStockUnitsPerInput = 1;
      supply.inputUnit = 'kg';
    } else {
      supply.inputUnit = actualProduct.incomingUnit.trim().isEmpty
          ? 'unit'
          : actualProduct.incomingUnit.trim();
    }

    supply.stockAdded = supply.quantity * actualProduct.incomingStockUnitsPerInput;

    // Incoming is the only operation that increases stock.
    actualProduct.stock += supply.stockAdded;
    actualProduct.lastIncomingDate = supply.date;

    // Incoming cost is entered per incoming unit. For LPG that is per kg,
    // while Product.cost remains the cost of one direct sale unit.
    if (isLpgMainStock) {
      final saleConversion = actualProduct.saleStockUnitsPerUnit > 0
          ? actualProduct.saleStockUnitsPerUnit
          : 1;
      actualProduct.cost = supply.costPerUnit * saleConversion;
    } else {
      actualProduct.cost = supply.costPerUnit;
    }
    if (supply.supplier.trim().isNotEmpty) {
      actualProduct.supplier = supply.supplier.trim();
    }

    incomingSupplies.add(supply);

    if (supply.paidAmount > 0) {
      paymentTransactions.add(
        PaymentTransaction(
          id: newId(),
          linkedType: 'supply',
          linkedId: supply.id,
          amount: supply.paidAmount.clamp(0, supply.total).toDouble(),
          date: supply.paymentDate ?? DateTime.now(),
          method: paymentMethod,
          note: 'Initial supplier payment',
        ),
      );
      supply.paidAmount = paidForSupply(supply.id);
    }

    if (!await save()) {
      throw StateError('Incoming product could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> deleteProduct(Product product) async {
    final children = products
        .where((p) => p.parentProductId == product.id)
        .toList();
    if (children.isNotEmpty) {
      throw StateError(
        'This product is a parent stock product for ${children.length} selling variant(s). Delete or reassign those variants first.',
      );
    }

    final linkedIncoming = incomingSupplies
        .where(
          (supply) => supply.productId == product.id ||
              (supply.productId.isEmpty &&
                  supply.product.toLowerCase() == product.name.toLowerCase()),
        )
        .toList();
    final hasSales = saleItems.any(
      (item) => item.productId == product.id ||
          (item.productId.isEmpty &&
              item.product.toLowerCase() == product.name.toLowerCase()),
    );

    if (hasSales) {
      throw StateError(
        'This product is used by saved sales and cannot be deleted safely. Delete the incorrect Sale record first.',
      );
    }

    final incomingIds = linkedIncoming.map((supply) => supply.id).toSet();
    incomingSupplies.removeWhere((supply) => incomingIds.contains(supply.id));
    paymentTransactions.removeWhere(
      (payment) =>
          payment.linkedType == 'supply' && incomingIds.contains(payment.linkedId),
    );
    products.removeWhere((p) => p.id == product.id);

    if (!await save()) {
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }

  Product? _productForSaleName(String name) {
    final normalized = name.trim().toLowerCase();
    for (final p in products) {
      final full = [p.name, p.type, p.subType]
          .where((x) => x.isNotEmpty)
          .join(' ')
          .toLowerCase();
      if (p.name.toLowerCase() == normalized || full == normalized) return p;
    }
    return null;
  }

  Product? _productForSaleItem(SaleItem item) {
    if (item.productId.isNotEmpty) {
      final direct = productById(item.productId);
      if (direct != null) return direct;
    }
    return _productForSaleName(item.product);
  }

  Product? inventoryProductForSale(Product saleProduct) {
    if (!saleProduct.subtractFromParentStock) return saleProduct;
    final parent = productById(saleProduct.parentProductId);
    return parent;
  }

  double stockConsumptionForSale(
    Product saleProduct,
    double quantity, {
    String saleUnit = '',
  }) {
    if (quantity <= 0) return 0;

    if (saleProduct.subtractFromParentStock &&
        saleProduct.saleConsumptionMode == 'kg_or_viss') {
      final unit = _normalizeSaleUnit(saleUnit);
      if (unit == 'kg') return quantity;
      if (unit == 'viss') return quantity * 1.6;
      throw StateError('Select whether legacy loose gas is sold by kg or viss.');
    }

    final conversion = saleProduct.saleStockUnitsPerUnit > 0
        ? saleProduct.saleStockUnitsPerUnit
        : 1;
    return quantity * conversion;
  }

  double costAmountForSale(
    Product saleProduct,
    double quantity, {
    String saleUnit = '',
  }) {
    final inventoryProduct = inventoryProductForSale(saleProduct);
    if (inventoryProduct == null) {
      throw StateError('The selected product is missing its parent stock product.');
    }

    final deduction = stockConsumptionForSale(
      saleProduct,
      quantity,
      saleUnit: saleUnit,
    );
    final parentSaleConversion = inventoryProduct.saleStockUnitsPerUnit > 0
        ? inventoryProduct.saleStockUnitsPerUnit
        : 1;
    final costPerInventoryUnit = inventoryProduct.cost / parentSaleConversion;
    return deduction * costPerInventoryUnit;
  }

  Future<void> deductStockForSale(
    String name,
    double qty, {
    String productId = '',
    String saleUnit = '',
  }) async {
    if (name.trim().isEmpty) return;
    final product = productId.isNotEmpty
        ? productById(productId)
        : _productForSaleName(name);
    if (product == null) return;
    final inventoryProduct = inventoryProductForSale(product);
    if (inventoryProduct == null) return;
    final deduction = stockConsumptionForSale(
      product,
      qty,
      saleUnit: saleUnit,
    );
    inventoryProduct.stock -= deduction;
  }

  // ---- People ----
  Future<void> addPerson(Person p) async {
    people.add(p);
    if (!await save()) {
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> deletePerson(Person person) async {
    people.remove(person);
    if (!await save()) {
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }

  // ---- Payment transactions ----
  List<PaymentTransaction> paymentsForSale(String voucherNumber) =>
      paymentTransactions
          .where((p) => p.linkedType == 'sale' && p.linkedId == voucherNumber)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  List<PaymentTransaction> paymentsForSupply(String supplyId) =>
      paymentTransactions
          .where((p) => p.linkedType == 'supply' && p.linkedId == supplyId)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  double paidForSale(String voucherNumber) => paymentTransactions
      .where((p) => p.linkedType == 'sale' && p.linkedId == voucherNumber)
      .fold(0.0, (sum, p) => sum + p.amount)
      .clamp(0, double.infinity)
      .toDouble();

  double paidForSupply(String supplyId) => paymentTransactions
      .where((p) => p.linkedType == 'supply' && p.linkedId == supplyId)
      .fold(0.0, (sum, p) => sum + p.amount)
      .clamp(0, double.infinity)
      .toDouble();

  void _migrateLegacyPayments() {
    for (final sale in sales) {
      final hasTransactions = paymentTransactions.any(
        (p) => p.linkedType == 'sale' && p.linkedId == sale.voucherNumber,
      );
      if (!hasTransactions && sale.paid > 0) {
        paymentTransactions.add(
          PaymentTransaction(
            id: 'legacy-sale:${sale.voucherNumber}',
            linkedType: 'sale',
            linkedId: sale.voucherNumber,
            amount: sale.paid,
            date: sale.paymentDate ?? sale.date,
            method: sale.paymentMethod,
            note: 'Legacy payment migrated',
          ),
        );
      }
      sale.paid = paidForSale(sale.voucherNumber);
    }

    for (final supply in incomingSupplies) {
      final hasTransactions = paymentTransactions.any(
        (p) => p.linkedType == 'supply' && p.linkedId == supply.id,
      );
      if (!hasTransactions && supply.paidAmount > 0) {
        paymentTransactions.add(
          PaymentTransaction(
            id: 'legacy-supply:${supply.id}',
            linkedType: 'supply',
            linkedId: supply.id,
            amount: supply.paidAmount,
            date: supply.paymentDate ?? supply.date,
            note: 'Legacy payment migrated',
          ),
        );
      }
      supply.paidAmount = paidForSupply(supply.id);
    }
  }

  Future<void> addPaymentTransaction({
    required String linkedType,
    required String linkedId,
    required double amount,
    DateTime? date,
    String method = '',
    String note = '',
  }) async {
    if (amount.abs() <= 0.000001) return;
    paymentTransactions.add(
      PaymentTransaction(
        id: newId(),
        linkedType: linkedType,
        linkedId: linkedId,
        amount: amount,
        date: date ?? DateTime.now(),
        method: method,
        note: note,
      ),
    );
    if (!await save()) {
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }

  // ---- Incoming supply ----
  // Kept as a compatibility alias for older callers. New code should call
  // addIncomingProduct(), which clearly represents an inventory receipt for
  // an existing master product.
  Future<void> addIncomingSupply(IncomingSupply supply, {String paymentMethod = ''}) {
    return addIncomingProduct(
      supply: supply,
      paymentMethod: paymentMethod,
    );
  }

  Product? _productForSupply(IncomingSupply supply) {
    if (supply.productId.isNotEmpty) {
      for (final product in products) {
        if (product.id == supply.productId) return product;
      }
    }
    final normalized = supply.product.trim().toLowerCase();
    for (final product in products) {
      if (product.name.trim().toLowerCase() == normalized) return product;
    }
    return null;
  }

  Future<void> deleteIncomingSupply(String id) async {
    final index = incomingSupplies.indexWhere((supply) => supply.id == id);
    if (index < 0) return;

    final supply = incomingSupplies[index];
    final product = _productForSupply(supply);
    if (product != null) {
      final stockToReverse = supply.stockAdded > 0
          ? supply.stockAdded
          : supply.quantity *
              (product.incomingStockUnitsPerInput > 0
                  ? product.incomingStockUnitsPerInput
                  : 1);
      if (product.stock + 0.000001 < stockToReverse) {
        throw StateError(
          'This incoming record cannot be deleted safely because some of the received stock has already been sold or otherwise consumed.',
        );
      }
      product.stock -= stockToReverse;
      final remaining = incomingSupplies
          .where((other) => other.id != id &&
              (other.productId == product.id ||
                  (other.productId.isEmpty &&
                      other.product.toLowerCase() == product.name.toLowerCase())))
          .toList();
      if (remaining.isEmpty) {
        product.lastIncomingDate = null;
      } else {
        remaining.sort((a, b) => b.date.compareTo(a.date));
        product.lastIncomingDate = remaining.first.date;
      }
    }

    paymentTransactions.removeWhere(
      (payment) => payment.linkedType == 'supply' && payment.linkedId == id,
    );
    incomingSupplies.removeAt(index);

    if (!await save()) {
      throw StateError('Incoming product deletion could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> updateIncomingSupplyPayment(
    String id,
    double paidAmount, {
    DateTime? paymentDate,
    String? method,
  }) async {
    final idx = incomingSupplies.indexWhere((x) => x.id == id);
    if (idx < 0) return;
    final supply = incomingSupplies[idx];
    final current = paidForSupply(id);
    final target = paidAmount.clamp(0, supply.total).toDouble();
    final delta = target - current;
    if (delta.abs() > 0.000001) {
      paymentTransactions.add(
        PaymentTransaction(
          id: newId(),
          linkedType: 'supply',
          linkedId: id,
          amount: delta,
          date: paymentDate ?? DateTime.now(),
          method: method ?? '',
          note: delta >= 0 ? 'Supplier payment' : 'Supplier payment adjustment',
        ),
      );
    } else if (paymentDate != null) {
      supply.paymentDate = paymentDate;
    }
    supply.paidAmount = paidForSupply(id);
    supply.paymentDate = paymentDate ?? supply.paymentDate;
    if (!await save()) {
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }

  // ---- Sales ----
  Future<void> addSale(Sale sale, List<SaleItem> items) async {
    if (items.isEmpty) {
      throw StateError('A sale must contain at least one item.');
    }

    final resolved = <SaleItem, Product>{};
    final inventoryByProduct = <SaleItem, Product>{};
    final requestedByInventoryProduct = <String, double>{};

    for (final item in items) {
      if (item.quantity <= 0) {
        throw StateError('Quantity for ${item.product} must be greater than zero.');
      }
      final product = _productForSaleItem(item);
      if (product == null) {
        throw StateError(
          'Product "${item.product}" could not be matched to the product catalog.',
        );
      }

      final inventoryProduct = inventoryProductForSale(product);
      if (inventoryProduct == null) {
        throw StateError(
          'Product "${product.name}" is linked to a missing parent stock product.',
        );
      }

      final deduction = stockConsumptionForSale(
        product,
        item.quantity,
        saleUnit: item.saleUnit,
      );
      if (deduction <= 0) {
        throw StateError('The stock conversion for "${product.name}" is invalid.');
      }

      final requested =
          (requestedByInventoryProduct[inventoryProduct.id] ?? 0) + deduction;
      requestedByInventoryProduct[inventoryProduct.id] = requested;

      if (requested > inventoryProduct.stock + 0.000001) {
        throw StateError(
          'Not enough stock for "${inventoryProduct.name}". '
          'Available: ${_formatNumber(inventoryProduct.stock)} ${inventoryProduct.measurement}, '
          'required: ${_formatNumber(requested)} ${inventoryProduct.measurement}.',
        );
      }

      resolved[item] = product;
      inventoryByProduct[item] = inventoryProduct;
    }

    sale.paid = sale.paid.clamp(0, double.infinity).toDouble();
    sales.add(sale);

    for (final item in items) {
      final productData = resolved[item]!;
      final inventoryProduct = inventoryByProduct[item]!;
      final deduction = stockConsumptionForSale(
        productData,
        item.quantity,
        saleUnit: item.saleUnit,
      );

      item.saleVoucherNumber = sale.voucherNumber;
      item.productId = productData.id;
      item.inventoryProductId = inventoryProduct.id;
      item.stockDeduction = deduction;
      item.profit =
          item.amount - costAmountForSale(productData, item.quantity, saleUnit: item.saleUnit);

      saleItems.add(item);
      inventoryProduct.stock -= deduction;
    }

    if (sale.paid > 0) {
      final total = totalForSale(sale.voucherNumber);
      final initialPaid = sale.paid.clamp(0, total).toDouble();
      paymentTransactions.add(
        PaymentTransaction(
          id: newId(),
          linkedType: 'sale',
          linkedId: sale.voucherNumber,
          amount: initialPaid,
          date: sale.paymentDate ?? DateTime.now(),
          method: sale.paymentMethod,
          note: 'Initial customer payment',
        ),
      );
      sale.paid = paidForSale(sale.voucherNumber);
      sale.paymentDate = sale.paymentDate ?? DateTime.now();
    } else {
      sale.paid = 0;
    }

    if (!await save()) {
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> addVoucher(Sale sale, List<SaleItem> items) =>
      addSale(sale, items);

  Future<void> updateSalePayment(
    String voucherNumber, {
    required double paid,
    String? paymentMethod,
    DateTime? date,
    String? customer,
    DateTime? paymentDate,
  }) async {
    final idx = sales.indexWhere((s) => s.voucherNumber == voucherNumber);
    if (idx < 0) return;
    final sale = sales[idx];
    final total = totalForSale(voucherNumber);
    final target = paid.clamp(0, total).toDouble();
    final current = paidForSale(voucherNumber);
    final delta = target - current;

    if (delta.abs() > 0.000001) {
      paymentTransactions.add(
        PaymentTransaction(
          id: newId(),
          linkedType: 'sale',
          linkedId: voucherNumber,
          amount: delta,
          date: paymentDate ?? DateTime.now(),
          method: paymentMethod ?? sale.paymentMethod,
          note: delta >= 0 ? 'Customer payment' : 'Customer payment adjustment',
        ),
      );
      sale.paymentDate = paymentDate ?? DateTime.now();
    } else if (paymentDate != null) {
      sale.paymentDate = paymentDate;
    }

    sale.paid = paidForSale(voucherNumber);
    if (paymentMethod != null) sale.paymentMethod = paymentMethod;
    if (date != null) sale.date = date;
    if (customer != null) sale.customer = customer;
    if (!await save()) {
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> deleteSale(String voucherNumber) async {
    final items = itemsForSale(voucherNumber);
    for (final item in items) {
      Product? inventoryProduct;
      if (item.inventoryProductId.isNotEmpty) {
        inventoryProduct = productById(item.inventoryProductId);
      }
      inventoryProduct ??= () {
        final selected = _productForSaleItem(item);
        return selected == null ? null : inventoryProductForSale(selected);
      }();

      if (inventoryProduct != null) {
        final deduction = item.stockDeduction > 0
            ? item.stockDeduction
            : stockConsumptionForSale(
                _productForSaleItem(item) ?? inventoryProduct,
                item.quantity,
                saleUnit: item.saleUnit,
              );
        inventoryProduct.stock += deduction;
      }
    }
    sales.removeWhere((s) => s.voucherNumber == voucherNumber);
    saleItems.removeWhere((i) => i.saleVoucherNumber == voucherNumber);
    paymentTransactions.removeWhere(
      (p) => p.linkedType == 'sale' && p.linkedId == voucherNumber,
    );
    if (!await save()) {
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> deleteVoucher(String voucherNumber) => deleteSale(voucherNumber);

  List<SaleItem> itemsForSale(String voucherNumber) =>
      saleItems.where((i) => i.saleVoucherNumber == voucherNumber).toList();

  double totalForSale(String voucherNumber) =>
      itemsForSale(voucherNumber).fold(0.0, (sum, i) => sum + i.amount);

  List<LedgerEntry> _buildPayYanEntries() {
    final result = <LedgerEntry>[];

    for (final supply in incomingSupplies) {
      final amount = supply.total - paidForSupply(supply.id);
      if (amount <= 0.005) continue;

      result.add(
        LedgerEntry(
          id: 'supply:${supply.id}',
          name: supply.supplier.isEmpty ? 'Supplier' : supply.supplier,
          note: '${supply.product} • Qty ${_formatNumber(supply.quantity)} • Total ${_formatNumber(supply.total)} • Paid ${_formatNumber(paidForSupply(supply.id))}',
          amount: amount,
          date: supply.date,
          type: 'payable',
        ),
      );
    }

    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  List<LedgerEntry> _buildYaYanEntries() {
    final result = <LedgerEntry>[];

    for (final sale in sales) {
      final total = totalForSale(sale.voucherNumber);
      final balance = total - paidForSale(sale.voucherNumber);
      if (balance <= 0.005) continue;

      result.add(
        LedgerEntry(
          id: 'sale:${sale.voucherNumber}',
          name: sale.customer.isEmpty ? 'Customer' : sale.customer,
          note: 'Voucher ${sale.voucherNumber} • Paid ${_formatNumber(paidForSale(sale.voucherNumber))} / ${_formatNumber(total)}',
          amount: balance,
          date: sale.date,
          type: 'receivable',
        ),
      );
    }

    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  List<LedgerEntry> _buildCashEntries() {
    final result = <LedgerEntry>[...incomeExpenseEntries];

    for (final payment in paymentTransactions) {
      Sale? sale;
      IncomingSupply? supply;
      if (payment.linkedType == 'sale') {
        for (final candidate in sales) {
          if (candidate.voucherNumber == payment.linkedId) {
            sale = candidate;
            break;
          }
        }
      } else if (payment.linkedType == 'supply') {
        for (final candidate in incomingSupplies) {
          if (candidate.id == payment.linkedId) {
            supply = candidate;
            break;
          }
        }
      }

      if (payment.linkedType == 'sale' && sale == null) continue;
      if (payment.linkedType == 'supply' && supply == null) continue;

      if (payment.linkedType == 'sale') {
        result.add(
          LedgerEntry(
            id: 'payment:${payment.id}',
            name: sale!.customer.isEmpty ? 'Customer sale' : sale.customer,
            note: 'Sale ${sale.voucherNumber}${payment.method.isNotEmpty ? ' • ${payment.method}' : ''}${payment.note.isNotEmpty ? ' • ${payment.note}' : ''}',
            amount: payment.amount,
            date: payment.date,
            type: 'income',
          ),
        );
      } else if (payment.linkedType == 'supply') {
        result.add(
          LedgerEntry(
            id: 'payment:${payment.id}',
            name: supply!.supplier.isEmpty ? 'Supplier payment' : supply.supplier,
            note: 'Purchase ${supply.product}${payment.method.isNotEmpty ? ' • ${payment.method}' : ''}${payment.note.isNotEmpty ? ' • ${payment.note}' : ''}',
            amount: payment.amount,
            date: payment.date,
            type: 'expense',
          ),
        );
      }
    }

    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  static String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  Future<void> addIncomeExpense(LedgerEntry e) async {
    incomeExpenseEntries.add(e);

    if (e.type == 'expense') {
      expenses.add(
        Expense(
          id: e.id,
          date: e.date,
          reason: e.name,
          amount: e.amount,
        ),
      );
    }

    if (!await save()) {
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> removeIncomeExpense(String id) async {
    LedgerEntry? entry;
    for (final candidate in incomeExpenseEntries) {
      if (candidate.id == id) {
        entry = candidate;
        break;
      }
    }
    incomeExpenseEntries.removeWhere((x) => x.id == id);

    if (entry != null && entry.type == 'expense') {
      final expenseIndex = expenses.indexWhere((e) => e.id == entry!.id);
      if (expenseIndex >= 0) expenses.removeAt(expenseIndex);
    }

    if (!await save()) {
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> addCylinderType(CylinderType type) async {
    type.name = type.name.trim();
    type.baseType = type.baseType.trim().toLowerCase();
    if (type.id.isEmpty) type.id = newId();
    if (!type.totalQuantity.isFinite || type.totalQuantity < 0) {
      throw StateError('Cylinder stock cannot be negative. Enter 0 or more.');
    }
    if (type.name.isEmpty) {
      throw StateError('Cylinder type name cannot be empty.');
    }
    if (type.baseType != '48kg' && type.baseType != '10v') {
      throw StateError('Cylinder category must be 48 kg or 10v.');
    }
    final duplicate = cylinderTypes.any(
      (existing) => existing.baseType == type.baseType &&
          existing.name.toLowerCase() == type.name.toLowerCase(),
    );
    if (duplicate) {
      throw StateError('A cylinder type with this name already exists in this category.');
    }
    cylinderTypes.add(type);
    if (!await save()) {
      throw StateError('Cylinder type could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> deleteCylinderType(String id) async {
    if (!cylinderTypes.any((type) => type.id == id)) return;
    final used = cylinderCycles.any((cycle) => cycle.cylinderTypeId == id);
    if (used) {
      throw StateError(
        'This cylinder type is already used by Cylinder Cycles and cannot be deleted. Delete those cycle records first.',
      );
    }
    cylinderTypes.removeWhere((type) => type.id == id);
    if (cylinderTypes.isEmpty) {
      _ensureDefaultCylinderTypes();
    }
    if (!await save()) {
      throw StateError('Cylinder type deletion could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> updateCylinderTypeTotalQuantity(
    String id,
    double quantity,
  ) async {
    if (!quantity.isFinite || quantity < 0) {
      throw StateError('Cylinder stock cannot be negative. Enter 0 or more.');
    }
    final type = cylinderTypeById(id);
    if (type == null) {
      throw StateError('Cylinder type not found.');
    }

    final oldQuantity = type.totalQuantity;
    type.totalQuantity = quantity;
    if (!await save()) {
      type.totalQuantity = oldQuantity;
      throw StateError('Cylinder quantity could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> addCylinderCycle(CylinderCycle cycle) async {
    if (cycle.id.isEmpty) cycle.id = newId();
    if (!cycle.givenQuantity.isFinite || !cycle.receivedQuantity.isFinite ||
        cycle.givenQuantity < 0 || cycle.receivedQuantity < 0) {
      throw StateError('Cylinder quantities cannot be negative.');
    }

    final type = cylinderTypeById(cycle.cylinderTypeId);
    final oldQuantity = type?.totalQuantity;

    if (type == null) {
      throw StateError('Cylinder type not found.');
    }

    final newQuantity = type.totalQuantity +
        cycle.receivedQuantity - cycle.givenQuantity;
    if (newQuantity < -0.000001) {
      throw StateError(
        'Insufficient ${type.name} stock. Available: '
        '${type.totalQuantity}, trying to give: ${cycle.givenQuantity}.',
      );
    }

    cylinderCycles.add(cycle);
    type.totalQuantity = newQuantity < 0 ? 0 : newQuantity;

    if (!await save()) {
      cylinderCycles.removeWhere((item) => item.id == cycle.id);
      if (oldQuantity != null) {
        type.totalQuantity = oldQuantity;
      }
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> deleteCylinderCycle(String id) async {
    final index = cylinderCycles.indexWhere((cycle) => cycle.id == id);
    if (index < 0) return;

    final cycle = cylinderCycles[index];
    final type = cylinderTypeById(cycle.cylinderTypeId);
    final oldQuantity = type?.totalQuantity;

    cylinderCycles.removeAt(index);
    if (type != null) {
      final restoredQuantity =
          type.totalQuantity + cycle.givenQuantity - cycle.receivedQuantity;
      type.totalQuantity = restoredQuantity < 0 ? 0 : restoredQuantity;
    }

    if (!await save()) {
      cylinderCycles.insert(index, cycle);
      if (oldQuantity != null) {
        type?.totalQuantity = oldQuantity;
      }
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }

  Future<void> saveCylinderRows() async {
    if (!await save()) {
      throw StateError('Data could not be saved. Your previous saved data was kept.');
    }
  }
}

// =====================================================================
// DASHBOARD
// =====================================================================

class _DashboardPageButton {
  const _DashboardPageButton({
    required this.pageKey,
    required this.labelKey,
    required this.icon,
  });

  /// Internal navigation identifier. This is never shown to the user.
  final String pageKey;

  /// Translation key / English copy that is actually rendered by the button.
  final String labelKey;

  final IconData icon;
}

class PosDashboardScreen extends StatelessWidget {
  const PosDashboardScreen({super.key});

  static const Color primaryGreen = Color(0xFF0F6E3F);
  static const Color sidebarBg = Color(0xFFE2EBE4);
  static const Color cardBg = Color(0xFFE0E8E1);
  static const Color textColor = Colors.black87;

  void _openPage(BuildContext context, String pageKey) {
    late final Widget targetScreen;

    switch (pageKey) {
      case 'Pay Yan':
        targetScreen = const PayYanPage(title: 'Pay Yan');
        break;
      case 'Ya Yan':
        targetScreen = const YaYanPage(title: 'Ya Yan');
        break;
      case 'Data Backup':
        targetScreen = const DataBackupPage(title: 'Data Backup');
        break;
      case 'Products':
        targetScreen = const ProductCatalogPage(title: 'Products');
        break;
      case 'Instock Products':
        targetScreen = const InStockProductsPage(title: 'In-stock Products');
        break;
      case 'Incoming Products':
        targetScreen = const IncomingProductsPage(title: 'Incoming Products');
        break;
      case 'Sale':
        targetScreen = const SalePage(title: 'Sale');
        break;
      case 'Customer':
        targetScreen = const CustomerPage(title: 'Customer');
        break;
      case 'Vouchers':
        targetScreen = const VouchersPage(title: 'Vouchers');
        break;
      case 'Income/Expense':
        targetScreen = const IncomeExpensePage(title: 'Income/Expense');
        break;
      case 'Sales Report':
        targetScreen = const SalesReportPage(title: 'Sales Report');
        break;
      case 'Cylinder Cycles':
        targetScreen = const CylinderCyclesPage(title: 'Cylinder Cycles');
        break;
      case 'Cylinder Types':
        targetScreen = const CylinderTypesPage(title: 'Cylinder Types');
        break;
      default:
        return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => targetScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the dashboard whenever the language changes so the button labels,
    // title, drawer, and language tooltip update immediately.
    return ValueListenableBuilder<String>(
      valueListenable: UiTranslation.language,
      builder: (context, language, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final bool isPhone = constraints.maxWidth < 600;

            return Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                titleSpacing: 8,
                leading: Builder(
                  builder: (context) => IconButton(
                    tooltip: uiT('Open menu'),
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
                title: Row(
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      width: isPhone ? 38 : 44,
                      height: isPhone ? 38 : 44,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.storefront, size: 34),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        uiT('Kyal Sin Lay Energy & Tech'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isPhone ? 15 : 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: UiTranslation.languageButtonTooltip,
                    icon: const Icon(Icons.translate),
                    onPressed: () => UiTranslation.toggle(),
                  ),
                  const SizedBox(width: 4),
                ],
              ),

              drawer: Drawer(
                backgroundColor: sidebarBg,
                child: SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                        child: Text(
                          uiT('Point of Sale System'),
                          style: const TextStyle(
                            color: primaryGreen,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      _buildDrawerItem(
                        context,
                        const _DashboardPageButton(
                          pageKey: 'Pay Yan',
                          labelKey: 'Pay Yan',
                          icon: Icons.payments_outlined,
                        ),
                      ),
                      _buildDrawerItem(
                        context,
                        const _DashboardPageButton(
                          pageKey: 'Ya Yan',
                          labelKey: 'Ya Yan',
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      ),
                      _buildDrawerItem(
                        context,
                        const _DashboardPageButton(
                          pageKey: 'Products',
                          labelKey: 'Products',
                          icon: Icons.category_outlined,
                        ),
                      ),
                      _buildDrawerItem(
                        context,
                        const _DashboardPageButton(
                          pageKey: 'Incoming Products',
                          labelKey: 'Incoming Products',
                          icon: Icons.local_shipping_outlined,
                        ),
                      ),
                      _buildDrawerItem(
                        context,
                        const _DashboardPageButton(
                          pageKey: 'Customer',
                          labelKey: 'Customer',
                          icon: Icons.people_outline,
                        ),
                      ),
                      _buildDrawerItem(
                        context,
                        const _DashboardPageButton(
                          pageKey: 'Vouchers',
                          labelKey: 'Vouchers',
                          icon: Icons.confirmation_number_outlined,
                        ),
                      ),
                      _buildDrawerItem(
                        context,
                        const _DashboardPageButton(
                          pageKey: 'Income/Expense',
                          labelKey: 'Income/Expense',
                          icon: Icons.account_balance_outlined,
                        ),
                      ),
                      _buildDrawerItem(
                        context,
                        const _DashboardPageButton(
                          pageKey: 'Sales Report',
                          labelKey: 'Sales Report',
                          icon: Icons.assessment_outlined,
                        ),
                      ),
                      _buildDrawerItem(
                        context,
                        const _DashboardPageButton(
                          pageKey: 'Cylinder Types',
                          labelKey: 'Cylinder Types',
                          icon: Icons.propane_tank_outlined,
                        ),
                      ),
                      _buildDrawerItem(
                        context,
                        const _DashboardPageButton(
                          pageKey: 'Data Backup',
                          labelKey: 'Data Backup',
                          icon: Icons.backup_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              body: SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isPhone ? 16 : 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        children: [
                          if (AppData.instance.loadError != null)
                            Card(
                              color: Colors.red.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        uiError(AppData.instance.loadError!),
                                        style: const TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Text.rich(
                            TextSpan(
                              style: TextStyle(
                                fontSize: isPhone ? 18 : 22,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                              children: [
                                TextSpan(text: uiT('Welcome from ')),
                                TextSpan(
                                  text: uiT(
                                    'Kyal Sin Lay Energy & Tech Point of Sale System',
                                  ),
                                  style: const TextStyle(color: primaryGreen),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          LayoutBuilder(
                            builder: (context, gridConstraints) {
                              final width = gridConstraints.maxWidth;

                              final int columns = width < 520
                                  ? 1
                                  : width < 850
                                      ? 2
                                      : 3;

                              const pageButtons = <_DashboardPageButton>[
                                _DashboardPageButton(
                                  // Keep the legacy route key separate from
                                  // the exact text/translation key shown.
                                  pageKey: 'Instock Products',
                                  labelKey: 'In-stock Products',
                                  icon: Icons.inventory_2_outlined,
                                ),
                                _DashboardPageButton(
                                  pageKey: 'Sale',
                                  labelKey: 'Sale',
                                  icon: Icons.point_of_sale_outlined,
                                ),
                                _DashboardPageButton(
                                  pageKey: 'Cylinder Cycles',
                                  labelKey: 'Cylinder Cycles',
                                  icon: Icons.propane_tank_outlined,
                                ),
                              ];

                              return GridView.count(
                                crossAxisCount: columns,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                childAspectRatio: isPhone ? 2.4 : 1.45,
                                children: [
                                  for (final pageButton in pageButtons)
                                    _buildMenuCard(context, pageButton),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDrawerItem(
    BuildContext context,
    _DashboardPageButton pageButton,
  ) {
    return ListTile(
      leading: Icon(pageButton.icon, color: primaryGreen),
      title: Text(
        uiT(pageButton.labelKey),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      onTap: () {
        Navigator.pop(context);
        _openPage(context, pageButton.pageKey);
      },
    );
  }

  Widget _buildMenuCard(
    BuildContext context,
    _DashboardPageButton pageButton,
  ) {
    return Card(
      color: cardBg,
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openPage(context, pageButton.pageKey),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                pageButton.icon,
                size: 30,
                color: primaryGreen,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  uiT(pageButton.labelKey),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    height: 1.2,
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

// =====================================================================
// PAY YAN / YA YAN / INCOME & EXPENSE
// =====================================================================

class PayYanPage extends StatefulWidget {
  const PayYanPage({super.key, required this.title});
  final String title;
  @override State<PayYanPage> createState() => _PayYanPageState();
}

class _PayYanPageState extends State<PayYanPage> {
  Future<void> _pay(IncomingSupply supply) async {
    final amountCtrl = TextEditingController(text: supply.balance.toStringAsFixed(2));
    String method = 'Cash';
    DateTime date = DateTime.now();
    final value = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(uiF('Pay {supplier}', {'supplier': supply.supplier.isEmpty ? uiT('Supplier') : supply.supplier})),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(uiF('Outstanding: {balance}', {'balance': supply.balance.toStringAsFixed(2)}), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: uiT('Payment amount')),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: InputDecoration(labelText: uiT('Payment method')),
                items: [
                  DropdownMenuItem(value: 'Cash', child: Text(uiT('Cash'))),
                  DropdownMenuItem(value: 'Bank', child: Text(uiT('Bank'))),
                  DropdownMenuItem(value: 'Mobile', child: Text(uiT('Mobile'))),
                ],
                onChanged: (v) => setDialogState(() => method = v ?? 'Cash'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setDialogState(() => date = picked);
                },
                icon: const Icon(Icons.calendar_today),
                label: Text(uiF('Payment date {date}', {'date': _formatDateOnly(date)})),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(uiT('Cancel'))),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                if (amount <= 0 || amount > supply.balance + 0.005) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(uiT('Enter an amount within the outstanding balance.'))));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(uiT('Save payment')),
            ),
          ],
        ),
      ),
    );
    if (value != true) {
      amountCtrl.dispose();
      return;
    }
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    await AppData.instance.updateIncomingSupplyPayment(
      supply.id,
      supply.paidAmount + amount,
      paymentDate: date,
      method: method,
    );
    amountCtrl.dispose();
    if (mounted) setState(() {});
  }

  void _history(IncomingSupply supply) {
    final payments = AppData.instance.paymentsForSupply(supply.id);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(uiF('{supplier} • {product}', {'supplier': supply.supplier.isEmpty ? uiT('Supplier') : supply.supplier, 'product': supply.product})),
        content: SizedBox(
          width: 460,
          child: payments.isEmpty
              ? Text(uiT('No payment transactions recorded.'))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: payments.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = payments[i];
                    final label = p.amount >= 0 ? 'Paid' : 'Adjustment';
                    return ListTile(
                      dense: true,
                      leading: Icon(p.amount >= 0 ? Icons.arrow_upward : Icons.undo, color: p.amount >= 0 ? Colors.red : Colors.orange),
                      title: Text(uiF('{label} {amount}', {'label': uiT(label), 'amount': p.amount.abs().toStringAsFixed(2)})),
                      subtitle: Text('${_formatDateOnly(p.date)}${p.method.isNotEmpty ? ' • ${uiT(p.method)}' : ''}${p.note.isNotEmpty ? ' • ${uiLedgerNote(p.note)}' : ''}'),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(uiT('Close')))],
      ),
    );
  }

  @override Widget build(BuildContext context) {
    final supplies = AppData.instance.incomingSupplies.where((s) => AppData.instance.paidForSupply(s.id) < s.total - .005).toList()..sort((a,b) => b.date.compareTo(a.date));
    final total = supplies.fold(0.0, (sum,s) => sum + (s.total - AppData.instance.paidForSupply(s.id)).clamp(0, double.infinity).toDouble());
    return Scaffold(
      appBar: AppBar(title: Text(uiT(widget.title)), backgroundColor: PosDashboardScreen.primaryGreen, foregroundColor: Colors.white),
      body: Column(children: [
        _ledgerTotal(uiF('Total to Pay: {amount}', {'amount': total.toStringAsFixed(2)}), Colors.redAccent),
        Expanded(
          child: supplies.isEmpty
              ? Center(child: Text(uiT('Nothing to pay. All supplier balances are settled.')))
              : ListView.builder(
                  itemCount: supplies.length,
                  itemBuilder: (_, i) {
                    final s = supplies[i];
                    final paid = AppData.instance.paidForSupply(s.id);
                    final balance = (s.total - paid).clamp(0, double.infinity).toDouble();
                    return ListTile(
                      leading: const Icon(Icons.arrow_upward, color: Colors.redAccent),
                      title: Text(s.supplier.isEmpty ? uiT('Supplier') : s.supplier),
                      subtitle: Text('${s.product} • ${_formatDateOnly(s.date)}\n${uiF('Paid {paid} / {total} • Balance {balance}', {'paid': paid.toStringAsFixed(2), 'total': s.total.toStringAsFixed(2), 'balance': balance.toStringAsFixed(2)})}'),
                      isThreeLine: true,
                      trailing: Wrap(spacing: 4, children: [
                        IconButton(onPressed: () => _history(s), icon: const Icon(Icons.history), tooltip: uiT('Payment history')),
                        FilledButton(onPressed: () => _pay(s), child: Text(uiT('Pay'))),
                      ]),
                    );
                  },
                ),
        )
      ]),
    );
  }

  Widget _ledgerTotal(String text, Color color) => Container(width: double.infinity, color: color.withValues(alpha: .12), padding: const EdgeInsets.all(16), child: Text(text, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)));
}

class YaYanPage extends StatefulWidget {
  const YaYanPage({super.key, required this.title});
  final String title;
  @override State<YaYanPage> createState() => _YaYanPageState();
}

class _YaYanPageState extends State<YaYanPage> {
  Future<void> _receive(Sale sale) async {
    final total = AppData.instance.totalForSale(sale.voucherNumber);
    final currentPaid = AppData.instance.paidForSale(sale.voucherNumber);
    final balance = total - currentPaid;
    final amountCtrl = TextEditingController(text: balance.toStringAsFixed(2));
    String method = sale.paymentMethod.isEmpty ? 'Cash' : sale.paymentMethod;
    DateTime date = DateTime.now();
    final value = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(uiF('Receive from {customer}', {'customer': sale.customer.isEmpty ? uiT('Customer') : sale.customer})),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(uiF('Outstanding: {balance}', {'balance': balance.toStringAsFixed(2)}), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: uiT('Payment amount'))),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: InputDecoration(labelText: uiT('Payment method')),
                items: [
                  DropdownMenuItem(value: 'Cash', child: Text(uiT('Cash'))),
                  DropdownMenuItem(value: 'Bank', child: Text(uiT('Bank'))),
                  DropdownMenuItem(value: 'Mobile', child: Text(uiT('Mobile'))),
                  DropdownMenuItem(value: 'Credit', child: Text(uiT('Credit'))),
                ],
                onChanged: (v) => setDialogState(() => method = v ?? 'Cash'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (picked != null) setDialogState(() => date = picked);
                },
                icon: const Icon(Icons.calendar_today),
                label: Text(uiF('Payment date {date}', {'date': _formatDateOnly(date)})),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(uiT('Cancel'))),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                if (amount <= 0 || amount > balance + 0.005) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(uiT('Enter an amount within the outstanding balance.'))));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(uiT('Save payment')),
            ),
          ],
        ),
      ),
    );
    if (value != true) {
      amountCtrl.dispose();
      return;
    }
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    await AppData.instance.updateSalePayment(
      sale.voucherNumber,
      paid: currentPaid + amount,
      paymentMethod: method,
      paymentDate: date,
    );
    amountCtrl.dispose();
    if (mounted) setState(() {});
  }

  void _history(Sale sale) {
    final payments = AppData.instance.paymentsForSale(sale.voucherNumber);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(uiF('{customer} • Voucher {voucher}', {'customer': sale.customer.isEmpty ? uiT('Customer') : sale.customer, 'voucher': sale.voucherNumber})),
        content: SizedBox(
          width: 460,
          child: payments.isEmpty
              ? Text(uiT('No payment transactions recorded.'))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: payments.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = payments[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(p.amount >= 0 ? Icons.arrow_downward : Icons.undo, color: p.amount >= 0 ? Colors.teal : Colors.orange),
                      title: Text(uiF('{label} {amount}', {'label': p.amount >= 0 ? uiT('Received') : uiT('Adjustment'), 'amount': p.amount.abs().toStringAsFixed(2)})),
                      subtitle: Text('${_formatDateOnly(p.date)}${p.method.isNotEmpty ? ' • ${uiT(p.method)}' : ''}${p.note.isNotEmpty ? ' • ${uiLedgerNote(p.note)}' : ''}'),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(uiT('Close')))],
      ),
    );
  }

  @override Widget build(BuildContext context) {
    final sales = AppData.instance.sales.where((s) => AppData.instance.totalForSale(s.voucherNumber) - AppData.instance.paidForSale(s.voucherNumber) > .005).toList()..sort((a,b) => b.date.compareTo(a.date));
    final total = sales.fold(0.0, (sum,s) => sum + (AppData.instance.totalForSale(s.voucherNumber) - AppData.instance.paidForSale(s.voucherNumber)).clamp(0, double.infinity).toDouble());
    return Scaffold(appBar: AppBar(title: Text(uiT(widget.title)), backgroundColor: PosDashboardScreen.primaryGreen, foregroundColor: Colors.white), body: Column(children: [
      _ledgerTotal(uiF('Total to Receive: {amount}', {'amount': total.toStringAsFixed(2)}), Colors.teal),
      Expanded(child: sales.isEmpty ? Center(child: Text(uiT('Nothing to receive. All customer balances are settled.'))) : ListView.builder(itemCount: sales.length, itemBuilder: (_,i) {
        final s=sales[i];
        final total=AppData.instance.totalForSale(s.voucherNumber);
        final paid=AppData.instance.paidForSale(s.voucherNumber);
        final balance=(total-paid).clamp(0,double.infinity).toDouble();
        return ListTile(
          leading: const Icon(Icons.arrow_downward, color: Colors.teal),
          title: Text(s.customer.isEmpty ? uiT('Customer') : s.customer),
          subtitle: Text('${uiF('Voucher {voucher} • {date}', {'voucher': s.voucherNumber, 'date': _formatDateOnly(s.date)})}\n${uiF('Paid {paid} / {total} • Balance {balance}', {'paid': paid.toStringAsFixed(2), 'total': total.toStringAsFixed(2), 'balance': balance.toStringAsFixed(2)})}'),
          isThreeLine: true,
          trailing: Wrap(spacing: 4, children: [
            IconButton(onPressed: () => _history(s), icon: const Icon(Icons.history), tooltip: uiT('Payment history')),
            FilledButton(onPressed: () => _receive(s), child: Text(uiT('Receive'))),
          ]),
        );
      }))
    ]));
  }

  Widget _ledgerTotal(String text, Color color) => Container(width: double.infinity, color: color.withValues(alpha: .12), padding: const EdgeInsets.all(16), child: Text(text, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)));
}

class IncomeExpensePage extends StatefulWidget {
  const IncomeExpensePage({super.key, required this.title});

  final String title;

  @override
  State<IncomeExpensePage> createState() => _IncomeExpensePageState();
}

class _IncomeExpensePageState extends State<IncomeExpensePage> {
  String _period = 'Daily';
  DateTime _selectedDate = DateTime.now();
  DateTime _selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  int _selectedYear = DateTime.now().year;

  static const List<String> _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _matchesPeriod(DateTime date) {
    switch (_period) {
      case 'Monthly':
        return date.year == _selectedMonth.year &&
            date.month == _selectedMonth.month;
      case 'Yearly':
        return date.year == _selectedYear;
      case 'Daily':
      default:
        return _sameDate(date, _selectedDate);
    }
  }

  String _formatDate(DateTime date) => _formatDateOnly(date);

  String _formatMonth(DateTime month) =>
      '${uiT(_monthNames[month.month - 1])} ${month.year}';

  String _periodValueLabel() {
    switch (_period) {
      case 'Monthly':
        return _formatMonth(_selectedMonth);
      case 'Yearly':
        return _selectedYear.toString();
      case 'Daily':
      default:
        return _formatDate(_selectedDate);
    }
  }

  String _periodLabel() =>
      uiF('Showing {period}', {'period': _periodValueLabel()});

  Future<void> _selectDailyDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: uiT('Select transaction date'),
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _selectedMonth = DateTime(picked.year, picked.month);
        _selectedYear = picked.year;
      });
    }
  }

  Future<void> _selectMonth() async {
    int tempYear = _selectedMonth.year;
    int tempMonth = _selectedMonth.month;

    final selected = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(uiT('Select Month')),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: tempYear,
                      decoration: InputDecoration(
                        labelText: uiT('Year'),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (int year = 2000; year <= 2100; year++)
                          DropdownMenuItem<int>(
                            value: year,
                            child: Text('$year'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => tempYear = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      itemCount: 12,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 2.3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemBuilder: (_, index) {
                        final month = index + 1;
                        final selected = month == tempMonth;
                        return OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: selected
                                ? PosDashboardScreen.primaryGreen
                                    .withValues(alpha: .12)
                                : null,
                          ),
                          onPressed: () {
                            setDialogState(() => tempMonth = month);
                          },
                          child: Text(uiT(_monthNames[index])),
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(uiT('Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    DateTime(tempYear, tempMonth),
                  ),
                  child: Text(uiT('Select')),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedMonth = DateTime(selected.year, selected.month);
        _selectedYear = selected.year;
        _selectedDate = selected;
      });
    }
  }

  Future<void> _selectYear() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        int tempYear = _selectedYear;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(uiT('Select Year')),
              content: DropdownButtonFormField<int>(
                initialValue: tempYear,
                decoration: InputDecoration(
                  labelText: uiT('Year'),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (int year = 2000; year <= 2100; year++)
                    DropdownMenuItem<int>(
                      value: year,
                      child: Text('$year'),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => tempYear = value);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(uiT('Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, tempYear),
                  child: Text(uiT('Select')),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedYear = selected;
        _selectedMonth = DateTime(selected, _selectedMonth.month);
        _selectedDate = DateTime(selected, _selectedDate.month, _selectedDate.day);
      });
    }
  }

  void _changePeriod(int direction) {
    setState(() {
      switch (_period) {
        case 'Monthly':
          _selectedMonth = DateTime(
            _selectedMonth.year,
            _selectedMonth.month + direction,
          );
          _selectedYear = _selectedMonth.year;
          _selectedDate = _selectedMonth;
          break;
        case 'Yearly':
          _selectedYear += direction;
          _selectedMonth = DateTime(_selectedYear, _selectedMonth.month);
          _selectedDate = DateTime(
            _selectedYear,
            _selectedDate.month,
            _selectedDate.day,
          );
          break;
        case 'Daily':
        default:
          _selectedDate = _selectedDate.add(Duration(days: direction));
          _selectedMonth = DateTime(_selectedDate.year, _selectedDate.month);
          _selectedYear = _selectedDate.year;
          break;
      }
    });
  }

  void _jumpToToday() {
    final today = DateTime.now();
    setState(() {
      _selectedDate = today;
      _selectedMonth = DateTime(today.year, today.month);
      _selectedYear = today.year;
    });
  }

  Widget _periodSelector() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'Daily', label: Text(uiT('Daily'))),
                ButtonSegment(value: 'Monthly', label: Text(uiT('Monthly'))),
                ButtonSegment(value: 'Yearly', label: Text(uiT('Yearly'))),
              ],
              selected: {_period},
              onSelectionChanged: (selection) {
                setState(() => _period = selection.first);
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  tooltip: uiT('Previous period'),
                  onPressed: () => _changePeriod(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      switch (_period) {
                        case 'Monthly':
                          _selectMonth();
                          break;
                        case 'Yearly':
                          _selectYear();
                          break;
                        case 'Daily':
                        default:
                          _selectDailyDate();
                          break;
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _period == 'Daily'
                                ? Icons.calendar_today_outlined
                                : _period == 'Monthly'
                                    ? Icons.calendar_month_outlined
                                    : Icons.event_repeat_outlined,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _periodLabel(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: uiT('Next period'),
                  onPressed: () => _changePeriod(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: _jumpToToday,
                  child: Text(uiT('Today')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _grossProfit() {
    double total = 0;
    for (final item in AppData.instance.saleItems) {
      Sale? sale;
      for (final candidate in AppData.instance.sales) {
        if (candidate.voucherNumber == item.saleVoucherNumber) {
          sale = candidate;
          break;
        }
      }
      if (sale != null && _matchesPeriod(sale.date)) {
        total += item.profit;
      }
    }
    return total;
  }

  List<LedgerEntry> _transactions() {
    final entries = AppData.instance.cashEntries
        .where((entry) => _matchesPeriod(entry.date))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  double _manualExpenses() {
    return AppData.instance.incomeExpenseEntries
        .where((entry) =>
            entry.type == 'expense' && _matchesPeriod(entry.date))
        .fold(0.0, (sum, entry) => sum + entry.amount);
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String type = 'income';
    DateTime entryDate = _selectedDate;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(uiT('Add Entry')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'income', label: Text(uiT('Income'))),
                    ButtonSegment(value: 'expense', label: Text(uiT('Expense'))),
                  ],
                  selected: {type},
                  onSelectionChanged: (selection) =>
                      setDialogState(() => type = selection.first),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: entryDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      helpText: uiT('Select entry date'),
                    );
                    if (picked != null) {
                      setDialogState(() => entryDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: uiT('Date'),
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(_formatDate(entryDate)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: uiT('Description'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: uiT('Amount'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: uiT('Note (optional)'),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(uiT('Cancel')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: PosDashboardScreen.primaryGreen,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                if (nameCtrl.text.trim().isEmpty || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text(uiT('Enter a description and a valid amount')),
                    ),
                  );
                  return;
                }

                await AppData.instance.addIncomeExpense(
                  LedgerEntry(
                    id: AppData.newId(),
                    name: nameCtrl.text.trim(),
                    note: noteCtrl.text.trim(),
                    amount: amount,
                    date: entryDate,
                    type: type,
                  ),
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: Text(uiT('Save')),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    noteCtrl.dispose();
    amountCtrl.dispose();

    if (saved == true && mounted) setState(() {});
  }

  String _money(double value) =>
      'MMK ${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}';

  Widget _summaryCard(
    String title,
    double amount,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: .12),
              foregroundColor: color,
              child: Icon(icon),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    uiT(title),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _money(amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryPanel(double profit, double expense, double net) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          uiT('Summary'),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _summaryCard('Total Profit', profit, Icons.trending_up, Colors.green),
        _summaryCard('Expense', expense, Icons.trending_down, Colors.red),
        _summaryCard(
          'Net Profit',
          net,
          Icons.account_balance_wallet_outlined,
          net >= 0 ? PosDashboardScreen.primaryGreen : Colors.red,
        ),
        const SizedBox(height: 6),
        Text(
          uiF('Period: {period}. Total Profit comes from the saved SaleItem profit. Expense here means manually recorded Income/Expense expenses; supplier purchase cost is already used when sale profit is calculated.', {'period': _periodValueLabel()}),
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _transactionList(List<LedgerEntry> entries) {
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            uiT('No transactions for this period.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isExpense = entry.type == 'expense';
        final isLinkedPayment = entry.id.startsWith('payment:');
        return ListTile(
          leading: Icon(
            isExpense ? Icons.arrow_downward : Icons.arrow_upward,
            color: isExpense ? Colors.red : Colors.green,
          ),
          title: Text(entry.name),
          subtitle: Text(
            '${entry.note.isNotEmpty ? '${uiLedgerNote(entry.note)} • ' : ''}${_formatDateOnly(entry.date)}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${isExpense ? '-' : '+'}${_money(entry.amount.abs())}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isExpense
                      ? Colors.red
                      : PosDashboardScreen.primaryGreen,
                ),
              ),
              if (isLinkedPayment)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Tooltip(
                    message: uiT('Linked payment transaction'),
                    child: Icon(Icons.link, size: 20, color: Colors.grey),
                  ),
                )
              else
                IconButton(
                  tooltip: uiT('Delete'),
                  icon:
                      const Icon(Icons.delete_outline, color: Colors.grey),
                  onPressed: () async {
                    await AppData.instance.removeIncomeExpense(entry.id);
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactions = _transactions();
    final profit = _grossProfit();
    final expense = _manualExpenses();
    final net = profit - expense;

    return Scaffold(
      appBar: AppBar(
        title: Text(uiT(widget.title)),
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _periodSelector(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final summary = Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: _summaryPanel(profit, expense, net),
                );

                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Text(
                                uiF('Transactions • {period}', {'period': _periodValueLabel()}),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(child: _transactionList(transactions)),
                          ],
                        ),
                      ),
                      SizedBox(width: 340, child: summary),
                    ],
                  );
                }

                return Column(
                  children: [
                    summary,
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          uiF('Transactions • {period}', {'period': _periodValueLabel()}),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: _transactionList(transactions)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// SALES REPORT (LPG cost / sales / expenses / profit + PDF export)
// =====================================================================

class SalesReportPage extends StatefulWidget {
  const SalesReportPage({super.key, required this.title});

  final String title;

  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  String _period = 'Daily';
  DateTime _selectedDate = DateTime.now();
  DateTime _selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  int _selectedYear = DateTime.now().year;
  bool _generatingPdf = false;

  static const List<String> _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _matchesPeriod(DateTime date) {
    switch (_period) {
      case 'Monthly':
        return date.year == _selectedMonth.year &&
            date.month == _selectedMonth.month;
      case 'Yearly':
        return date.year == _selectedYear;
      case 'Daily':
      default:
        return _sameDate(date, _selectedDate);
    }
  }

  String _formatMonth(DateTime month) =>
      '${uiT(_monthNames[month.month - 1])} ${month.year}';

  String _periodLabel() {
    switch (_period) {
      case 'Monthly':
        return _formatMonth(_selectedMonth);
      case 'Yearly':
        return '$_selectedYear';
      case 'Daily':
      default:
        return _formatDateOnly(_selectedDate);
    }
  }

  String _periodFileLabel() {
    switch (_period) {
      case 'Monthly':
        return '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';
      case 'Yearly':
        return '$_selectedYear';
      case 'Daily':
      default:
        return '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _selectDailyDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: uiT('Select report date'),
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _selectedMonth = DateTime(picked.year, picked.month);
        _selectedYear = picked.year;
      });
    }
  }

  Future<void> _selectMonth() async {
    int tempYear = _selectedMonth.year;
    int tempMonth = _selectedMonth.month;

    final selected = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(uiT('Select Month')),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: tempYear,
                      decoration: InputDecoration(
                        labelText: uiT('Year'),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (int year = 2000; year <= 2100; year++)
                          DropdownMenuItem<int>(
                            value: year,
                            child: Text('$year'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => tempYear = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      itemCount: 12,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 2.3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemBuilder: (_, index) {
                        final month = index + 1;
                        final selected = month == tempMonth;
                        return OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: selected
                                ? PosDashboardScreen.primaryGreen
                                    .withValues(alpha: .12)
                                : null,
                          ),
                          onPressed: () {
                            setDialogState(() => tempMonth = month);
                          },
                          child: Text(uiT(_monthNames[index])),
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(uiT('Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    DateTime(tempYear, tempMonth),
                  ),
                  child: Text(uiT('Select')),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedMonth = DateTime(selected.year, selected.month);
        _selectedYear = selected.year;
        _selectedDate = selected;
      });
    }
  }

  Future<void> _selectYear() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        int tempYear = _selectedYear;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(uiT('Select Year')),
              content: DropdownButtonFormField<int>(
                initialValue: tempYear,
                decoration: InputDecoration(
                  labelText: uiT('Year'),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (int year = 2000; year <= 2100; year++)
                    DropdownMenuItem<int>(
                      value: year,
                      child: Text('$year'),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => tempYear = value);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(uiT('Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, tempYear),
                  child: Text(uiT('Select')),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedYear = selected;
        _selectedMonth = DateTime(selected, _selectedMonth.month);
        _selectedDate =
            DateTime(selected, _selectedDate.month, _selectedDate.day);
      });
    }
  }

  void _changePeriod(int direction) {
    setState(() {
      switch (_period) {
        case 'Monthly':
          _selectedMonth = DateTime(
            _selectedMonth.year,
            _selectedMonth.month + direction,
          );
          _selectedYear = _selectedMonth.year;
          _selectedDate = _selectedMonth;
          break;
        case 'Yearly':
          _selectedYear += direction;
          _selectedMonth = DateTime(_selectedYear, _selectedMonth.month);
          _selectedDate = DateTime(
            _selectedYear,
            _selectedDate.month,
            _selectedDate.day,
          );
          break;
        case 'Daily':
        default:
          _selectedDate = _selectedDate.add(Duration(days: direction));
          _selectedMonth = DateTime(_selectedDate.year, _selectedDate.month);
          _selectedYear = _selectedDate.year;
          break;
      }
    });
  }

  void _jumpToToday() {
    final today = DateTime.now();
    setState(() {
      _selectedDate = today;
      _selectedMonth = DateTime(today.year, today.month);
      _selectedYear = today.year;
    });
  }

  // ---- Data for the selected period ----

  List<Sale> _periodSales() {
    final list = AppData.instance.sales
        .where((s) => _matchesPeriod(s.date))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  double _totalSalesAmount(List<Sale> sales) {
    double total = 0;
    for (final sale in sales) {
      total += AppData.instance.totalForSale(sale.voucherNumber);
    }
    return total;
  }

  double _totalLpgCost(List<Sale> sales) {
    double total = 0;
    for (final sale in sales) {
      for (final item in AppData.instance.itemsForSale(sale.voucherNumber)) {
        total += item.amount - item.profit;
      }
    }
    return total;
  }

  double _manualExpenses() {
    return AppData.instance.incomeExpenseEntries
        .where((entry) =>
            entry.type == 'expense' && _matchesPeriod(entry.date))
        .fold(0.0, (sum, entry) => sum + entry.amount);
  }

  String _money(double value) =>
      'MMK ${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}';

  // ---- UI ----

  Widget _periodSelector() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'Daily', label: Text(uiT('Daily'))),
                ButtonSegment(value: 'Monthly', label: Text(uiT('Monthly'))),
                ButtonSegment(value: 'Yearly', label: Text(uiT('Yearly'))),
              ],
              selected: {_period},
              onSelectionChanged: (selection) {
                setState(() => _period = selection.first);
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  tooltip: uiT('Previous period'),
                  onPressed: () => _changePeriod(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        switch (_period) {
                          case 'Monthly':
                            _selectMonth();
                            break;
                          case 'Yearly':
                            _selectYear();
                            break;
                          case 'Daily':
                          default:
                            _selectDailyDate();
                            break;
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: PosDashboardScreen.primaryGreen
                              .withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: PosDashboardScreen.primaryGreen
                                .withValues(alpha: .35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _period == 'Daily'
                                  ? Icons.calendar_today_outlined
                                  : _period == 'Monthly'
                                      ? Icons.calendar_month_outlined
                                      : Icons.event_repeat_outlined,
                              size: 18,
                              color: PosDashboardScreen.primaryGreen,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _periodLabel(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: PosDashboardScreen.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: uiT('Next period'),
                  onPressed: () => _changePeriod(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: _jumpToToday,
                  child: Text(uiT('Today')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard(
    String title,
    double amount,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Card(
        elevation: 1.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withValues(alpha: .12),
                foregroundColor: color,
                child: Icon(icon, size: 18),
              ),
              const SizedBox(height: 8),
              Text(
                uiT(title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _money(amount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profitPanel(double profitBefore, double profitAfter) {
    return Card(
      color: PosDashboardScreen.primaryGreen.withValues(alpha: .06),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: PosDashboardScreen.primaryGreen.withValues(alpha: .25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    uiT('Profit before expenses'),
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _money(profitBefore),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: profitBefore >= 0
                          ? PosDashboardScreen.primaryGreen
                          : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 44,
              color: Colors.black12,
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    uiT('Profit after expenses'),
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _money(profitAfter),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: profitAfter >= 0
                          ? PosDashboardScreen.primaryGreen
                          : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _salesList(List<Sale> sales) {
    if (sales.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            uiT('No sales recorded for this period.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: sales.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final sale = sales[index];
        final items = AppData.instance.itemsForSale(sale.voucherNumber);
        final amount = AppData.instance.totalForSale(sale.voucherNumber);
        final profit =
            items.fold(0.0, (sum, item) => sum + item.profit);
        return ListTile(
          dense: true,
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(
            sale.customerName.isEmpty ? uiT('Customer') : sale.customerName,
          ),
          subtitle: Text(
            uiF('Voucher {voucher} • {date} • {count} item(s)', {'voucher': sale.voucherNumber, 'date': _formatDateOnly(sale.date), 'count': items.length.toString()}),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_money(amount),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                uiF('Profit {amount}', {'amount': _money(profit)}),
                style: TextStyle(
                  fontSize: 11,
                  color: profit >= 0 ? PosDashboardScreen.primaryGreen : Colors.red,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- PDF report ----

  /// Myanmar is a complex OpenType script. The Flutter UI can shape it, but
  /// package:pdf's normal text widget does not perform the same HarfBuzz
  /// shaping. For PDF output we therefore use pdf_text_shaper for any cell
  /// containing Myanmar Unicode characters.
  ///
  /// The TTF files must be bundled with the app because pdf_text_shaper needs
  /// the actual font bytes. A package:pdf Font alone is not enough for
  /// complex-script shaping.
  Future<ShapedFont> _loadMyanmarPdfShapedFont({required bool bold}) async {
    final path = bold
        ? 'assets/fonts/NotoSansMyanmar-Bold.ttf'
        : 'assets/fonts/NotoSansMyanmar-Regular.ttf';
    try {
      final data = await rootBundle.load(path);
      return ShapedFont.fromBytes(
        data.buffer.asUint8List(),
        name: bold ? 'Noto Sans Myanmar Bold' : 'Noto Sans Myanmar',
      );
    } catch (e) {
      throw StateError(
        'Myanmar PDF font is missing. Add $path to pubspec.yaml under '
        'flutter assets/fonts before generating a PDF. Original error: $e',
      );
    }
  }

  Future<({ShapedFont regular, ShapedFont bold})> _loadReportShapedFonts() async {
    final fonts = await Future.wait<ShapedFont>([
      _loadMyanmarPdfShapedFont(bold: false),
      _loadMyanmarPdfShapedFont(bold: true),
    ]);
    return (regular: fonts[0], bold: fonts[1]);
  }

  bool _containsMyanmar(String text) {
    return RegExp(r'[\u1000-\u109F\uAA60-\uAA7F\uA9E0-\uA9FF]').hasMatch(text);
  }

  pw.Widget _pdfReportText(
    String text, {
    required ShapedFont regularFont,
    required ShapedFont boldFont,
    double fontSize = 8.5,
    bool bold = false,
    PdfColor color = PdfColors.black,
    pw.AlignmentGeometry alignment = pw.Alignment.centerLeft,
  }) {
    final font = bold ? boldFont : regularFont;
    if (_containsMyanmar(text)) {
      return pw.Align(
        alignment: alignment,
        child: ShapedText(
          text,
          style: ShapedTextStyle(
            font: font,
            fontSize: fontSize,
            color: color,
            preserveUnicodeText: true,
          ),
        ),
      );
    }

    return pw.Align(
      alignment: alignment,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    );
  }

  pw.Widget _pdfReportCell(
    String text, {
    required ShapedFont regularFont,
    required ShapedFont boldFont,
    double fontSize = 8.5,
    bool bold = false,
    PdfColor color = PdfColors.black,
    pw.AlignmentGeometry alignment = pw.Alignment.centerLeft,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 5),
      child: _pdfReportText(
        text,
        regularFont: regularFont,
        boldFont: boldFont,
        fontSize: fontSize,
        bold: bold,
        color: color,
        alignment: alignment,
      ),
    );
  }

  pw.TableRow _pdfReportHeaderRow(
    List<String> headers, {
    required ShapedFont regularFont,
    required ShapedFont boldFont,
  }) {
    const alignments = <pw.AlignmentGeometry>[
      pw.Alignment.centerLeft,
      pw.Alignment.centerLeft,
      pw.Alignment.centerLeft,
      pw.Alignment.centerLeft,
      pw.Alignment.centerRight,
      pw.Alignment.centerRight,
      pw.Alignment.center,
    ];
    return pw.TableRow(
      repeat: true,
      decoration: const pw.BoxDecoration(color: PdfColors.teal700),
      children: [
        for (var i = 0; i < headers.length; i++)
          _pdfReportCell(
            headers[i],
            regularFont: regularFont,
            boldFont: boldFont,
            fontSize: 9,
            bold: true,
            color: PdfColors.white,
            alignment: alignments[i],
          ),
      ],
    );
  }

  pw.TableRow _pdfReportDataRow(
    List<String> row, {
    required int rowIndex,
    required ShapedFont regularFont,
    required ShapedFont boldFont,
  }) {
    const alignments = <pw.AlignmentGeometry>[
      pw.Alignment.centerLeft,
      pw.Alignment.centerLeft,
      pw.Alignment.centerLeft,
      pw.Alignment.centerLeft,
      pw.Alignment.centerRight,
      pw.Alignment.centerRight,
      pw.Alignment.center,
    ];
    return pw.TableRow(
      decoration: rowIndex.isOdd
          ? const pw.BoxDecoration(color: PdfColors.grey100)
          : null,
      children: [
        for (var i = 0; i < row.length; i++)
          _pdfReportCell(
            row[i],
            regularFont: regularFont,
            boldFont: boldFont,
            fontSize: 8.5,
            alignment: alignments[i],
          ),
      ],
    );
  }

  pw.Table _pdfSalesTable(
    List<String> headers,
    List<List<String>> rows, {
    required ShapedFont regularFont,
    required ShapedFont boldFont,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(2.0),
        3: pw.FlexColumnWidth(2.2),
        4: pw.FlexColumnWidth(1.2),
        5: pw.FlexColumnWidth(1.2),
        6: pw.FlexColumnWidth(1.0),
      },
      children: [
        _pdfReportHeaderRow(
          headers,
          regularFont: regularFont,
          boldFont: boldFont,
        ),
        for (var i = 0; i < rows.length; i++)
          _pdfReportDataRow(
            rows[i],
            rowIndex: i,
            regularFont: regularFont,
            boldFont: boldFont,
          ),
      ],
    );
  }

  pw.TableRow _pdfSummaryRow(
    String label,
    String value, {
    bool bold = false,
    PdfColor? color,
    required ShapedFont regularFont,
    required ShapedFont boldFont,
  }) {
    final resolvedColor = color ?? PdfColors.black;
    return pw.TableRow(children: [
      _pdfReportCell(
        label,
        regularFont: regularFont,
        boldFont: boldFont,
        fontSize: bold ? 12 : 10.5,
        bold: bold,
        color: resolvedColor,
      ),
      _pdfReportCell(
        value,
        regularFont: regularFont,
        boldFont: boldFont,
        fontSize: bold ? 12 : 10.5,
        bold: bold,
        color: resolvedColor,
        alignment: pw.Alignment.centerRight,
      ),
    ]);
  }

  Future<void> _generateYearlySummaryPdf() async {
    // Yearly detailed exports can become extremely large because complex
    // Myanmar text is rendered as vector glyph paths. Keep the yearly export
    // deliberately compact: one row per month plus a yearly total.
    final year = _selectedYear;
    final rows = <List<String>>[];

    double yearSales = 0;
    double yearCost = 0;
    double yearExpenses = 0;
    int yearTransactions = 0;

    for (var month = 1; month <= 12; month++) {
      final monthSales = AppData.instance.sales
          .where((sale) => sale.date.year == year && sale.date.month == month)
          .toList();
      final salesTotal = _totalSalesAmount(monthSales);
      final costTotal = _totalLpgCost(monthSales);
      final expenseTotal = AppData.instance.incomeExpenseEntries
          .where((entry) =>
              entry.type == 'expense' &&
              entry.date.year == year &&
              entry.date.month == month)
          .fold<double>(0, (sum, entry) => sum + entry.amount);
      final net = salesTotal - costTotal - expenseTotal;

      yearTransactions += monthSales.length;
      yearSales += salesTotal;
      yearCost += costTotal;
      yearExpenses += expenseTotal;

      rows.add([
        _monthNames[month - 1],
        monthSales.length.toString(),
        _money(salesTotal),
        _money(costTotal),
        _money(expenseTotal),
        _money(net),
      ]);
    }

    final yearNet = yearSales - yearCost - yearExpenses;
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final doc = pw.Document();

    pw.Widget text(
      String value, {
      double size = 9,
      bool isBold = false,
      PdfColor color = PdfColors.black,
      pw.TextAlign align = pw.TextAlign.left,
    }) {
      return pw.Text(
        value,
        textAlign: align,
        style: pw.TextStyle(
          font: isBold ? bold : regular,
          fontSize: size,
          color: color,
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 28),
        build: (_) => [
          text(uiT('Kyal Sin Lay Energy & Tech'), size: 18, isBold: true,
              color: PdfColors.teal800),
          pw.SizedBox(height: 3),
          text(uiF('Yearly Sales Summary - {year}', {'year': year.toString()}), size: 13, isBold: true),
          pw.SizedBox(height: 3),
          text(uiF('Transactions: {count}', {'count': yearTransactions.toString()}), size: 9,
              color: PdfColors.grey700),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.5),
              1: pw.FlexColumnWidth(1.0),
              2: pw.FlexColumnWidth(1.5),
              3: pw.FlexColumnWidth(1.5),
              4: pw.FlexColumnWidth(1.5),
              5: pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.teal700),
                children: [
                  'Month', 'Sales Count', 'Sales', 'Cost', 'Expenses', 'Net',
                ].map(uiT).map((value) => pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: text(value, size: 8.5, isBold: true,
                      color: PdfColors.white),
                )).toList(),
              ),
              for (var i = 0; i < rows.length; i++)
                pw.TableRow(
                  decoration: i.isOdd
                      ? const pw.BoxDecoration(color: PdfColors.grey100)
                      : null,
                  children: [
                    for (var j = 0; j < rows[i].length; j++)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: text(
                          rows[i][j],
                          size: 8.5,
                          align: j == 0 || j == 1
                              ? pw.TextAlign.left
                              : pw.TextAlign.right,
                        ),
                      ),
                  ],
                ),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  text(uiT('YEAR TOTAL'), size: 8.5, isBold: true),
                  text(yearTransactions.toString(), size: 8.5, isBold: true,
                      align: pw.TextAlign.left),
                  text(_money(yearSales), size: 8.5, isBold: true,
                      align: pw.TextAlign.right),
                  text(_money(yearCost), size: 8.5, isBold: true,
                      align: pw.TextAlign.right),
                  text(_money(yearExpenses), size: 8.5, isBold: true,
                      align: pw.TextAlign.right),
                  text(_money(yearNet), size: 8.5, isBold: true,
                      color: yearNet >= 0 ? PdfColors.green800 : PdfColors.red800,
                      align: pw.TextAlign.right),
                ].map((child) => pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: child,
                )).toList(),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          text(
            uiT('Yearly export uses a compact monthly summary to avoid excessive memory use on large transaction histories.'),
            size: 8,
            color: PdfColors.grey700,
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final uri = await FilePicker.saveFile(
      dialogTitle: uiT('Save Yearly Sales Report'),
      fileName: 'Sales_Report_$year.pdf',
      mimeType: 'application/pdf',
      bytes: Uint8List.fromList(bytes),
    );

    if (uri != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Yearly report saved to ') + uri.toString())),
      );
    }
  }

  Future<void> _generatePdfReport() async {
    if (_generatingPdf) return;
    setState(() => _generatingPdf = true);
    ShapedFont? regularFont;
    ShapedFont? boldFont;
    try {
      if (_period == 'Yearly') {
        await _generateYearlySummaryPdf();
        return;
      }

      final sales = _periodSales();
      final totalSales = _totalSalesAmount(sales);
      final totalCost = _totalLpgCost(sales);
      final expenses = _manualExpenses();
      final profitBefore = totalSales - totalCost;
      final profitAfter = profitBefore - expenses;

      final fonts = await _loadReportShapedFonts();
      regularFont = fonts.regular;
      boldFont = fonts.bold;

      final doc = pw.Document();
      final headers = [
        'Date',
        'Voucher No.',
        'Customer',
        'Items',
        'Amount',
        'Profit',
        'Status',
      ].map(uiT).toList();

      // Do NOT build one giant pw.Table for a yearly report. A large yearly
      // dataset can create tens of thousands of PDF layout/shaping objects at
      // once and cause the Flutter process to be killed for memory pressure.
      // Build the rows as plain strings first, then render bounded chunks.
      final rows = <List<String>>[];
      for (final sale in sales) {
        final items = AppData.instance.itemsForSale(sale.voucherNumber);
        final itemsSummary =
            items.map((i) => '${i.name} x${i.qty}').join(', ');
        final amount = AppData.instance.totalForSale(sale.voucherNumber);
        final profit = items.fold(0.0, (sum, i) => sum + i.profit);
        final paid = AppData.instance.paidForSale(sale.voucherNumber);
        final balance = (amount - paid).clamp(0, double.infinity);
        final status = balance <= 0.005
            ? 'PAID'
            : (paid > 0 ? 'PARTIALLY PAID' : 'UNPAID');
        rows.add([
          _formatDateOnly(sale.date),
          sale.voucherNumber,
          sale.customerName.isEmpty ? 'Customer' : sale.customerName,
          itemsSummary.isEmpty ? '-' : itemsSummary,
          _money(amount),
          _money(profit),
          status,
        ]);
      }

      final reportRegularFont = regularFont;
      final reportBoldFont = boldFont;


      final normalPdfRegular = await _loadMyanmarPdfRegularAsPdfFont();
      final normalPdfBold = await _loadMyanmarPdfBoldAsPdfFont();

      const rowsPerPage = 30;
      final chunks = <List<List<String>>>[];
      for (var start = 0; start < rows.length; start += rowsPerPage) {
        final end = (start + rowsPerPage < rows.length)
            ? start + rowsPerPage
            : rows.length;
        chunks.add(rows.sublist(start, end));
      }

      pw.Widget reportHeader() => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _pdfReportText(
                uiT('Kyal Sin Lay Energy & Tech'),
                regularFont: reportRegularFont,
                boldFont: reportBoldFont,
                fontSize: 18,
                bold: true,
                color: PdfColors.teal800,
              ),
              pw.SizedBox(height: 2),
              _pdfReportText(
                uiF('Sales Report - {period}', {'period': _periodLabel()}),
                regularFont: reportRegularFont,
                boldFont: reportBoldFont,
                fontSize: 12,
              ),
              _pdfReportText(
                uiF('Generated: {date}', {'date': _formatDateOnly(DateTime.now())}),
                regularFont: reportRegularFont,
                boldFont: reportBoldFont,
                fontSize: 8,
                color: PdfColors.grey600,
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: PdfColors.grey400),
            ],
          );

      pw.Widget reportFooter(pw.Context context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: _pdfReportText(
              uiF('Page {page}', {'page': context.pageNumber.toString()}),
              regularFont: reportRegularFont,
              boldFont: reportBoldFont,
              fontSize: 8,
              color: PdfColors.grey600,
              alignment: pw.Alignment.centerRight,
            ),
          );

      pw.Widget summarySection() => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _pdfReportText(
                uiT('Summary'),
                regularFont: reportRegularFont,
                boldFont: reportBoldFont,
                fontSize: 13,
                bold: true,
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2),
                  1: pw.FlexColumnWidth(2),
                },
                children: [
                  _pdfSummaryRow(
                    uiT('LPG Cost'),
                    _money(totalCost),
                    regularFont: reportRegularFont,
                    boldFont: reportBoldFont,
                  ),
                  _pdfSummaryRow(
                    uiT('Total Sales'),
                    _money(totalSales),
                    regularFont: reportRegularFont,
                    boldFont: reportBoldFont,
                  ),
                  _pdfSummaryRow(
                    uiT('Expenses'),
                    _money(expenses),
                    regularFont: reportRegularFont,
                    boldFont: reportBoldFont,
                  ),
                  _pdfSummaryRow(
                    uiT('Profit Before Expenses'),
                    _money(profitBefore),
                    bold: true,
                    regularFont: reportRegularFont,
                    boldFont: reportBoldFont,
                  ),
                  _pdfSummaryRow(
                    uiT('Profit After Expenses'),
                    _money(profitAfter),
                    bold: true,
                    color: profitAfter >= 0
                        ? PdfColors.green800
                        : PdfColors.red800,
                    regularFont: reportRegularFont,
                    boldFont: reportBoldFont,
                  ),
                ],
              ),
            ],
          );

      // Keep the summary on the first page and render sales in bounded chunks.
      // This is especially important for Yearly mode, where there may be a
      // large number of saved sales records.
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 28),
          theme: pw.ThemeData.withFont(
            base: normalPdfRegular,
            bold: normalPdfBold,
          ),
          header: (_) => reportHeader(),
          footer: reportFooter,
          build: (_) {
            final content = <pw.Widget>[
              summarySection(),
              pw.SizedBox(height: 20),
              _pdfReportText(
                uiT('Sales Detail'),
                regularFont: reportRegularFont,
                boldFont: reportBoldFont,
                fontSize: 13,
                bold: true,
              ),
              pw.SizedBox(height: 6),
            ];

            if (chunks.isEmpty) {
              content.add(
                _pdfReportText(
                  uiT('No sales recorded for this period.'),
                  regularFont: reportRegularFont,
                  boldFont: reportBoldFont,
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              );
            } else {
              content.add(
                _pdfSalesTable(
                  headers,
                  chunks.first,
                  regularFont: reportRegularFont,
                  boldFont: reportBoldFont,
                ),
              );
            }
            return content;
          },
        ),
      );

      // Remaining chunks are separate MultiPages. This prevents the PDF
      // layout engine from materializing the whole yearly table in one go.
      for (var chunkIndex = 1; chunkIndex < chunks.length; chunkIndex++) {
        final chunk = chunks[chunkIndex];
        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 28),
            theme: pw.ThemeData.withFont(
              base: normalPdfRegular,
              bold: normalPdfBold,
            ),
            header: (_) => reportHeader(),
            footer: reportFooter,
            build: (_) => [
              _pdfReportText(
                uiT('Sales Detail (continued)'),
                regularFont: reportRegularFont,
                boldFont: reportBoldFont,
                fontSize: 13,
                bold: true,
              ),
              pw.SizedBox(height: 6),
              _pdfSalesTable(
                headers,
                chunk,
                regularFont: reportRegularFont,
                boldFont: reportBoldFont,
              ),
            ],
          ),
        );
      }

      final bytes = await doc.save();
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: 'Sales_Report_${_periodFileLabel()}.pdf',
      );
    } catch (e, stackTrace) {
      debugPrint('PDF generation failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(uiError(e)),
          ),
        );
      }
    } finally {
      regularFont?.dispose();
      boldFont?.dispose();
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  /// package:pdf still needs normal PdfFont instances for its theme and for
  /// non-Myanmar `pw.Text` widgets. These are loaded from the exact same
  /// bundled files used by ShapedFont so the document has consistent metrics.
  Future<pw.Font> _loadMyanmarPdfRegularAsPdfFont() async {
    final data = await rootBundle.load(
      'assets/fonts/NotoSansMyanmar-Regular.ttf',
    );
    return pw.Font.ttf(data);
  }

  Future<pw.Font> _loadMyanmarPdfBoldAsPdfFont() async {
    final data = await rootBundle.load(
      'assets/fonts/NotoSansMyanmar-Bold.ttf',
    );
    return pw.Font.ttf(data);
  }

  @override
  Widget build(BuildContext context) {
    final sales = _periodSales();
    final totalSales = _totalSalesAmount(sales);
    final totalCost = _totalLpgCost(sales);
    final expenses = _manualExpenses();
    final profitBefore = totalSales - totalCost;
    final profitAfter = profitBefore - expenses;

    return Scaffold(
      appBar: AppBar(
        title: Text(uiT(widget.title)),
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: uiT('Generate PDF report'),
            onPressed: _generatingPdf ? null : _generatePdfReport,
            icon: _generatingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _periodSelector(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 420;
                      final cards = [
                        _metricCard('LPG Cost', totalCost,
                            Icons.local_gas_station_outlined, Colors.deepOrange),
                        _metricCard('Sales', totalSales,
                            Icons.point_of_sale_outlined, PosDashboardScreen.primaryGreen),
                        _metricCard('Expenses', expenses,
                            Icons.trending_down, Colors.red),
                      ];
                      if (narrow) {
                        return Column(
                          children: [
                            for (final c in cards)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(children: [c]),
                              ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          cards[0],
                          const SizedBox(width: 8),
                          cards[1],
                          const SizedBox(width: 8),
                          cards[2],
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: _profitPanel(profitBefore, profitAfter),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      uiF('Sales • {period}', {'period': _periodLabel()}),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _salesList(sales),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
        onPressed: _generatingPdf ? null : _generatePdfReport,
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: Text(uiT('PDF Report')),
      ),
    );
  }
}

class LedgerPage extends StatefulWidget {
  const LedgerPage({
    super.key,
    required this.title,
    required this.accentColor,
    required this.personLabel,
    required this.totalLabelPrefix,
    required this.emptyMessage,
    required this.entriesGetter,
    required this.onAdd,
    required this.onDelete,
    this.useIncomeExpenseToggle = false,
    this.readOnly = false,
  });

  final String title;
  final Color accentColor;
  final String personLabel;
  final String totalLabelPrefix;
  final String emptyMessage;
  final bool useIncomeExpenseToggle;
  final List<LedgerEntry> Function() entriesGetter;
  final Future<void> Function(LedgerEntry entry) onAdd;
  final Future<void> Function(String id) onDelete;
  final bool readOnly;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  void _showAddDialog() {
    if (widget.readOnly) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(uiT('Automatically generated')),
          content: Text(
            widget.title == 'Pay Yan'
                ? 'Pay Yan comes from unpaid IncomingSupply records. Record the supplier purchase first; it will appear here automatically.'
                : 'Ya Yan comes from unpaid Sale records. Record the sale and payment first; it will appear here automatically.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(uiT('OK')),
            ),
          ],
        ),
      );
      return;
    }

    final nameCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String type = 'income';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(uiT('Add Entry')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.useIncomeExpenseToggle) ...[
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'income', label: Text(uiT('Income'))),
                          ButtonSegment(value: 'expense', label: Text(uiT('Expense'))),
                        ],
                        selected: {type},
                        onSelectionChanged: (s) =>
                            setDialogState(() => type = s.first),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(labelText: widget.personLabel),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: uiT('Amount')),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: InputDecoration(labelText: uiT('Note (optional)')),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(uiT('Cancel')),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                    if (nameCtrl.text.trim().isEmpty || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(uiT('Enter a name and a valid amount')),
                        ),
                      );
                      return;
                    }
                    final entry = LedgerEntry(
                      id: AppData.newId(),
                      name: nameCtrl.text.trim(),
                      note: noteCtrl.text.trim(),
                      amount: amount,
                      date: DateTime.now(),
                      type: widget.useIncomeExpenseToggle ? type : '',
                    );
                    await widget.onAdd(entry);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) setState(() {});
                  },
                  child: Text(uiT('Save')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  double get _total {
    final entries = widget.entriesGetter();
    if (widget.useIncomeExpenseToggle) {
      double income = 0, expense = 0;
      for (final e in entries) {
        if (e.type == 'expense') {
          expense += e.amount;
        } else {
          income += e.amount;
        }
      }
      return income - expense;
    }
    return entries.fold(0.0, (sum, e) => sum + e.amount);
  }

  @override
  Widget build(BuildContext context) {
    final entries = List<LedgerEntry>.from(widget.entriesGetter())
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: Text(uiT(widget.title)),
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: widget.accentColor,
        onPressed: _showAddDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: widget.accentColor.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(16),
            child: Text(
              uiF('{label}: MMK {amount}', {
                'label': uiT(widget.totalLabelPrefix),
                'amount': _total.toStringAsFixed(2),
              }),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: widget.accentColor,
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        uiT(widget.emptyMessage),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = entries[index];
                      final isExpense =
                          widget.useIncomeExpenseToggle && e.type == 'expense';
                      return ListTile(
                        leading: widget.useIncomeExpenseToggle
                            ? Icon(
                                isExpense
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color: isExpense ? Colors.red : Colors.green,
                              )
                            : null,
                        title: Text(e.name),
                        subtitle: Text(
                          '${e.note.isNotEmpty ? '${e.note} • ' : ''}${_formatDateOnly(e.date)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'MMK ${e.amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isExpense ? Colors.red : widget.accentColor,
                              ),
                            ),
                            if (!e.id.startsWith('payment:'))
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                                onPressed: () async {
                                  if (widget.readOnly) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          widget.title == 'Pay Yan'
                                              ? uiT('Pay Yan entries come from IncomingSupply. Update the purchase payment instead.')
                                              : uiT('Ya Yan entries come from Sale. Update the sale payment instead.'),
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  await widget.onDelete(e.id);
                                  if (mounted) setState(() {});
                                },
                              )
                            else
                              Tooltip(
                                message: uiT('Linked payment transaction'),
                                child: const Icon(Icons.link, size: 20, color: Colors.grey),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class ProductCatalogPage extends StatefulWidget {
  const ProductCatalogPage({super.key, required this.title});

  final String title;

  @override
  State<ProductCatalogPage> createState() => _ProductCatalogPageState();
}

class _ProductCatalogPageState extends State<ProductCatalogPage> {
  // ---------------------------------------------------------------------------
  // The data model still stores all inventory settings, but the main product
  // form intentionally exposes only the information a normal user needs.
  // Technical unit/conversion fields live inside Advanced settings.
  // ---------------------------------------------------------------------------
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _typeController = TextEditingController();
  final TextEditingController _subTypeController = TextEditingController();
  final TextEditingController _measurementController = TextEditingController();
  final TextEditingController _incomingUnitController = TextEditingController();
  final TextEditingController _saleUnitController = TextEditingController();
  final TextEditingController _incomingConversionController =
      TextEditingController(text: '1');
  final TextEditingController _saleConversionController =
      TextEditingController(text: '1');
  final TextEditingController _price1Controller = TextEditingController();
  final TextEditingController _price2Controller = TextEditingController();
  final TextEditingController _price3Controller = TextEditingController();
  final TextEditingController _costController = TextEditingController();

  String? _selectedSupplier;
  String? _selectedParentProductId;
  String? _editingId;
  bool _subtractFromParentStock = false;
  String _saleConsumptionMode = 'fixed';
  bool _showAdvanced = false;

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _subTypeController.dispose();
    _measurementController.dispose();
    _incomingUnitController.dispose();
    _saleUnitController.dispose();
    _incomingConversionController.dispose();
    _saleConversionController.dispose();
    _price1Controller.dispose();
    _price2Controller.dispose();
    _price3Controller.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _clearForm() {
    _editingId = null;
    _nameController.clear();
    _typeController.clear();
    _subTypeController.clear();
    _measurementController.clear();
    _incomingUnitController.text = 'unit';
    _saleUnitController.text = 'unit';
    _incomingConversionController.text = '1';
    _saleConversionController.text = '1';
    _price1Controller.clear();
    _price2Controller.clear();
    _price3Controller.clear();
    _costController.clear();
    _selectedSupplier = null;
    _selectedParentProductId = null;
    _subtractFromParentStock = false;
    _saleConsumptionMode = 'fixed';
    _showAdvanced = false;
  }

  void _loadProduct(Product product) {
    setState(() {
      _editingId = product.id;
      _nameController.text = product.name;
      _typeController.text = product.type;
      _subTypeController.text = product.subType;
      _measurementController.text = product.measurement;
      _incomingUnitController.text =
          product.incomingUnit.isEmpty ? 'unit' : product.incomingUnit;
      _saleUnitController.text =
          product.saleUnit.isEmpty ? 'unit' : product.saleUnit;
      _incomingConversionController.text = _numberText(
        product.incomingStockUnitsPerInput > 0
            ? product.incomingStockUnitsPerInput
            : 1,
      );
      _saleConversionController.text = _numberText(
        product.saleStockUnitsPerUnit > 0 ? product.saleStockUnitsPerUnit : 1,
      );
      _price1Controller.text = _numberText(product.sellingPrice1);
      _price2Controller.text = _numberText(product.sellingPrice2);
      _price3Controller.text = _numberText(product.sellingPrice3);
      _costController.text = _numberText(product.cost);
      _selectedSupplier = product.supplier.isEmpty ? null : product.supplier;
      _selectedParentProductId = product.parentProductId.isEmpty
          ? null
          : product.parentProductId;
      _subtractFromParentStock = product.subtractFromParentStock;
      _saleConsumptionMode = product.saleConsumptionMode == 'kg_or_viss'
          ? 'kg_or_viss'
          : 'fixed';
      _showAdvanced = false;
    });
  }

  String _numberText(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  List<Person> get _suppliers {
    final list = AppData.instance.people
        .where((person) => person.category.toLowerCase() == 'supplier')
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<String> _supplierNames({String? current}) {
    final names = _suppliers.map((supplier) => supplier.name).toList();
    if (current != null && current.trim().isNotEmpty && !names.contains(current)) {
      names.insert(0, current);
    }
    return names;
  }

  List<Product> get _parentCandidates {
    final editing = _editingId;
    final list = AppData.instance.products.where((product) {
      if (editing != null && product.id == editing) return false;
      return !product.subtractFromParentStock;
    }).toList()
      ..sort((a, b) {
        final aLabel = '${a.name} ${a.type} ${a.subType}'.toLowerCase();
        final bLabel = '${b.name} ${b.type} ${b.subType}'.toLowerCase();
        return aLabel.compareTo(bLabel);
      });
    return list;
  }

  String _normalizeLabel(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  bool get _isLpg => _normalizeLabel(_typeController.text) == 'lpg';

  void _applyLpgPreset(String preset) {
    setState(() {
      _typeController.text = 'LPG';
      _subTypeController.text = preset;
      _measurementController.text = 'kg';
      _saleConsumptionMode = 'fixed';
      _incomingUnitController.text = 'kg';
      _incomingConversionController.text = '1';

      switch (preset) {
        case '220g':
          // Selling variant: deduct 0.22 kg from the LPG Kg main stock.
          _subtractFromParentStock = true;
          _saleUnitController.text = '220g';
          _saleConversionController.text = '0.22';
          break;
        case 'Viss':
          // Selling variant: one viss is 1.6 kg of LPG stock.
          _subtractFromParentStock = true;
          _saleUnitController.text = 'Viss';
          _saleConversionController.text = '1.6';
          break;
        case 'Kg':
          // Main stock product: incoming and selling quantities are both kg.
          _subtractFromParentStock = false;
          _selectedParentProductId = null;
          _saleUnitController.text = 'kg';
          _saleConversionController.text = '1';
          break;
      }
    });
  }

  /// Fill technical inventory settings from the friendly fields whenever
  /// possible. Existing explicit advanced values are respected unless the
  /// product is one of the built-in LPG patterns.
  Map<String, dynamic> _resolvedInventorySetup() {
    final type = _normalizeLabel(_typeController.text);
    final subtype = _normalizeLabel(_subTypeController.text);
    final name = _normalizeLabel(_nameController.text);

    Product? parent;
    if (_selectedParentProductId != null) {
      parent = AppData.instance.productById(_selectedParentProductId!);
    }

    String measurement = _measurementController.text.trim();
    String incomingUnit = _incomingUnitController.text.trim();
    String saleUnit = _saleUnitController.text.trim();
    double incomingConversion =
        double.tryParse(_incomingConversionController.text.trim()) ?? 1;
    double saleConversion =
        double.tryParse(_saleConversionController.text.trim()) ?? 1;
    String saleMode = _saleConsumptionMode;

    // Variants inherit the parent's physical stock unit.
    if (_subtractFromParentStock && parent != null) {
      if (parent.measurement.trim().isNotEmpty) {
        measurement = parent.measurement.trim();
      }
      if (incomingUnit.isEmpty || incomingUnit == 'unit') {
        incomingUnit = saleUnit.isEmpty || saleUnit == 'unit' ? 'unit' : saleUnit;
      }
      incomingConversion = 1;
    }

    // Friendly automatic rules for LPG.
    if (type == 'lpg') {
      measurement = measurement.isEmpty
          ? (parent?.measurement.trim().isNotEmpty == true
              ? parent!.measurement.trim()
              : 'kg')
          : measurement;

      // Main LPG stock is received in kg only. The user never chooses a
      // cylinder/fully-converted receiving unit.
      if (!_subtractFromParentStock) {
        measurement = 'kg';
        incomingUnit = 'kg';
        incomingConversion = 1;
      }

      if (subtype.contains('220')) {
        // LPG 220g is a fixed 0.22 kg selling variant of the main LPG stock.
        saleUnit = saleUnit.isEmpty || saleUnit == 'unit' ? '220g' : saleUnit;
        saleMode = 'fixed';
        if (saleConversion == 1) saleConversion = 0.22;
      } else if (subtype.contains('viss')) {
        // LPG Viss is a fixed 1.6 kg selling variant of the main LPG stock.
        saleUnit = saleUnit.isEmpty || saleUnit == 'unit' ? 'Viss' : saleUnit;
        saleMode = 'fixed';
        if (saleConversion == 1) saleConversion = 1.6;
      } else if (subtype == 'kg' || subtype.endsWith(' kg')) {
        // LPG Kg is the main stock product and is sold directly by kg.
        if (!_subtractFromParentStock) {
          saleUnit = saleUnit.isEmpty || saleUnit == 'unit' ? 'kg' : saleUnit;
          saleMode = 'fixed';
          if (saleConversion == 1) saleConversion = 1;
        }
      }
    }

    // Generic products should still work without any technical setup.
    if (measurement.isEmpty) measurement = 'unit';
    if (incomingUnit.isEmpty) incomingUnit = measurement;
    if (saleUnit.isEmpty) {
      saleUnit = _subTypeController.text.trim().isEmpty
          ? measurement
          : _subTypeController.text.trim();
    }
    if (incomingConversion <= 0) incomingConversion = 1;
    if (!_subtractFromParentStock && saleConversion <= 0) saleConversion = 1;

    // Selling variants do not own incoming stock. Keep a safe metadata value
    // for compatibility with the existing data model.
    if (_subtractFromParentStock) {
      incomingConversion = 1;
    }

    return {
      'measurement': measurement,
      'incomingUnit': incomingUnit,
      'saleUnit': saleUnit,
      'incomingConversion': incomingConversion,
      'saleConversion': saleConversion,
      'saleMode': saleMode,
      'parent': parent,
      'name': name,
      'type': _typeController.text.trim(),
      'subType': _subTypeController.text.trim(),
    };
  }

  Future<void> _saveProduct() async {
    final setup = _resolvedInventorySetup();
    final name = setup['name'] as String;
    final type = setup['type'] as String;
    final subtype = setup['subType'] as String;
    final measurement = setup['measurement'] as String;
    final incomingUnit = setup['incomingUnit'] as String;
    final saleUnit = setup['saleUnit'] as String;
    final incomingConversion = setup['incomingConversion'] as double;
    final saleConversion = setup['saleConversion'] as double;
    final saleMode = setup['saleMode'] as String;
    final parent = setup['parent'] as Product?;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Please enter a product name.'))),
      );
      return;
    }

    if (_subtractFromParentStock && parent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Select the main stock product for this selling variant.'))),
      );
      return;
    }

    if (incomingConversion <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Incoming stock conversion must be greater than zero.'))),
      );
      return;
    }

    if (!_subtractFromParentStock && saleConversion <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Stock used per direct sale unit must be greater than zero.'))),
      );
      return;
    }

    if (_subtractFromParentStock &&
        saleMode == 'fixed' &&
        saleConversion <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Enter how much parent stock one sale unit consumes.'))),
      );
      return;
    }

    final product = Product(
      id: _editingId ?? '',
      name: name,
      type: type,
      subType: subtype,
      measurement: measurement,
      incomingUnit: incomingUnit,
      saleUnit: saleUnit,
      stock: 0,
      sellingPrice1: double.tryParse(_price1Controller.text.trim()) ?? 0,
      sellingPrice2: double.tryParse(_price2Controller.text.trim()) ?? 0,
      sellingPrice3: double.tryParse(_price3Controller.text.trim()) ?? 0,
      cost: double.tryParse(_costController.text.trim()) ?? 0,
      supplier: (_selectedSupplier ?? '').trim(),
      subtractFromParentStock: _subtractFromParentStock,
      parentProductId: parent?.id ?? '',
      incomingStockUnitsPerInput: incomingConversion,
      saleStockUnitsPerUnit: saleMode == 'kg_or_viss' ? 0 : saleConversion,
      saleConsumptionMode: saleMode,
    );

    try {
      final wasEditing = _editingId != null;
      if (wasEditing) {
        await AppData.instance.updateProduct(product);
      } else {
        await AppData.instance.addProduct(product);
      }
      if (!mounted) return;
      setState(_clearForm);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(wasEditing ? uiT('Product updated.') : uiT('Product created.'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiError(e))),
      );
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final incomingCount = AppData.instance.incomingSupplies
        .where((supply) => supply.productId == product.id)
        .length;
    final saleCount = AppData.instance.saleItems
        .where((item) => item.productId == product.id)
        .length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uiT('Delete product?')),
        content: Text(
          uiF('Delete "{name}" ({kind})?\n\nIncoming records: {incoming}\nSaved sale items: {sales}\n\nParent stock products cannot be deleted while selling variants depend on them.', {
            'name': product.name,
            'kind': product.subType.isEmpty ? product.type : '${product.type} • ${product.subType}',
            'incoming': incomingCount.toString(),
            'sales': saleCount.toString(),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(uiT('Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(uiT('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await AppData.instance.deleteProduct(product);
      if (!mounted) return;
      setState(() {
        if (_editingId == product.id) _clearForm();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Product deleted.'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiError(e))),
      );
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    String? hintText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: uiT(label),
        hintText: hintText == null ? null : uiT(hintText),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _responsiveFields(BuildContext context, List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              for (int i = 0; i < fields.length; i++) ...[
                fields[i],
                if (i != fields.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (int i = 0; i < fields.length; i++) ...[
              Expanded(child: fields[i]),
              if (i != fields.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _quickPreset(String label, VoidCallback onPressed) {
    return ActionChip(
      avatar: const Icon(Icons.auto_awesome, size: 16),
      label: Text(label),
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = [...AppData.instance.products]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final parents = _parentCandidates;

    if (_selectedParentProductId != null &&
        !parents.any((p) => p.id == _selectedParentProductId)) {
      final currentParent = AppData.instance.productById(_selectedParentProductId!);
      if (currentParent != null &&
          currentParent.id != _editingId &&
          !currentParent.subtractFromParentStock) {
        parents.insert(0, currentParent);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(uiT(widget.title)),
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _editingId == null
                                    ? 'Add New Product'
                                    : 'Edit Product',
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_editingId != null)
                              TextButton.icon(
                                onPressed: () => setState(_clearForm),
                                icon: const Icon(Icons.close),
                                label: Text(uiT('Cancel')),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          uiT('Enter the essentials. Inventory rules are filled automatically for common products.'),
                          style: TextStyle(color: Colors.grey[700], fontSize: 12),
                        ),
                        const SizedBox(height: 16),

                        _field(
                          _nameController,
                          'Product name *',
                          hintText: uiT('Example: LPG Kg'),
                        ),
                        const SizedBox(height: 12),

                        _responsiveFields(context, [
                          _field(
                            _typeController,
                            'Type',
                            hintText: uiT('Example: LPG'),
                          ),
                          _field(
                            _subTypeController,
                            'Variant / sub type',
                            hintText: uiT('Example: 220g, Viss, Kg'),
                          ),
                        ]),

                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _quickPreset('LPG 220g', () => _applyLpgPreset('220g')),
                            _quickPreset('LPG Viss', () => _applyLpgPreset('Viss')),
                            _quickPreset('LPG Kg', () => _applyLpgPreset('Kg')),
                          ],
                        ),
                        const SizedBox(height: 16),

                        _responsiveFields(context, [
                          _field(
                            _price1Controller,
                            'Selling price',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                          _field(
                            _costController,
                            'Cost per sale unit',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            hintText: uiT('Optional'),
                          ),
                        ]),

                        const SizedBox(height: 10),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(uiT('This is a selling variant')),
                          subtitle: Text(
                            uiT('Turn this on when the product uses stock from another product, such as LPG 220g or LPG Viss.'),
                          ),
                          value: _subtractFromParentStock,
                          onChanged: (value) {
                            setState(() {
                              _subtractFromParentStock = value;
                              if (!value) {
                                _selectedParentProductId = null;
                                _saleConsumptionMode = 'fixed';
                              }
                            });
                          },
                        ),

                        if (_subtractFromParentStock) ...[
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedParentProductId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: uiT('Main stock product'),
                              border: OutlineInputBorder(),
                            ),
                            hint: Text(
                              parents.isEmpty
                                  ? 'Create a main stock product first'
                                  : 'Choose the product whose stock this variant uses',
                            ),
                            items: parents
                                .map(
                                  (p) => DropdownMenuItem<String>(
                                    value: p.id,
                                    child: Text(
                                      '${p.name}${p.subType.isEmpty ? '' : ' • ${p.subType}'}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: parents.isEmpty
                                ? null
                                : (value) => setState(
                                      () => _selectedParentProductId = value,
                                    ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _saleConsumptionMode,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: uiT('How is this variant sold?'),
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'fixed',
                                child: Text(uiT('By a fixed unit')),
                              ),
                              DropdownMenuItem(
                                value: 'kg_or_viss',
                                child: Text(uiT('By kg or viss at sale')),
                              ),
                            ],
                            onChanged: (value) => setState(
                              () => _saleConsumptionMode = value ?? 'fixed',
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                        Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            initiallyExpanded: _showAdvanced,
                            onExpansionChanged: (value) =>
                                setState(() => _showAdvanced = value),
                            leading: const Icon(Icons.tune_outlined),
                            title: Text(uiT('Advanced inventory settings')),
                            subtitle: Text(
                              uiT('Usually leave these alone'),
                              style: const TextStyle(fontSize: 12),
                            ),
                            children: [
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  uiT('These values are stored for the inventory engine. Most products can use the automatic defaults.'),
                                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _responsiveFields(context, [
                                _field(
                                  _measurementController,
                                  'Stock unit',
                                  hintText: uiT('unit, kg, piece, box'),
                                ),
                                if (_isLpg && !_subtractFromParentStock)
                                  InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: uiT('Incoming unit'),
                                      border: OutlineInputBorder(),
                                    ),
                                    child: Text(uiT('kg (fixed for LPG)')),
                                  )
                                else
                                  _field(
                                    _incomingUnitController,
                                    'Incoming unit',
                                    hintText: uiT('What you buy/receive'),
                                  ),
                                _field(
                                  _saleUnitController,
                                  'Sale unit',
                                  hintText: uiT('What you sell'),
                                ),
                              ]),
                              const SizedBox(height: 12),
                              _responsiveFields(context, [
                                if (_isLpg && !_subtractFromParentStock)
                                  InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: uiT('Incoming conversion'),
                                      border: OutlineInputBorder(),
                                    ),
                                    child: Text(uiT('1 kg → 1 kg (fixed)')),
                                  )
                                else
                                  _field(
                                    _incomingConversionController,
                                    'Incoming conversion',
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    hintText: uiT('How incoming units become stock'),
                                  ),
                                _field(
                                  _saleConversionController,
                                  'Sale conversion',
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  hintText: uiT('220g → 0.22 kg'),
                                ),
                              ]),
                              const SizedBox(height: 12),
                              const Divider(),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  uiT('Additional selling prices'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _responsiveFields(context, [
                                _field(
                                  _price2Controller,
                                  'Selling price 2',
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  hintText: uiT('Optional'),
                                ),
                                _field(
                                  _price3Controller,
                                  'Selling price 3',
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  hintText: uiT('Optional'),
                                ),
                              ]),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedSupplier ?? '',
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: uiT('Default / preferred supplier'),
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  DropdownMenuItem<String>(
                                    value: '',
                                    child: Text(uiT('No supplier selected')),
                                  ),
                                  ..._supplierNames(current: _selectedSupplier).map(
                                    (name) => DropdownMenuItem<String>(
                                      value: name,
                                      child: Text(
                                        name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (value) => setState(() {
                                  _selectedSupplier =
                                      value?.isEmpty == true ? null : value;
                                }),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _saveProduct,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: PosDashboardScreen.primaryGreen,
                              foregroundColor: Colors.white,
                            ),
                            icon: Icon(
                              _editingId == null
                                  ? Icons.add
                                  : Icons.save_outlined,
                            ),
                            label: Text(
                              _editingId == null
                                  ? 'Create Product'
                                  : 'Save Changes',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        uiT('Product Catalog'),
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(uiF('{count} {label}', {'count': products.length.toString(), 'label': uiT(products.length == 1 ? 'product' : 'products')})),
                  ],
                ),
                const SizedBox(height: 8),
                if (products.isEmpty)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(uiT('No products yet. Create a product above first.')),
                    ),
                  )
                else
                  ...products.map(
                    (product) => Card(
                      child: ListTile(
                        leading: Icon(
                          product.subtractFromParentStock
                              ? Icons.alt_route_outlined
                              : Icons.category_outlined,
                        ),
                        title: Text(
                          product.subType.isEmpty
                              ? product.name
                              : '${product.name} • ${product.subType}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          product.subtractFromParentStock
                              ? uiF('Selling variant • Parent: {parent} • Sale unit: {unit}', {'parent': AppData.instance.productById(product.parentProductId)?.name ?? uiT('Missing'), 'unit': product.saleUnit})
                              : uiF('Stock: {stock} {unit} • Incoming: {incoming}', {'stock': AppData._formatNumber(product.stock), 'unit': product.measurement, 'incoming': product.incomingUnit}),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: uiT('Edit product'),
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _loadProduct(product),
                            ),
                            IconButton(
                              tooltip: uiT('Delete product'),
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _deleteProduct(product),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class IncomingProductsPage extends StatefulWidget {
  const IncomingProductsPage({super.key, required this.title});

  final String title;

  @override
  State<IncomingProductsPage> createState() => _IncomingProductsPageState();
}

class _IncomingProductsPageState extends State<IncomingProductsPage> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _costController = TextEditingController();
  final TextEditingController _paidController = TextEditingController();
  String? _selectedProductId;
  String? _selectedSupplier;
  String _paymentMethod = 'Cash';
  DateTime _incomingDate = DateTime.now();

  @override
  void dispose() {
    _amountController.dispose();
    _costController.dispose();
    _paidController.dispose();
    super.dispose();
  }

  Product? get _selectedProduct => _selectedProductId == null
      ? null
      : AppData.instance.productById(_selectedProductId!);

  List<Product> get _products {
    final list = AppData.instance.products
        .where((product) => !product.subtractFromParentStock)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<Person> get _suppliers {
    final list = AppData.instance.people
        .where((person) => person.category.toLowerCase() == 'supplier')
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  String _number(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  double _incomingCostForProduct(Product product) {
    if (product.type.trim().toLowerCase() == 'lpg' &&
        !product.subtractFromParentStock) {
      final saleConversion = product.saleStockUnitsPerUnit > 0
          ? product.saleStockUnitsPerUnit
          : 1;
      return product.cost / saleConversion;
    }
    return product.cost;
  }

  Future<void> _saveIncoming() async {
    final product = _selectedProduct;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Please select an existing main stock product first.'))),
      );
      return;
    }

    if (product.subtractFromParentStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Selling variants cannot receive stock directly.'))),
      );
      return;
    }

    final quantity = double.tryParse(_amountController.text.trim()) ?? 0;
    if (quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Incoming amount must be greater than zero.'))),
      );
      return;
    }

    final cost =
        double.tryParse(_costController.text.trim()) ??
        _incomingCostForProduct(product);
    if (cost < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Cost cannot be negative.'))),
      );
      return;
    }

    final total = quantity * cost;
    final paid = double.tryParse(_paidController.text.trim()) ?? 0;
    if (paid < 0 || paid > total) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Paid amount must be between 0 and the incoming total.'))),
      );
      return;
    }

    final stockAdded = quantity * product.incomingStockUnitsPerInput;
    final stockUnit = product.measurement.isEmpty ? 'stock unit(s)' : product.measurement;
    final inputUnit = product.incomingUnit.isEmpty ? 'unit' : product.incomingUnit;

    try {
      await AppData.instance.addIncomingProduct(
        supply: IncomingSupply(
          productId: product.id,
          product: product.name,
          supplier: (_selectedSupplier ?? '').trim(),
          date: _incomingDate,
          quantity: quantity,
          costPerUnit: cost,
          inputUnit: inputUnit,
          stockAdded: stockAdded,
          paidAmount: paid,
          paymentDate: paid > 0 ? DateTime.now() : null,
        ),
        paymentMethod: _paymentMethod,
      );

      if (!mounted) return;
      setState(() {
        _amountController.clear();
        _costController.clear();
        _paidController.clear();
        _selectedProductId = null;
        _selectedSupplier = null;
        _paymentMethod = 'Cash';
        _incomingDate = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uiF('{product}: added {stock} {stockUnit} from {quantity} {inputUnit}.', {'product': product.name, 'stock': _number(stockAdded), 'stockUnit': stockUnit, 'quantity': _number(quantity), 'inputUnit': inputUnit}),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiError(e))),
      );
    }
  }

  Future<void> _confirmDeleteIncoming(IncomingSupply supply) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uiT('Delete incoming record?')),
        content: Text(
          uiF(
          '{product} • {qty} {inputUnit} • {adds} {stockUnit}\n\n{details}',
          {
            'product': supply.product,
            'qty': _number(supply.quantity),
            'inputUnit': supply.inputUnit.isEmpty ? uiT('Unit') : supply.inputUnit,
            'adds': _number(supply.stockAdded),
            'stockUnit': uiT('stock units'),
            'details': uiT('This will reverse the converted stock amount and remove its linked supplier payment/payable record.'),
          },
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(uiT('Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(uiT('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await AppData.instance.deleteIncomingSupply(supply.id);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Incoming record deleted and stock reversed.'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    final suppliers = _suppliers;
    final product = _selectedProduct;

    if (_selectedProductId != null && product == null) {
      _selectedProductId = null;
    }
    if (_selectedSupplier != null && !suppliers.any((s) => s.name == _selectedSupplier)) {
      _selectedSupplier = null;
    }

    final isLpgProduct = product?.type.trim().toLowerCase() == 'lpg' &&
        product?.subtractFromParentStock != true;
    final incomingUnit = isLpgProduct
        ? 'kg'
        : (product?.incomingUnit.trim().isNotEmpty == true
            ? product!.incomingUnit
            : 'unit');
    final stockUnit = isLpgProduct
        ? 'kg'
        : (product?.measurement.trim().isNotEmpty == true
            ? product!.measurement
            : 'stock units');
    final conversion = isLpgProduct
        ? 1.0
        : (product?.incomingStockUnitsPerInput ?? 1);

    return Scaffold(
      appBar: AppBar(
        title: Text(uiT(widget.title)),
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          uiT('Record Incoming Stock'),
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedProductId,
                          decoration: InputDecoration(
                            labelText: uiT('Select Main Stock Product'),
                            border: OutlineInputBorder(),
                          ),
                          hint: Text(products.isEmpty
                              ? uiT('No main stock products created yet')
                              : uiT('Select an existing main stock product')),
                          items: products.map((p) {
                            return DropdownMenuItem<String>(
                              value: p.id,
                              child: Text(
                                '${p.name}${p.subType.isEmpty ? '' : ' • ${p.subType}'} '
                                '(${uiF('Stock: {stock} {unit}', {'stock': AppData._formatNumber(p.stock), 'unit': p.measurement})})',
                              ),
                            );
                          }).toList(),
                          onChanged: products.isEmpty
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedProductId = value;
                                    final selected = value == null
                                        ? null
                                        : AppData.instance.productById(value);
                                    if (selected != null) {
                                      final incomingCost =
                                          _incomingCostForProduct(selected);
                                      _costController.text = incomingCost == 0
                                          ? ''
                                          : incomingCost.toString();
                                      _paidController.clear();
                                    }
                                  });
                                },
                        ),
                        const SizedBox(height: 10),
                        if (product != null)
                          Card(
                            margin: EdgeInsets.zero,
                            color: Colors.grey.shade100,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(
                                    uiF('Current stock: {stock} {unit}', {'stock': _number(product.stock), 'unit': stockUnit}),
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    isLpgProduct
                                        ? uiT('LPG incoming: 1 kg → 1 kg (kg-only input)')
                                        : uiF('1 {input} → {output} {stockUnit}', {'input': incomingUnit, 'output': _number(conversion), 'stockUnit': stockUnit}),
                                  ),
                                  if (product.type.isNotEmpty || product.subType.isNotEmpty)
                                    Text(
                                      [product.type, product.subType]
                                          .where((x) => x.isNotEmpty)
                                          .join(' • '),
                                    ),
                                  Text(
                                    isLpgProduct
                                        ? uiF('Current incoming cost per kg: MMK {amount}', {'amount': _incomingCostForProduct(product).toStringAsFixed(2)})
                                        : uiF('Current cost per {unit}: MMK {amount}', {'unit': incomingUnit, 'amount': product.cost.toStringAsFixed(2)}),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: product == null
                                ? uiT('Incoming quantity')
                                : uiF('Incoming quantity ({unit})', {'unit': incomingUnit}),
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (product != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            isLpgProduct
                                ? uiT('Enter LPG quantity directly in kg. No cylinder input is used.')
                                : uiF('Stock added: {qty} {unit}', {'qty': _number((double.tryParse(_amountController.text) ?? 0) * conversion), 'unit': stockUnit}),
                            style: const TextStyle(color: Colors.black54),
                          ),
                          if (isLpgProduct)
                            Text(
                              uiF('Stock added: {qty} kg', {'qty': _number(double.tryParse(_amountController.text) ?? 0)}),
                              style: const TextStyle(color: Colors.black54),
                            ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: _costController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: uiF('Cost per {unit} for this incoming', {'unit': incomingUnit}),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedSupplier ?? '',
                          decoration: InputDecoration(
                            labelText: uiT('Supplier'),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem<String>(
                              value: '',
                              child: Text(uiT('No supplier selected')),
                            ),
                            ...suppliers.map(
                              (person) => DropdownMenuItem<String>(
                                value: person.name,
                                child: Text(person.name),
                              ),
                            ),
                          ],
                          onChanged: (value) => setState(() {
                            _selectedSupplier = value?.isEmpty == true ? null : value;
                          }),
                        ),
                        if (suppliers.isEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            uiT('Add suppliers from the Suppliers page to use named supplier records in incoming stock.'),
                            style: TextStyle(color: Colors.orange),
                          ),
                        ],
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _incomingDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null && mounted) {
                              setState(() => _incomingDate = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            uiF('Incoming date: {date}', {'date': _formatDateOnly(_incomingDate)}),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _paidController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: uiT('Amount paid to supplier'),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _paymentMethod,
                          decoration: InputDecoration(
                            labelText: uiT('Payment method'),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(value: 'Cash', child: Text(uiT('Cash'))),
                            DropdownMenuItem(value: 'Bank', child: Text(uiT('Bank'))),
                            DropdownMenuItem(value: 'Mobile', child: Text(uiT('Mobile'))),
                          ],
                          onChanged: (value) => setState(() {
                            _paymentMethod = value ?? 'Cash';
                          }),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: products.isEmpty ? null : _saveIncoming,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: PosDashboardScreen.primaryGreen,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.add_business_outlined),
                            label: Text(uiT('Add Incoming Stock')),
                          ),
                        ),
                        if (products.isEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            uiT('Create the LPG Kg main stock product first. LPG 220g and LPG Viss are selling variants and cannot receive stock directly.'),
                            style: TextStyle(color: Colors.orange),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(uiT('Incoming History'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (AppData.instance.incomingSupplies.isEmpty)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(uiT('No incoming stock transactions yet.')),
                    ),
                  )
                else
                  ...AppData.instance.incomingSupplies.reversed.map((supply) {
                    final paid = AppData.instance.paidForSupply(supply.id);
                    final balance = (supply.total - paid).clamp(0, double.infinity).toDouble();
                    final status = paid >= supply.total - .005
                        ? 'PAID'
                        : (paid > .005 ? 'PARTIALLY PAID' : 'UNPAID');
                    final statusColor = paid >= supply.total - .005
                        ? Colors.green
                        : (paid > .005 ? Colors.orange : Colors.red);

                    final detail = uiF(
                      '{qty} {inputUnit} → {stock} {stockUnit} • MMK {cost} per {unit}{supplier} • {date}',
                      {
                        'qty': _number(supply.quantity),
                        'inputUnit': supply.inputUnit.isEmpty ? uiT('Unit') : supply.inputUnit,
                        'stock': _number(supply.stockAdded),
                        'stockUnit': AppData.instance.productById(supply.productId)?.measurement ?? uiT('stock units'),
                        'cost': supply.costPerUnit.toStringAsFixed(2),
                        'unit': supply.inputUnit.isEmpty ? uiT('Unit') : supply.inputUnit,
                        'supplier': supply.supplier.isEmpty ? '' : ' • ${supply.supplier}',
                        'date': _formatDateOnly(supply.date),
                      },
                    );

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              supply.product,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Text(detail, softWrap: true),
                            const SizedBox(height: 8),
                            Wrap(
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                Text(
                                  status,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  uiF('Balance MMK {balance}', {'balance': balance.toStringAsFixed(0)}),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                IconButton(
                                  tooltip: uiT('Delete incoming record'),
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _confirmDeleteIncoming(supply),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InStockProductsPage extends StatefulWidget {
  const InStockProductsPage({super.key, required this.title});

  final String title;

  @override
  State<InStockProductsPage> createState() => _InStockProductsPageState();
}

class _InStockProductsPageState extends State<InStockProductsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _confirmDelete(Product p) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uiT('Remove product?')),
        content: Text(
          uiF('Remove product {name}?\n\n{details}', {
            'name': p.name,
            'details': uiT('This will also delete its linked Incoming Products records and supplier payment records. Saved sales using this product are protected and will block deletion.'),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(uiT('Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await AppData.instance.deleteProduct(p);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) setState(() {});
              } catch (e) {
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(uiError(e))),
                );
              }
            },
            child: Text(uiT('Remove')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = AppData.instance.products
        .where((p) => !p.subtractFromParentStock)
        .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(uiT(widget.title)),
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              uiT('In-stock Products'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: uiT('Search product'),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: products.isEmpty
                  ? Center(
                      child: Text(uiT('No products yet. Add a master product from Products, then add stock through Incoming Products.')),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 24,
                        columns: [
                          DataColumn(label: Text(uiT('Product'))),
                          DataColumn(label: Text(uiT('Type'))),
                          DataColumn(label: Text(uiT('Qty'))),
                          DataColumn(label: Text(uiT('Unit'))),
                          DataColumn(label: Text(uiT('Price 1'))),
                          DataColumn(label: Text(uiT('Cost'))),
                          DataColumn(label: Text(uiT('Last Incoming'))),
                          DataColumn(label: Text('')),
                        ],
                        rows: products.map((p) {
                          final wholeNumber = p.stock == p.stock.roundToDouble();
                          return DataRow(cells: [
                            DataCell(Text(p.name)),
                            DataCell(Text(
                              [p.type, p.subType].where((s) => s.isNotEmpty).join(' / '),
                            )),
                            DataCell(Text(
                              p.stock.toStringAsFixed(wholeNumber ? 0 : 2),
                              style: TextStyle(
                                color: p.stock <= 0 ? Colors.red : Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            )),
                            DataCell(Text(p.measurement)),
                            DataCell(Text('MMK ${p.sellingPrice1.toStringAsFixed(2)}')),
                            DataCell(Text('MMK ${p.cost.toStringAsFixed(2)}')),
                            DataCell(Text(p.lastIncomingDate == null ? '-' : _formatDateOnly(p.lastIncomingDate!))),
                            DataCell(
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _confirmDelete(p),
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// CUSTOMER / SUPPLIER SECTION
// =====================================================================

class CustomerPage extends StatelessWidget {
  const CustomerPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(uiT(title)),
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 560 ? 1 : 2;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    children: [
                      Text(
                        uiT('People'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      GridView.count(
                        crossAxisCount: columns,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: columns == 1 ? 2.2 : 1.45,
                        children: [
                          _buildProductMenuCard(
                            context,
                            pageKey: 'Suppliers',
                            labelKey: 'Suppliers',
                            icon: Icons.people_outline_sharp,
                          ),
                          _buildProductMenuCard(
                            context,
                            pageKey: 'Customers',
                            labelKey: 'Customers',
                            icon: Icons.people_sharp,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProductMenuCard(
    BuildContext context, {
    required String pageKey,
    required String labelKey,
    required IconData icon,
  }) {
    return Card(
      color: PosDashboardScreen.cardBg,
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          final Widget page = pageKey == 'Suppliers'
              ? const SuppliersPage(title: 'Suppliers')
              : const CustomersPage(title: 'Customers');

          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => page),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30, color: PosDashboardScreen.primaryGreen),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  uiT(labelKey),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: PosDashboardScreen.textColor,
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

class AddPeoplePage extends StatefulWidget {
  const AddPeoplePage({super.key, required this.title, this.presetCategory});

  final String title;
  final String? presetCategory;

  @override
  State<AddPeoplePage> createState() => _AddPeoplePageState();
}

class _AddPeoplePageState extends State<AddPeoplePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _typeController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  late String _category;

  @override
  void initState() {
    super.initState();
    _category = widget.presetCategory ?? 'Customer';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _phoneNumberController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Please enter a name'))),
      );
      return;
    }

    AppData.instance.addPerson(Person(
      name: name,
      category: _category,
      phone: _phoneNumberController.text.trim(),
      address: _addressController.text.trim(),
    ));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(uiF('{name} added as {category}', {'name': name, 'category': uiT(_category)}))),
    );

    if (widget.presetCategory != null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _nameController.clear();
        _typeController.clear();
        _phoneNumberController.clear();
        _addressController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(uiT(widget.title)),
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.presetCategory == null) ...[
                  Text(uiT('Category'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'Customer', label: Text(uiT('Customer'))),
                      ButtonSegment(value: 'Supplier', label: Text(uiT('Supplier'))),
                    ],
                    selected: {_category},
                    onSelectionChanged: (s) => setState(() => _category = s.first),
                  ),
                  const SizedBox(height: 16),
                ],
                _buildField(_nameController, 'Entity or Person name'),
                const SizedBox(height: 12),
                _responsiveFields(
                  context,
                  _buildField(_typeController, 'Type'),
                ),
                const SizedBox(height: 12),
                _responsiveFields(
                  context,
                  _buildField(
                    _phoneNumberController,
                    'Phone number',
                    keyboardType: TextInputType.phone,
                  ),
                ),
                const SizedBox(height: 12),
                _buildField(_addressController, 'Address'),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PosDashboardScreen.primaryGreen,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      uiT('Save'),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _responsiveFields(
    BuildContext context,
    Widget first,
  ) {
    final fields = <Widget>[first];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;

        if (isNarrow) {
          return Column(
            children: [
              for (int i = 0; i < fields.length; i++) ...[
                fields[i],
                if (i != fields.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (int i = 0; i < fields.length; i++) ...[
              Expanded(child: fields[i]),
              if (i != fields.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: uiT(label),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class SuppliersPage extends StatelessWidget {
  const SuppliersPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return PeopleListScaffold(title: title, category: 'Supplier');
  }
}

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return PeopleListScaffold(title: title, category: 'Customer');
  }
}

class PeopleListScaffold extends StatefulWidget {
  const PeopleListScaffold({super.key, required this.title, required this.category});

  final String title;
  final String category;

  @override
  State<PeopleListScaffold> createState() => _PeopleListScaffoldState();
}

class _PeopleListScaffoldState extends State<PeopleListScaffold> {
  void _delete(Person p) {
    AppData.instance.deletePerson(p);
    setState(() {});
  }

  Future<void> _openAdd() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddPeoplePage(
          title: uiF('Add {category}', {'category': uiT(widget.category)}),
          presetCategory: widget.category,
        ),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final people =
        AppData.instance.people.where((p) => p.category == widget.category).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(uiT(widget.title)),
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: PosDashboardScreen.primaryGreen,
        onPressed: _openAdd,
        child: const Icon(Icons.person_add_alt_1, color: Colors.white),
      ),
      body: people.isEmpty
          ? Center(
              child: Text(uiF('No {category}s yet. Tap + to add one.', {'category': uiT(widget.category == 'Supplier' ? 'Suppliers' : 'Customers')})),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: people.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final p = people[index];
                final details = [
                  if (p.type.isNotEmpty) p.type,
                  if (p.phone.isNotEmpty) p.phone,
                  if (p.address.isNotEmpty) p.address,
                ].join(' • ');
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: PosDashboardScreen.primaryGreen,
                    child: Text(
                      p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(p.name),
                  subtitle: details.isEmpty ? null : Text(details),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.grey),
                    onPressed: () => _delete(p),
                  ),
                );
              },
            ),
    );
  }
}

// =====================================================================
// SALE PAGE + VOUCHER PREVIEW (shared) + VOUCHERS LIST
// =====================================================================

class SalePage extends StatefulWidget {
  const SalePage({super.key, required this.title});

  final String title;

  @override
  State<SalePage> createState() => _SalePageState();
}

class _SalePageState extends State<SalePage> {
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _paidController = TextEditingController();
  String _paymentMethod = 'Cash';

  Product? _selectedProduct;
  String? _selectedType;
  String? _selectedSubType;
  String? _selectedCustomer;
  String? _selectedSaleUnit;
  double? _selectedPrice;
  DateTime _selectedDate = DateTime.now();

  final List<SaleItem> _items = [];

  // Get dynamic filters based on data store
  List<String> get _availableTypes => AppData.instance.products
      .map((p) => p.type)
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();

  List<String> get _availableSubTypes => AppData.instance.products
      .where((p) => _selectedType == null || p.type == _selectedType)
      .map((p) => p.subType)
      .where((st) => st.isNotEmpty)
      .toSet()
      .toList();

  List<Product> get _filteredProducts => AppData.instance.products.where((p) {
        final matchesType = _selectedType == null || p.type == _selectedType;
        final matchesSubType =
            _selectedSubType == null || p.subType == _selectedSubType;
        return matchesType && matchesSubType;
      }).toList();

  List<Person> get _customers =>
      AppData.instance.people.where((p) => p.category == 'Customer').toList();

  // Helper function to build the majestic "Name Type SubType" string!
  String _buildFullProductName(Product? prod) {
    if (prod == null) return '';
    final parts = <String>[prod.name];
    if (prod.type.isNotEmpty &&
        prod.type.trim().toLowerCase() != prod.name.trim().toLowerCase()) {
      parts.add(prod.type);
    }
    if (prod.subType.isNotEmpty) parts.add(prod.subType);
    return parts.join(' ');
  }

  void _onProductSelected(Product? prod) {
    setState(() {
      _selectedProduct = prod;
      if (prod != null) {
        if (prod.type.isNotEmpty) _selectedType = prod.type;
        if (prod.subType.isNotEmpty) _selectedSubType = prod.subType;
        _selectedSaleUnit = prod.saleConsumptionMode == 'kg_or_viss'
            ? 'kg'
            : (prod.saleUnit.trim().isEmpty
                ? (prod.measurement.trim().isEmpty ? 'unit' : prod.measurement)
                : prod.saleUnit.trim());
        if (prod.sellingPrice1 > 0) {
          _selectedPrice = prod.sellingPrice1;
        } else if (prod.sellingPrice2 > 0) {
          _selectedPrice = prod.sellingPrice2;
        } else if (prod.sellingPrice3 > 0) {
          _selectedPrice = prod.sellingPrice3;
        } else {
          _selectedPrice = null;
        }
      } else {
        _selectedPrice = null;
        _selectedSaleUnit = null;
      }
    });
  }

  String _availableStockText(Product product) {
    final inventory = AppData.instance.inventoryProductForSale(product);
    if (inventory == null) return uiT('Parent stock missing');
    final unit = inventory.measurement.isEmpty ? 'stock units' : inventory.measurement;
    return uiF('Stock: {stock} {unit}', {'stock': AppData._formatNumber(inventory.stock), 'unit': unit});
  }

  double _pendingStockForInventory(String inventoryProductId) {
    return _items.fold(0.0, (sum, item) {
      final p = AppData.instance.productById(item.productId);
      if (p == null) return sum;
      final inventory = AppData.instance.inventoryProductForSale(p);
      if (inventory == null || inventory.id != inventoryProductId) return sum;
      return sum + (item.stockDeduction > 0
          ? item.stockDeduction
          : AppData.instance.stockConsumptionForSale(
              p, item.quantity, saleUnit: item.saleUnit));
    });
  }

  void _addItem() {
    final prod = _selectedProduct;
    final price = _selectedPrice ?? 0.0;
    final qty = double.tryParse(_quantityController.text.trim()) ?? 0;
    final saleUnit = _selectedSaleUnit ?? '';

    if (prod == null || price <= 0 || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Select a product, sale unit, price, and a valid quantity.'))),
      );
      return;
    }

    if (prod.subtractFromParentStock &&
        prod.saleConsumptionMode == 'kg_or_viss' &&
        !{'kg', 'viss'}.contains(saleUnit.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Select a valid LPG sale unit.'))),
      );
      return;
    }

    try {
      final inventory = AppData.instance.inventoryProductForSale(prod);
      if (inventory == null) {
        throw StateError('This product is missing its parent stock product.');
      }
      final deduction = AppData.instance.stockConsumptionForSale(prod, qty, saleUnit: saleUnit);
      final available = inventory.stock - _pendingStockForInventory(inventory.id);
      if (deduction > available + 0.000001) {
        throw StateError(
          'Not enough stock. ${inventory.name} has only ${AppData._formatNumber(available)} ${inventory.measurement} available for this voucher.',
        );
      }

      setState(() {
        _items.add(SaleItem(
          saleVoucherNumber: '',
          product: _buildFullProductName(prod),
          productId: prod.id,
          quantity: qty,
          sellingPrice: price,
          saleUnit: saleUnit,
          inventoryProductId: inventory.id,
          stockDeduction: deduction,
        ));
        _selectedProduct = null;
        _selectedType = null;
        _selectedSubType = null;
        _selectedSaleUnit = null;
        _selectedPrice = null;
        _quantityController.text = '1';
      });
    } on StateError catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiError(e)), backgroundColor: Colors.redAccent),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiError(e)), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  double get _grandTotal => _items.fold(0.0, (sum, item) => sum + item.amount);
  double get _paid => double.tryParse(_paidController.text) ?? 0.0;

  List<SaleItem> _previewItems() {
    if (_items.isNotEmpty) return _items;
    final prod = _selectedProduct;
    final price = _selectedPrice ?? 0.0;
    if (prod == null || price <= 0) return [];
    final qty = double.tryParse(_quantityController.text.trim()) ?? 1;
    final saleUnit = _selectedSaleUnit ??
        (prod.saleConsumptionMode == 'kg_or_viss' ? 'kg' : prod.saleUnit);
    double deduction = 0;
    try {
      deduction = AppData.instance.stockConsumptionForSale(prod, qty, saleUnit: saleUnit);
    } catch (_) {}
    return [
      SaleItem(
        saleVoucherNumber: '',
        product: _buildFullProductName(prod),
        quantity: qty,
        sellingPrice: price,
        saleUnit: saleUnit,
        stockDeduction: deduction,
      ),
    ];
  }

  String _formatDate(DateTime date) => _formatDateOnly(date);

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _saveVoucher() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(uiT('Add at least one item before saving the voucher'))),
      );
      return;
    }

    final voucherNumber = AppData.instance.newVoucherNumber();
    final saleItems = _items
        .map(
          (item) => SaleItem(
            saleVoucherNumber: voucherNumber,
            product: item.product,
            productId: item.productId,
            quantity: item.quantity,
            sellingPrice: item.sellingPrice,
            saleUnit: item.saleUnit,
          ),
        )
        .toList();

    final sale = Sale(
      voucherNumber: voucherNumber,
      customer: _nameController.text.trim(),
      date: _selectedDate,
      paid: _paid.clamp(0, _grandTotal).toDouble(),
      paymentMethod: _paymentMethod,
      cylinderLedger: '',
      paymentDate: _paid > 0 ? DateTime.now() : null,
    );

    try {
      await AppData.instance.addSale(sale, saleItems);
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(uiError(e)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(uiError(e)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Voucher saved successfully. Cha-ching!'))),
      );
    }
    setState(() {
      _items.clear();
      _nameController.clear();
      _paidController.clear();
      _paymentMethod = 'Cash';
      _selectedDate = DateTime.now();
      _selectedCustomer = null;
      _selectedSaleUnit = null;
    });
  }

  Future<void> _copyVoucherText() async {
    final buffer = StringBuffer();
    buffer.writeln('Kyal Sin Lay Energy & Tech');
    buffer.writeln(uiF('Date: {date}', {'date': _formatDate(_selectedDate)}));
    buffer.writeln(
        uiF('Customer: {customer}', {'customer': _nameController.text.isEmpty ? 'N/A' : _nameController.text}));
    for (final item in _items) {
      buffer.writeln(
          '${item.name} x${item.qty}${item.saleUnit.isEmpty ? '' : ' ${item.saleUnit}'} = MMK ${item.amount.toStringAsFixed(2)}');
    }
    buffer.writeln(uiF('Total: MMK {amount}', {'amount': _grandTotal.toStringAsFixed(2)}));
    buffer.writeln(uiF('Paid: MMK {amount}', {'amount': _paid.toStringAsFixed(2)}));
    buffer.writeln('Balance: MMK ${(_grandTotal - _paid).toStringAsFixed(2)}');
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Voucher details copied to clipboard'))),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _paidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

  // ============================================================
  // FORM WIDGET
  // ============================================================
  Widget buildForm() {
    // Generate the price dropdown items.
    // We use a Set so duplicate prices do not cause dropdown issues.
    List<DropdownMenuItem<double>> priceItems = [];

    if (_selectedProduct != null) {
      Set<double> validPrices = {};

      if (_selectedProduct!.sellingPrice1 > 0) {
        validPrices.add(_selectedProduct!.sellingPrice1);
      }

      if (_selectedProduct!.sellingPrice2 > 0) {
        validPrices.add(_selectedProduct!.sellingPrice2);
      }

      if (_selectedProduct!.sellingPrice3 > 0) {
        validPrices.add(_selectedProduct!.sellingPrice3);
      }

      priceItems = validPrices
          .map(
            (p) => DropdownMenuItem<double>(
              value: p,
              child: Text('MMK ${p.toStringAsFixed(2)}'),
            ),
          )
          .toList();
    }

    // Safety check: if current selected price is no longer available,
    // reset it to null.
    if (_selectedPrice != null &&
        !priceItems.any((item) => item.value == _selectedPrice)) {
      _selectedPrice = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          uiT('Voucher Details'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),

        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: _selectDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: uiT('Select Date'),
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    _formatDate(_selectedDate),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ========================================================
        // CUSTOMER DROPDOWN
        // ========================================================
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedCustomer,
                decoration: InputDecoration(
                  labelText: uiT('Select Registered Customer'),
                  border: OutlineInputBorder(),
                ),
                items: _customers.map((c) {
                  return DropdownMenuItem<String>(
                    value: c.name,
                    child: Text(c.name),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedCustomer = val;

                    if (val != null) {
                      _nameController.text = val;
                    }
                  });
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ========================================================
        // CUSTOMER NAME
        // ========================================================
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: uiT('Customer Name (Manual Entry / Selected)'),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),

        const Divider(height: 32),

        // ========================================================
        // PRODUCT TYPE + SUB TYPE
        // ========================================================
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;

            final typeField = DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _selectedType,
              decoration: InputDecoration(
                labelText: uiT('Product Type'),
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text(uiT('All Types'), overflow: TextOverflow.ellipsis),
                ),
                ..._availableTypes.map(
                  (t) => DropdownMenuItem<String>(
                    value: t,
                    child: Text(t, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedType = val;
                  _selectedSubType = null;
                  _selectedProduct = null;
                  _selectedSaleUnit = null;
                  _selectedPrice = null;
                });
              },
            );

            final subTypeField = DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _selectedSubType,
              decoration: InputDecoration(
                labelText: uiT('Sub Type'),
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text(uiT('All SubTypes'), overflow: TextOverflow.ellipsis),
                ),
                ..._availableSubTypes.map(
                  (st) => DropdownMenuItem<String>(
                    value: st,
                    child: Text(st, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedSubType = val;
                  _selectedProduct = null;
                  _selectedSaleUnit = null;
                  _selectedPrice = null;
                });
              },
            );

            return compact
                ? Column(
                    children: [
                      typeField,
                      const SizedBox(height: 12),
                      subTypeField,
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: typeField),
                      const SizedBox(width: 12),
                      Expanded(child: subTypeField),
                    ],
                  );
          },
        ),

        const SizedBox(height: 16),

        // ========================================================
        // PRODUCT DROPDOWN
        // ========================================================
        DropdownButtonFormField<Product>(
          isExpanded: true,
          initialValue: _selectedProduct,
          decoration: InputDecoration(
            labelText: uiT('Select Product'),
            border: OutlineInputBorder(),
          ),
          items: _filteredProducts.map((p) {
            return DropdownMenuItem<Product>(
              value: p,
              child: Text('${p.name}${p.subType.isEmpty ? '' : ' • ${p.subType}'} (${_availableStockText(p)})', overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: _onProductSelected,
        ),

        const SizedBox(height: 16),

        if (_selectedProduct != null) ...[
          const SizedBox(height: 12),
          if (_selectedProduct!.saleConsumptionMode == 'kg_or_viss')
            DropdownButtonFormField<String>(
              initialValue: _selectedSaleUnit,
              decoration: InputDecoration(
                labelText: uiT('Legacy loose-gas sale unit'),
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'kg', child: Text(uiT('Kg'))),
                DropdownMenuItem(value: 'viss', child: Text(uiT('Viss (1 viss = 1.6 kg)'))),
              ],
              onChanged: (value) => setState(() => _selectedSaleUnit = value),
            )
          else
            InputDecorator(
              decoration: InputDecoration(
                labelText: uiT('Sale unit'),
                border: OutlineInputBorder(),
              ),
              child: Text(
                (_selectedSaleUnit ?? _selectedProduct!.saleUnit).isEmpty
                    ? uiT('Unit')
                    : (_selectedSaleUnit ?? _selectedProduct!.saleUnit),
              ),
            ),
        ],

        const SizedBox(height: 16),

        // ========================================================
        // PRICE + QUANTITY
        // ========================================================
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;

            final priceField = DropdownButtonFormField<double>(
              isExpanded: true,
              initialValue: _selectedPrice,
              decoration: InputDecoration(
                labelText: uiT('Select Price'),
                border: OutlineInputBorder(),
              ),
              items: priceItems,
              onChanged: (val) {
                setState(() {
                  _selectedPrice = val;
                });
              },
            );

            final quantityField = TextField(
              controller: _quantityController,
              decoration: InputDecoration(
                labelText: _selectedProduct == null
                    ? uiT('Quantity')
                    : uiF('Quantity ({unit})', {'unit': _selectedSaleUnit ?? _selectedProduct!.saleUnit}),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            );

            return compact
                ? Column(
                    children: [
                      priceField,
                      const SizedBox(height: 12),
                      quantityField,
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: priceField),
                      const SizedBox(width: 12),
                      Expanded(child: quantityField),
                    ],
                  );
          },
        ),

        const SizedBox(height: 16),

        // ========================================================
        // ADD ITEM BUTTON
        // ========================================================
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _addItem,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add_shopping_cart),
            label: Text(
              uiT('Add Item to Voucher'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ========================================================
        // ADDED ITEMS
        // ========================================================
        if (_items.isNotEmpty) ...[
          Text(
            uiT('Added Items:'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];

              return ListTile(
                dense: true,
                title: Text(item.name),
                subtitle: Text(
                  'MMK ${item.price} x ${item.qty}${item.saleUnit.isEmpty ? '' : ' ${item.saleUnit}'}',
                ),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.delete,
                    color: Colors.red,
                  ),
                  onPressed: () => _removeItem(index),
                ),
              );
            },
          ),

          const Divider(height: 24),

          // ======================================================
          // AMOUNT PAID
          // ======================================================
          TextField(
            controller: _paidController,
            decoration: InputDecoration(
              labelText: uiT('Amount Paid (MMK)'),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            initialValue: _paymentMethod,
            decoration: InputDecoration(
              labelText: uiT('Payment Method'),
              border: OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: 'Cash', child: Text(uiT('Cash'))),
              DropdownMenuItem(value: 'Bank', child: Text(uiT('Bank'))),
              DropdownMenuItem(value: 'Mobile', child: Text(uiT('Mobile'))),
              DropdownMenuItem(value: 'Credit', child: Text(uiT('Credit'))),
            ],
            onChanged: (value) => setState(() => _paymentMethod = value ?? 'Cash'),
          ),

          const SizedBox(height: 12),

          // ======================================================
          // GRAND TOTAL
          // ======================================================
          Text(
            uiF('Grand Total: MMK {amount}', {'amount': _grandTotal.toStringAsFixed(2)}),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),

          // ======================================================
          // BALANCE
          // ======================================================
          Text(
            uiF('Balance: MMK {amount}', {'amount': (_grandTotal - _paid).toStringAsFixed(2)}),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.red,
            ),
          ),

          const SizedBox(height: 16),

          // ======================================================
          // ACTION BUTTONS
          // ======================================================
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyVoucherText,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: Text(uiT('Copy Details')),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveVoucher,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        PosDashboardScreen.primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(uiT('Save Voucher')),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ============================================================
  // VOUCHER PREVIEW
  // ============================================================
  Widget buildVoucherPreview() {
    return Container(
      color: Colors.grey[300],
      padding: const EdgeInsets.all(16),
      child: Center(
        child: VoucherPreviewCard(
          customerName: _nameController.text,
          items: _previewItems(),
          paid: _paid,
          // Keep the live preview linked to the exact date selected
          // in the Sale form. This is the same date that will be saved
          // into Sale.date when the voucher is created.
          date: _selectedDate,
        ),
      ),
    );
  }

  // ============================================================
  // PAGE
  // ============================================================
  return Scaffold(
    appBar: AppBar(
      title: Text(uiT('Sale Page')),
    ),

    body: LayoutBuilder(
      builder: (context, constraints) {
        // Narrow browser windows now get the same stacked experience as phones.
        // Keep the split form/preview only when there is enough horizontal room.
        final isWide = constraints.maxWidth >= 900;

        if (!isWide) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: buildForm(),
                ),
                const Divider(height: 1, thickness: 1),
                buildVoucherPreview(),
              ],
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: buildForm(),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: buildVoucherPreview(),
            ),
          ],
        );
      },
    ),
  );
  }
}

// ============================================================================
// VOUCHER PREVIEW CARD
// ============================================================================

class VoucherPreviewCard extends StatelessWidget {
  const VoucherPreviewCard({
    super.key,
    required this.customerName,
    required this.items,
    required this.paid,
    required this.date,
  });

  final String customerName;
  final List<SaleItem> items;
  final double paid;
  final DateTime date;

  double get _total =>
      items.fold(0.0, (sum, i) => sum + i.amount);

  String get _qrData {
    final name =
        customerName.isEmpty ? 'Customer' : customerName;

    if (items.isEmpty) {
      return 'Kyal Sin Lay Energy | '
          'Name: $name | '
          'Total: MMK ${_total.toStringAsFixed(2)}';
    }

    final itemDetails = items
        .map((i) => '${i.name} (x${i.qty})')
        .join(', ');

    return 'Kyal Sin Lay Energy | '
        'Name: $name | '
        'Items: $itemDetails | '
        'Total: MMK ${_total.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final left = _total - paid;

    return AspectRatio(
      aspectRatio: 148 / 210,
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),

        child: FittedBox(
          fit: BoxFit.contain,

          child: SizedBox(
            width: 400,
            height: 567,

            child: Padding(
              padding: const EdgeInsets.all(20.0),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // ==================================================
                  // STORE NAME
                  // ==================================================
                  const Text(
                    'ကြယ်စင်လေး',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.blueAccent,
                    ),
                  ),

                  const SizedBox(height: 4),

                  // ==================================================
                  // PHONE
                  // ==================================================
                  Text(
                    'ဖုန်း - 09-401615090, 09-681617010',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),

                  // ==================================================
                  // ADDRESS 1
                  // ==================================================
                  Text(
                    'လိပ်စာ (1) - ကျန်းစစ်သားလမ်းနှင့် ပုလဲလမ်းထောင့် | ငပလီမြို့ | သံတွဲမြို့နယ် | ရခိုင်ပြည်နယ်',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),

                  // ==================================================
                  // ADDRESS 2
                  // ==================================================
                  Text(
                    'လိပ်စာ (2) - တွံတေးမြို့နယ် | ရန်ကုန်တိုင်းဒေသကြီး',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),

                  // ==================================================
                  // ADDRESS 3
                  // ==================================================
                  Text(
                    'လိပ်စာ (3) - တူးချောင်းရပ်ကွက် | ထန်းတပင်မြို့နယ် | ရန်ကုန်တိုင်းဒေသကြီး',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Divider(
                    thickness: 1,
                  ),

                  // ==================================================
                  // VOUCHER TITLE
                  // ==================================================
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      'VOUCHER',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // ==================================================
                  // CUSTOMER + DATE
                  // ==================================================
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Prepared For: ${customerName.isEmpty ? 'John/Jane Doe' : customerName}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Date: ${_formatDateOnly(date)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // ==================================================
                  // PRODUCT TABLE
                  // ==================================================
                  Table(
                    border: TableBorder.all(
                      color: Colors.black,
                      width: 0.8,
                    ),

                    columnWidths: const {
                      0: FlexColumnWidth(0.8),
                      1: FlexColumnWidth(3.5),
                      2: FlexColumnWidth(1.8),
                      3: FlexColumnWidth(1.2),
                      4: FlexColumnWidth(2.0),
                    },

                    children: [
                      // --------------------------------------------
                      // TABLE HEADER
                      // --------------------------------------------
                      TableRow(
                        decoration: const BoxDecoration(
                          color: Colors.black12,
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(
                              'No',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(
                              'Product',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(
                              'Price',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(
                              'Qty',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(
                              'Amount',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // --------------------------------------------
                      // ACTUAL ITEMS
                      // --------------------------------------------
                      ...items.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;

                        return TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Text(
                                '${idx + 1}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                ),
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Text(
                                item.name,
                                style: const TextStyle(
                                  fontSize: 10,
                                ),
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Text(
                                item.price.toStringAsFixed(2),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 10,
                                ),
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Text(
                                item.qty.toString(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                ),
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Text(
                                item.amount.toStringAsFixed(2),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        );
                      }),

                      // --------------------------------------------
                      // EMPTY ROWS
                      // --------------------------------------------
                      ...List.generate(
                        items.length >= 4 ? 0 : 4 - items.length,
                        (index) {
                          return const TableRow(
                            children: [
                              Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Text(
                                  '',
                                  style: TextStyle(fontSize: 10),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Text(''),
                              ),
                              Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Text(''),
                              ),
                              Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Text(''),
                              ),
                              Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Text(''),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),

                  // ==================================================
                  // TOTALS TABLE
                  // ==================================================
                  Table(
                    border: TableBorder.all(
                      color: Colors.black,
                      width: 0.8,
                    ),

                    columnWidths: const {
                      0: FlexColumnWidth(2.0),
                      1: FlexColumnWidth(2.6),
                    },

                    children: [
                      // --------------------------------------------
                      // TOTAL
                      // --------------------------------------------
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(
                              'Total',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(
                              _total.toStringAsFixed(2),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // --------------------------------------------
                      // PAID
                      // --------------------------------------------
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(
                              'Paid',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(
                              paid.toStringAsFixed(2),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // --------------------------------------------
                      // TOTAL LEFT
                      // --------------------------------------------
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(
                              'Total Left',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(
                              left.toStringAsFixed(2),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ==================================================
                  // PUSH SIGNATURES TO BOTTOM
                  // ==================================================
                  const Spacer(),

                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    crossAxisAlignment:
                        CrossAxisAlignment.end,
                    children: [
                      // CUSTOMER SIGN
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 80,
                            child: Divider(
                              color: Colors.black,
                              thickness: 1,
                            ),
                          ),
                          Text(
                            'Customer Sign',
                            style: TextStyle(
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),

                      // QR
                      // QR shrinks as more items are added so the voucher stays compact.
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final availableWidth =
                                constraints.maxWidth.isFinite
                                    ? constraints.maxWidth
                                    : 100.0;
                            final baseSize =
                                availableWidth.clamp(64.0, 96.0).toDouble();
                            final itemReduction =
                                ((items.length - 1).clamp(0, 6) * 5.0);
                            final qrSize =
                                (baseSize - itemReduction).clamp(56.0, 96.0).toDouble();

                            return Center(
                              child: QrImageView(
                                data: _qrData,
                                version: QrVersions.auto,
                                errorCorrectionLevel: QrErrorCorrectLevel.M,
                                gapless: true,
                                size: qrSize,
                              ),
                            );
                          },
                        ),
                      ),

                      // SELLER SIGN
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 80,
                            child: Divider(
                              color: Colors.black,
                              thickness: 1,
                            ),
                          ),
                          Text(
                            'Seller Sign',
                            style: TextStyle(
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
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

class VouchersPage extends StatefulWidget {
  const VouchersPage({super.key, required this.title});
  final String title;
  @override State<VouchersPage> createState() => _VouchersPageState();
}

class _VouchersPageState extends State<VouchersPage> {
  void _openVoucher(Voucher v) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => VoucherDetailPage(voucher: v)));
    if (mounted) setState(() {});
  }

  void _confirmDelete(Voucher v) {
    showDialog(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(uiT('Delete voucher?')),
      content: Text(uiF('Delete the voucher for "{customer}"? Stock sold on this voucher will be returned.', {'customer': v.customerName.isEmpty ? uiT('Customer') : v.customerName})),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(uiT('Cancel'))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () async { await AppData.instance.deleteVoucher(v.id); if (dialogContext.mounted) Navigator.pop(dialogContext); if (mounted) setState(() {}); }, child: Text(uiT('Delete')))],
    ));
  }

  @override Widget build(BuildContext context) {
    final vouchers = List<Voucher>.from(AppData.instance.vouchers)..sort((a,b) => b.date.compareTo(a.date));
    return Scaffold(
      appBar: AppBar(title: Text(uiT(widget.title)), backgroundColor: PosDashboardScreen.primaryGreen, foregroundColor: Colors.white),
      body: vouchers.isEmpty ? Center(child: Text(uiT('No vouchers saved yet. Create one from the Sale page.'))) : ListView.separated(
        padding: const EdgeInsets.all(12), itemCount: vouchers.length, separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context,index) {
          final v=vouchers[index]; final total=AppData.instance.totalForSale(v.voucherNumber); final paidAmount=AppData.instance.paidForSale(v.voucherNumber); final balance=(total-paidAmount).clamp(0,double.infinity).toDouble(); final paid=paidAmount>0 && balance>0.005; final settled=balance<=.005;
          final status=settled?'PAID':paid?'PARTIALLY PAID':'UNPAID';
          final statusColor=settled?Colors.green:paid?Colors.orange:Colors.red;
          return ListTile(
            leading: Icon(Icons.confirmation_number_outlined, color: PosDashboardScreen.primaryGreen),
            title: Text(v.customerName.isEmpty ? uiT('Customer') : v.customerName),
            subtitle: Text(uiF('{date} • {count} item(s) • {status}', {'date': _formatDateOnly(v.date), 'count': AppData.instance.itemsForSale(v.voucherNumber).length.toString(), 'status': uiT(status)})),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(mainAxisAlignment: MainAxisAlignment.center,crossAxisAlignment: CrossAxisAlignment.end,children:[Text(total.toStringAsFixed(2),style:const TextStyle(fontWeight:FontWeight.bold)),Text(uiF('Balance {balance}', {'balance': balance.toStringAsFixed(2)}),style:TextStyle(fontSize:11,color:statusColor))]),
                IconButton(
                  tooltip: uiT('Delete voucher'),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _confirmDelete(v),
                ),
              ],
            ),
            onTap: () => _openVoucher(v),
          );
        },
      ),
    );
  }
}

class VoucherDetailPage extends StatefulWidget {
  const VoucherDetailPage({super.key, required this.voucher});
  final Voucher voucher;
  @override State<VoucherDetailPage> createState() => _VoucherDetailPageState();
}

class _VoucherDetailPageState extends State<VoucherDetailPage> {
  final GlobalKey _voucherCaptureKey = GlobalKey();
  bool _capturingImage = false;

  Future<Uint8List?> _captureVoucherImage() async {
    try {
      // Let any pending frame finish rendering before we capture it.
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _voucherCaptureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareVoucherImage() async {
    if (_capturingImage) return;
    setState(() => _capturingImage = true);
    try {
      final bytes = await _captureVoucherImage();
      if (bytes == null) {
        throw StateError('Could not capture the voucher image.');
      }
      final name = widget.voucher.customerName.isEmpty
          ? 'Customer'
          : widget.voucher.customerName;

      try {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/voucher_${widget.voucher.voucherNumber}.png',
        );
        await file.writeAsBytes(bytes, flush: true);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: uiF('Voucher for {customer}', {'customer': name}),
          ),
        );
      } catch (_) {
        // Sharing files isn't available on this platform (e.g. Linux
        // desktop). Fall back to letting the user save it instead.
        final uri = await FilePicker.saveFile(
          fileName: 'voucher_${widget.voucher.voucherNumber}.png',
          bytes: bytes,
        );
        if (mounted && uri != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(uiT("Sharing isn't supported on this device — the voucher image was saved instead.")),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(uiError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _capturingImage = false);
    }
  }

  Future<void> _saveVoucherImage() async {
    if (_capturingImage) return;
    setState(() => _capturingImage = true);
    try {
      final bytes = await _captureVoucherImage();
      if (bytes == null) {
        throw StateError('Could not capture the voucher image.');
      }

      var savedToGallery = false;
      try {
        await Gal.putImageBytes(
          bytes,
          name: 'voucher_${widget.voucher.voucherNumber}',
        );
        savedToGallery = true;
      } catch (_) {
        // Gallery saving isn't available on this platform (e.g. Linux,
        // Windows, or web desktop). Fall back to a normal save dialog.
        savedToGallery = false;
      }

      if (!savedToGallery) {
        final uri = await FilePicker.saveFile(
          fileName: 'voucher_${widget.voucher.voucherNumber}.png',
          bytes: bytes,
        );
        if (uri == null) {
          // User cancelled the save dialog; nothing to report.
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              savedToGallery
                  ? uiT('Voucher image saved to your gallery')
                  : uiT('Voucher image saved'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(uiError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _capturingImage = false);
    }
  }

  Future<void> _editVoucher() async {
    final customer = TextEditingController(text: widget.voucher.customer);
    final currentPaid = AppData.instance.paidForSale(widget.voucher.voucherNumber);
    final paid = TextEditingController(text: currentPaid.toStringAsFixed(2));
    final allowedMethods = {'Cash', 'Bank', 'Mobile', 'Credit'};
    String method = allowedMethods.contains(widget.voucher.paymentMethod) ? widget.voucher.paymentMethod : 'Cash';
    DateTime date = widget.voucher.date;
    final total = AppData.instance.totalForSale(widget.voucher.voucherNumber);
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx,setDialogState) => AlertDialog(
      title: Text(uiT('Edit voucher')), content: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller: customer, decoration: InputDecoration(labelText:uiT('Customer'))),
        const SizedBox(height:10),
        TextField(controller: paid, keyboardType:TextInputType.number, decoration:InputDecoration(labelText:uiF('Amount paid (total {amount})', {'amount': total.toStringAsFixed(2)}))),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(initialValue: method.isEmpty?null:method, decoration:InputDecoration(labelText:uiT('Payment method')), items:[DropdownMenuItem(value:'Cash',child:Text(uiT('Cash'))),DropdownMenuItem(value:'Bank',child:Text(uiT('Bank'))),DropdownMenuItem(value:'Mobile',child:Text(uiT('Mobile'))),DropdownMenuItem(value:'Credit',child:Text(uiT('Credit')))], onChanged:(v)=>setDialogState(()=>method=v??'')),
        const SizedBox(height:10),
        OutlinedButton.icon(onPressed:() async { final picked=await showDatePicker(context:ctx,initialDate:date,firstDate:DateTime(2000),lastDate:DateTime(2100)); if(picked!=null)setDialogState(()=>date=picked); }, icon:const Icon(Icons.calendar_today), label:Text(uiF('Date {date}', {'date': _formatDateOnly(date)}))),
      ])), actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(uiT('Cancel'))),ElevatedButton(onPressed:() async { final amount=double.tryParse(paid.text.trim())??0; await AppData.instance.updateSalePayment(widget.voucher.voucherNumber, paid:amount, paymentMethod:method, date:date, customer:customer.text.trim(), paymentDate: amount != currentPaid ? DateTime.now() : widget.voucher.paymentDate); if(ctx.mounted)Navigator.pop(ctx); if(mounted)setState((){}); },child:Text(uiT('Save')))],
    )));
    customer.dispose(); paid.dispose();
  }

  @override Widget build(BuildContext context) {
    final total=AppData.instance.totalForSale(widget.voucher.voucherNumber); final paidAmount=AppData.instance.paidForSale(widget.voucher.voucherNumber); final balance=(total-paidAmount).clamp(0,double.infinity).toDouble(); final status=balance<=.005?'PAID':paidAmount>0?'PARTIALLY PAID':'UNPAID'; final payments=AppData.instance.paymentsForSale(widget.voucher.voucherNumber);
    return Scaffold(appBar:AppBar(title:Text(uiT('Voucher')),backgroundColor:PosDashboardScreen.primaryGreen,foregroundColor:Colors.white,actions:[
      IconButton(onPressed:_editVoucher,icon:const Icon(Icons.edit_outlined),tooltip:uiT('Edit voucher')),
      IconButton(
        onPressed: _capturingImage ? null : _shareVoucherImage,
        tooltip: uiT('Share as image'),
        icon: _capturingImage
            ? const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white))
            : const Icon(Icons.share_outlined),
      ),
      IconButton(
        onPressed: _capturingImage ? null : _saveVoucherImage,
        tooltip: uiT('Save as photo'),
        icon: const Icon(Icons.download_outlined),
      ),
    ]), body:Column(children:[
      Container(width:double.infinity,padding:const EdgeInsets.all(12),child:Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[Text(uiT(status),style:TextStyle(fontWeight:FontWeight.bold,color:status=='PAID'?Colors.green:status=='UNPAID'?Colors.red:Colors.orange)),Text(uiF('Paid {paid}', {'paid': paidAmount.toStringAsFixed(2)})),Text(uiF('Balance {balance}', {'balance': balance.toStringAsFixed(2)})) ])),
      Expanded(child:SingleChildScrollView(child:Column(children:[
        Padding(padding:const EdgeInsets.all(16),child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:380),child:RepaintBoundary(key:_voucherCaptureKey,child:VoucherPreviewCard(customerName:widget.voucher.customerName,items:AppData.instance.itemsForSale(widget.voucher.voucherNumber),paid:paidAmount,date:widget.voucher.date))))),
        Container(width:double.infinity,constraints:const BoxConstraints(maxWidth:520),padding:const EdgeInsets.fromLTRB(16,0,16,24),child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(uiT('Payment History'),style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
          const SizedBox(height:8),
          if(payments.isEmpty) Text(uiT('No payment transactions recorded.'))
          else ...payments.map((p)=>ListTile(contentPadding:EdgeInsets.zero,dense:true,leading:Icon(p.amount>=0?Icons.arrow_downward:Icons.undo,color:p.amount>=0?Colors.teal:Colors.orange),title:Text(uiF('{label} {amount}', {'label': p.amount>=0 ? uiT('Received') : uiT('Adjustment'), 'amount': p.amount.abs().toStringAsFixed(2)})),subtitle:Text('${_formatDateOnly(p.date)}${p.method.isNotEmpty?' • ${uiT(p.method)}':''}${p.note.isNotEmpty?' • ${uiLedgerNote(p.note)}':''}')))
        ])))),
      ]))),
    ]));
  }
}

// =====================================================================
// CYLINDER CYCLES
// =====================================================================

class CylinderTypesPage extends StatefulWidget {
  const CylinderTypesPage({super.key, required this.title});

  final String title;

  @override
  State<CylinderTypesPage> createState() => _CylinderTypesPageState();
}

class _CylinderTypesPageState extends State<CylinderTypesPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _totalController = TextEditingController(text: '0');
  String _baseType = '48kg';

  @override
  void dispose() {
    _nameController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  String _formatQty(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);

  String _categoryLabel(String baseType) =>
      baseType == '48kg' ? uiT('48 kg') : uiT('10v');

  Future<void> _addType() async {
    final name = _nameController.text.trim();
    final total = double.tryParse(_totalController.text.trim());
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Please enter a cylinder type name.'))),
      );
      return;
    }
    if (total == null || !total.isFinite || total < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Cylinder stock must be 0 or more.'))),
      );
      return;
    }

    try {
      final type = CylinderType(
        id: AppData.newId(),
        baseType: _baseType,
        name: name,
        totalQuantity: total,
      );
      await AppData.instance.addCylinderType(type);
      if (!mounted) return;
      _nameController.clear();
      _totalController.text = '0';
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiF('Cylinder type "{name}" added.', {'name': name}))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiError(e))),
      );
    }
  }

  Future<void> _setTotalQuantity(CylinderType type) async {
    final controller = TextEditingController(
      text: _formatQty(type.totalQuantity),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uiF('Set {type} quantity', {'type': type.name})),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: uiT('Currently in our possession'),
            suffixText: _categoryLabel(type.baseType),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(uiT('Cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              final quantity = double.tryParse(controller.text.trim());
              if (quantity == null || !quantity.isFinite || quantity < 0) return;
              Navigator.pop(dialogContext, quantity);
            },
            child: Text(uiT('Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;

    try {
      await AppData.instance.updateCylinderTypeTotalQuantity(type.id, value);
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiError(e))),
      );
    }
  }

  Future<void> _deleteType(CylinderType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uiT('Delete cylinder type?')),
        content: Text(
          uiF('Delete "{name}"? Existing cylinder-cycle records will not be deleted.', {'name': type.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(uiT('Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(uiT('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await AppData.instance.deleteCylinderType(type.id);
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = List<CylinderType>.from(AppData.instance.cylinderTypes)
      ..sort((a, b) {
        final baseCompare = a.baseType.compareTo(b.baseType);
        if (baseCompare != 0) return baseCompare;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(uiT(widget.title)),
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
        onPressed: _addType,
        icon: const Icon(Icons.add),
        label: Text(uiT('Add Type')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    uiT('Add Cylinder Type'),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _baseType,
                    decoration: InputDecoration(
                      labelText: uiT('Cylinder category'),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: '48kg', child: Text(uiT('48 kg'))),
                      DropdownMenuItem(value: '10v', child: Text(uiT('10v'))),
                    ],
                    onChanged: (value) =>
                        setState(() => _baseType = value ?? '48kg'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: uiT('Name of type'),
                      hintText: uiT('e.g. Standard 48 kg, Small 10v'),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addType(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _totalController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: uiT('Opening cylinder stock'),
                      helperText: uiT('Enter the cylinders you currently have. This is the stock starting balance.'),
                      suffixText: _categoryLabel(_baseType),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _addType,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PosDashboardScreen.primaryGreen,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.add),
                    label: Text(uiT('Add Cylinder Type')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            uiT('Cylinder Types'),
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (types.isEmpty)
            Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(uiT('No cylinder types have been added.')),
              ),
            )
          else
            ...types.map(
              (type) => Card(
                child: ListTile(
                  leading: const Icon(Icons.propane_tank_outlined),
                  title: Text(type.name),
                  subtitle: Text(
                    uiF('{category} • In our possession: {qty}', {
                      'category': _categoryLabel(type.baseType),
                      'qty': _formatQty(type.totalQuantity),
                    }),
                  ),
                  trailing: Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        tooltip: uiT('Set current quantity'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _setTotalQuantity(type),
                      ),
                      IconButton(
                        tooltip: uiT('Delete'),
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteType(type),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CylinderCyclesPage extends StatefulWidget {
  const CylinderCyclesPage({super.key, required this.title});

  final String title;

  @override
  State<CylinderCyclesPage> createState() => _CylinderCyclesPageState();
}

class _CylinderCyclesPageState extends State<CylinderCyclesPage> {
  final TextEditingController _givenController = TextEditingController();
  final TextEditingController _receivedController = TextEditingController();
  final TextEditingController _customerSearchController =
      TextEditingController();

  String? _selectedCustomer;
  String _customerSearchQuery = '';
  String? _selectedTypeId;
  DateTime _cycleDate = DateTime.now();

  @override
  void dispose() {
    _givenController.dispose();
    _receivedController.dispose();
    _customerSearchController.dispose();
    super.dispose();
  }

  List<Person> get _customers {
    final result = AppData.instance.people
        .where((person) => person.category.toLowerCase() == 'customer')
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  double _parseQty(String text) => double.tryParse(text.trim()) ?? 0;

  String _formatQty(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);

  String _dateText(DateTime date) => _formatDateOnly(date);

  String _categoryLabel(CylinderType type) =>
      type.baseType == '48kg' ? uiT('48 kg') : uiT('10v');

  String _directionText(double balance) {
    if (balance > 0.000001) {
      return uiF('Customer owes us {qty}', {'qty': _formatQty(balance)});
    }
    if (balance < -0.000001) {
      return uiF('We owe customer {qty}', {'qty': _formatQty(balance.abs())});
    }
    return uiT('Settled');
  }

  Color _balanceColor(double balance) {
    if (balance > 0.000001) return Colors.teal;
    if (balance < -0.000001) return Colors.redAccent;
    return Colors.green;
  }

  Future<void> _saveCycle() async {
    final customer = _selectedCustomer?.trim() ?? '';
    final given = _parseQty(_givenController.text);
    final received = _parseQty(_receivedController.text);
    final cylinderType = _selectedTypeId == null
        ? null
        : AppData.instance.cylinderTypeById(_selectedTypeId!);

    if (customer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Please select a customer'))),
      );
      return;
    }
    if (cylinderType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Please add and select a cylinder type'))),
      );
      return;
    }
    if (!given.isFinite || !received.isFinite || given < 0 || received < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Cylinder quantities must be 0 or more.'))),
      );
      return;
    }
    if (given <= 0 && received <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiT('Enter how much we give or receive'))),
      );
      return;
    }

    try {
      await AppData.instance.addCylinderCycle(
        CylinderCycle(
          cylinderTypeId: cylinderType.id,
          customer: customer,
          product: cylinderType.name,
          givenQuantity: given,
          receivedQuantity: received,
          date: _cycleDate,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uiError(e))),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _givenController.clear();
      _receivedController.clear();
      _cycleDate = DateTime.now();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(uiT('Cylinder cycle saved'))),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _cycleDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _cycleDate = picked);
    }
  }

  Future<bool> _confirmDeleteCycle(CylinderCycle cycle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uiT('Delete history record?')),
        content: Text(
          uiF(
          '{customer} • {type}\n\n{given}\n{received}\n{date}',
          {
            'customer': cycle.customer,
            'type': AppData.instance.cylinderTypeNameFor(cycle),
            'given': uiF('Given: {qty}', {'qty': _formatQty(cycle.givenQuantity)}),
            'received': uiF('Received: {qty}', {'qty': _formatQty(cycle.receivedQuantity)}),
            'date': uiF('Date: {date}', {'date': _dateText(cycle.date)}),
          },
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(uiT('Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(uiT('Delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      await AppData.instance.deleteCylinderCycle(cycle.id);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(uiError(e))),
        );
      }
      return false;
    }
  }

  List<CylinderCycle> _historyForCustomer(String customer) {
    final cycles = AppData.instance.cylinderCycles
        .where((cycle) => cycle.customer == customer)
        .toList();
    cycles.sort((a, b) => b.date.compareTo(a.date));
    return cycles;
  }

  Future<void> _viewCustomerHistory(String customer) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final cycles = _historyForCustomer(customer);
          final withCustomer = cycles
              .map((cycle) => cycle.balance)
              .where((balance) => balance > 0.000001)
              .fold<double>(0, (sum, balance) => sum + balance);
          final withUs = cycles
              .map((cycle) => cycle.balance)
              .where((balance) => balance < -0.000001)
              .fold<double>(0, (sum, balance) => sum + balance.abs());

          final grouped = <String, List<CylinderCycle>>{};
          for (final cycle in cycles) {
            final key = cycle.cylinderTypeId.isNotEmpty
                ? cycle.cylinderTypeId
                : cycle.product.trim().toLowerCase();
            grouped.putIfAbsent(key, () => []).add(cycle);
          }

          final typeBreakdowns = grouped.entries.map((entry) {
            final typeCycles = entry.value;
            final first = typeCycles.first;
            final type = first.cylinderTypeId.isNotEmpty
                ? AppData.instance.cylinderTypeById(first.cylinderTypeId)
                : null;
            final typeName = type?.name ?? first.product;
            final category = type == null ? '' : _categoryLabel(type);
            final given = typeCycles.fold<double>(
              0,
              (sum, cycle) => sum + cycle.givenQuantity,
            );
            final received = typeCycles.fold<double>(
              0,
              (sum, cycle) => sum + cycle.receivedQuantity,
            );
            final balance = typeCycles.fold<double>(
              0,
              (sum, cycle) => sum + cycle.balance,
            );

            return <String, dynamic>{
              'name': typeName,
              'category': category,
              'given': given,
              'received': received,
              'balance': balance,
            };
          }).toList()
            ..sort((a, b) => (a['name'] as String)
                .toLowerCase()
                .compareTo((b['name'] as String).toLowerCase()));

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.person_outline),
                const SizedBox(width: 8),
                Expanded(child: Text(customer)),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 760,
                maxHeight: 680,
              ),
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * .88,
                height: MediaQuery.sizeOf(context).height * .72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _customerSummaryBox(
                            icon: Icons.north_east,
                            label: uiT('With customer'),
                            value: _formatQty(withCustomer),
                            color: Colors.teal,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _customerSummaryBox(
                            icon: Icons.south_west,
                            label: uiT('With us'),
                            value: _formatQty(withUs),
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      uiT('Cylinder Type Breakdown'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (typeBreakdowns.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          uiT('No cylinder activity recorded for this customer.'),
                          style: const TextStyle(color: Colors.black54),
                        ),
                      )
                    else
                      Container(
                        constraints: const BoxConstraints(maxHeight: 190),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: typeBreakdowns.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = typeBreakdowns[index];
                            final typeName = item['name'] as String;
                            final category = item['category'] as String;
                            final given = item['given'] as double;
                            final received = item['received'] as double;
                            final balance = item['balance'] as double;
                            final color = _balanceColor(balance);

                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.propane_tank_outlined),
                              title: Text(
                                category.isEmpty
                                    ? typeName
                                    : '$typeName • $category',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                uiF('{given} • {received}', {
                                  'given': uiF('Given {qty}', {
                                    'qty': _formatQty(given),
                                  }),
                                  'received': uiF('Received {qty}', {
                                    'qty': _formatQty(received),
                                  }),
                                }),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _formatQty(balance.abs()),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: color,
                                    ),
                                  ),
                                  Text(
                                    balance > 0.000001
                                        ? uiT('with customer')
                                        : balance < -0.000001
                                            ? uiT('with us')
                                            : uiT('settled'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: color,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      uiT('Transactions'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: cycles.isEmpty
                          ? Center(
                              child: Text(
                                uiT('No transactions recorded for this customer.'),
                              ),
                            )
                          : ListView.separated(
                              itemCount: cycles.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final cycle = cycles[index];
                                final balance = cycle.balance;
                                final color = _balanceColor(balance);
                                final type = AppData.instance.cylinderTypeById(
                                  cycle.cylinderTypeId,
                                );
                                final typeName = type?.name ?? cycle.product;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: color.withValues(alpha: .12),
                                    foregroundColor: color,
                                    child: Icon(
                                      balance > 0
                                          ? Icons.arrow_upward
                                          : balance < 0
                                              ? Icons.arrow_downward
                                              : Icons.check,
                                    ),
                                  ),
                                  title: Text(
                                    '$typeName • ${_dateText(cycle.date)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    uiF('{given} • {received}\n{direction}', {
                                      'given': uiF('Given {qty}', {
                                        'qty': _formatQty(cycle.givenQuantity),
                                      }),
                                      'received': uiF('Received {qty}', {
                                        'qty': _formatQty(cycle.receivedQuantity),
                                      }),
                                      'direction': _directionText(balance),
                                    }),
                                  ),
                                  isThreeLine: true,
                                  trailing: IconButton(
                                    tooltip: uiT('Delete this transaction'),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    onPressed: () async {
                                      final deleted = await _confirmDeleteCycle(cycle);
                                      if (deleted) {
                                        setDialogState(() {});
                                        if (mounted) setState(() {});
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(uiT('Close')),
              ),
            ],
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _buildEntryForm() {
    final customers = _customers;
    if (_selectedCustomer != null &&
        !customers.any((customer) => customer.name == _selectedCustomer)) {
      _selectedCustomer = null;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              uiT('New Cylinder Cycle'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedCustomer,
              decoration: InputDecoration(
                labelText: uiT('Customer'),
                border: OutlineInputBorder(),
              ),
              hint: Text(
                customers.isEmpty ? uiT('No customers added yet') : uiT('Select customer'),
              ),
              items: customers
                  .map(
                    (customer) => DropdownMenuItem<String>(
                      value: customer.name,
                      child: Text(customer.name),
                    ),
                  )
                  .toList(),
              onChanged: customers.isEmpty
                  ? null
                  : (value) => setState(() => _selectedCustomer = value),
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final types = AppData.instance.cylinderTypes;
                if (_selectedTypeId == null ||
                    !types.any((type) => type.id == _selectedTypeId)) {
                  _selectedTypeId = types.isEmpty ? null : types.first.id;
                }
                return DropdownButtonFormField<String>(
                  initialValue: _selectedTypeId,
                  decoration: InputDecoration(
                    labelText: uiT('Cylinder Type'),
                    border: OutlineInputBorder(),
                  ),
                  hint: Text(
                    types.isEmpty ? uiT('Add a Cylinder Type first') : uiT('Select cylinder type'),
                  ),
                  items: types
                      .map(
                        (type) => DropdownMenuItem<String>(
                          value: type.id,
                          child: Text(
                            '${type.name} • ${_categoryLabel(type)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: types.isEmpty
                      ? null
                      : (value) => setState(() => _selectedTypeId = value),
                );
              },
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final vertical = constraints.maxWidth < 500;
                final given = TextField(
                  controller: _givenController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: uiT('How much we give'),
                    border: OutlineInputBorder(),
                  ),
                );
                final received = TextField(
                  controller: _receivedController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: uiT('How much we get'),
                    border: OutlineInputBorder(),
                  ),
                );
                if (vertical) {
                  return Column(
                    children: [
                      given,
                      const SizedBox(height: 10),
                      received,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: given),
                    const SizedBox(width: 10),
                    Expanded(child: received),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(uiF('Cycle date: {date}', {'date': _dateText(_cycleDate)})),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _saveCycle,
                style: ElevatedButton.styleFrom(
                  backgroundColor: PosDashboardScreen.primaryGreen,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.save_outlined),
                label: Text(
                  uiT('Save Cylinder Cycle'),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _customerSummaryBox({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerOverviewCard(String customer) {
    final cycles = _historyForCustomer(customer);
    final withCustomer = cycles
        .map((cycle) => cycle.balance)
        .where((balance) => balance > 0.000001)
        .fold<double>(0, (sum, balance) => sum + balance);
    final withUs = cycles
        .map((cycle) => cycle.balance)
        .where((balance) => balance < -0.000001)
        .fold<double>(0, (sum, balance) => sum + balance.abs());
    final totalActive = withCustomer + withUs;
    final hasActivity = cycles.isNotEmpty;
    final statusColor = withCustomer > 0.000001
        ? Colors.teal
        : withUs > 0.000001
            ? Colors.orange
            : Colors.black54;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.person_outline, color: statusColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    uiF('Total cylinders: {qty}', {
                      'qty': _formatQty(totalActive),
                    }),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: hasActivity ? Colors.black87 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (!hasActivity)
                    Text(
                      uiT('No cylinder activity'),
                      style: const TextStyle(color: Colors.black54),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          uiF('{qty} with customer', {
                            'qty': _formatQty(withCustomer),
                          }),
                          style: TextStyle(
                            color: withCustomer > 0.000001
                                ? Colors.teal
                                : Colors.black54,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          uiF('{qty} with us', {
                            'qty': _formatQty(withUs),
                          }),
                          style: TextStyle(
                            color: withUs > 0.000001
                                ? Colors.orange
                                : Colors.black54,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: () => _viewCustomerHistory(customer),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: Text(uiT('View')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerOverviewSection() {
    final customers = _customers;

    if (customers.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              const Icon(Icons.people_outline, size: 40, color: Colors.black45),
              const SizedBox(height: 8),
              Text(
                uiT('No customers added yet.'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                uiT('Add customers first, then their cylinder balances will appear here.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    final query = _customerSearchQuery.trim().toLowerCase();
    final filteredCustomers = query.isEmpty
        ? customers
        : customers.where((customer) {
            final name = customer.name.toLowerCase();
            final phone = customer.phone.toLowerCase();
            return name.contains(query) || phone.contains(query);
          }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _customerSearchController,
          onChanged: (value) {
            setState(() {
              _customerSearchQuery = value.trim().toLowerCase();
            });
          },
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: uiT('Search customer name or phone'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _customerSearchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: uiT('Clear search'),
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _customerSearchController.clear();
                      setState(() => _customerSearchQuery = '');
                    },
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (filteredCustomers.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const Icon(Icons.search_off, size: 40, color: Colors.black45),
                  const SizedBox(height: 8),
                  Text(
                    uiT('No customers match your search.'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    uiT('Try another customer name or phone number.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          )
        else
          ...filteredCustomers.map(
            (customer) => _customerOverviewCard(customer.name),
          ),
      ],
    );
  }

  Widget _stockTypeCard(CylinderType type) {
    final category = _categoryLabel(type);
    final quantity = type.totalQuantity;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: PosDashboardScreen.primaryGreen.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.propane_tank_outlined,
                color: PosDashboardScreen.primaryGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    category,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  uiT('We have'),
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                Text(
                  _formatQty(quantity),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _stockSection() {
    final types = List<CylinderType>.from(AppData.instance.cylinderTypes)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (types.isEmpty) {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(uiT('Add cylinder types first.')),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 20, color: Colors.black54),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    uiT('Cylinder stock is entered and adjusted on the Cylinder Types page.'),
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
        ...types.map(_stockTypeCard),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(uiT(widget.title)),
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEntryForm(),
                const SizedBox(height: 22),
                Text(
                  uiT('Cylinder Stock'),
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  uiT('Your current physical quantity. Cycle entries update this automatically.'),
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                _stockSection(),
                const SizedBox(height: 24),
                Text(
                  uiT('Customer Cylinders'),
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  uiT('All customers are listed here. Open a customer to see the exact cylinder types, balances, and transaction history.'),
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                _customerOverviewSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// DATA BACKUP
// =====================================================================

class DataBackupPage extends StatefulWidget {
  const DataBackupPage({super.key, required this.title});

  final String title;

  @override
  State<DataBackupPage> createState() => _DataBackupPageState();
}

class _DataBackupPageState extends State<DataBackupPage> {
  final TextEditingController _importController = TextEditingController();
  bool _importing = false;

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  Future<void> _copyExport() async {
    final json = AppData.instance.exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uiF('Backup copied ({count} characters). For large backups, save it as a file instead of using the clipboard.', {'count': json.length.toString()}),
          ),
        ),
      );
    }
  }

  Future<void> _saveExportFile() async {
    try {
      final json = AppData.instance.exportJson();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final uri = await FilePicker.saveFile(
        fileName: 'pos_backup_$stamp.json',
        bytes: Uint8List.fromList(utf8.encode(json)),
      );

      if (mounted && uri != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(uiF('Backup file saved ({count} characters).', {'count': json.length.toString()})),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(uiError(e)),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Future<void> _importRaw(String raw) async {
    final cleaned = raw.replaceFirst('\uFEFF', '').trim();
    if (cleaned.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(uiT('The backup is empty.'))),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uiT('Replace all data?')),
        content: Text(
          '${uiF('The backup is {count} characters long.', {'count': cleaned.length.toString()})} ${uiT('Importing it will overwrite everything currently stored on this device.')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(uiT('Cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(uiT('Import')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _importing = true);
    try {
      await AppData.instance.importJson(cleaned);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(uiT('Data imported successfully'))),
        );
        _importController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(uiError(e)),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importFromFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json', 'txt'],
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final raw = utf8.decode(bytes);
      await _importRaw(raw);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(uiError(e)),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Future<void> _importFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text ?? '';
      if (raw.isEmpty) {
        throw StateError('There is no text backup in the clipboard.');
      }
      _importController.text = raw;
      await _importRaw(raw);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(uiError(e))),
        );
      }
    }
  }

  Future<void> _import() async {
    await _importRaw(_importController.text);
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uiT('Erase all data?')),
        content: Text(
          uiT('This deletes every product, person, voucher, and ledger entry on this device. This cannot be undone.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(uiT('Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(uiT('Erase')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AppData.instance.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(uiT('All data erased'))),
        );
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(uiT(widget.title)),
        backgroundColor: PosDashboardScreen.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(uiT('Export'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  uiT('Save a complete snapshot of your data as a JSON backup. This is the recommended method for large backups because it does not depend on clipboard limits.'),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _saveExportFile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PosDashboardScreen.primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.save_alt_outlined),
                  label: Text(uiT('Save Backup File')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _copyExport,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: Text(uiT('Copy Backup to Clipboard')),
                ),
                const SizedBox(height: 32),
                Text(uiT('Import'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  uiT('For large backups, import the original .json/.txt file directly. This bypasses clipboard and text-box size limits. You can still paste smaller backups below.'),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _importing ? null : _importFromFile,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(uiT('Import Backup File')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _importing ? null : _importFromClipboard,
                  icon: const Icon(Icons.content_paste_go_outlined),
                  label: Text(uiT('Import from Clipboard')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _importController,
                  minLines: 6,
                  maxLines: 14,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: uiT('Paste a smaller backup JSON here'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _importing ? null : _import,
                  icon: _importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_upload_outlined),
                  label: Text(_importing ? uiT('Importing...') : uiT('Import Pasted Backup')),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                Text(uiT('Danger zone'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _clearAll,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(uiT('Erase All Data')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}