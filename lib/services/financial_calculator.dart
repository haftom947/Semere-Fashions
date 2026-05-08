import 'dart:convert';

import 'package:flutter/material.dart';

import 'database_helper.dart';

class FinancialCalculator {
  FinancialCalculator({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  Future<FinancialSummary> calculateSummary({
    required DateTimeRange? range,
    String? branchId,
    String? currency,
  }) async {
    return _calculateSummaryInternal(
      range: range,
      branchId: branchId,
      currency: currency,
    );
  }

  Future<List<CurrencySummary>> calculatePerCurrency({
    required DateTimeRange? range,
    String? branchId,
  }) async {
    // Use the existing internal calculation but request per-currency summaries.
    final base = await _calculateSummaryInternal(range: range, branchId: branchId);

    // Gather currencies from orderProfitItems; fallback to ETB if none.
    final currencySet = <String>{};
    for (final item in base.orderProfitItems) {
      if (item.currency.isNotEmpty) currencySet.add(item.currency);
    }
    if (currencySet.isEmpty) currencySet.add('ETB');

    final currencies = currencySet.toList()..sort();
    final results = <CurrencySummary>[];
    for (final currency in currencies) {
      final per = await _calculateSummaryInternal(
        range: range,
        branchId: branchId,
        currency: currency,
      );
      results.add(CurrencySummary(
        currency: currency,
        revenue: per.revenue,
        cogs: per.cogs,
        grossProfit: per.grossProfit,
        commissionExpenses: per.commissionExpenses,
        lossesExpense: per.losses,
        netProfit: per.netProfit,
        overheadExpenses: per.overheadExpenses,
        expenseItems: per.expenseItems,
        orderProfitItems: per.orderProfitItems,
      ));
    }
    return results;
  }

  Future<FinancialSummary> _calculateSummaryInternal({
    required DateTimeRange? range,
    String? branchId,
    String? currency,
  }) async {
    final startMillis = range == null ? 0 : range.start.millisecondsSinceEpoch;
    final endMillis = range == null
        ? DateTime.now().millisecondsSinceEpoch
        : range.end.add(const Duration(days: 1)).millisecondsSinceEpoch - 1;

    final allOrders = await _dbHelper.getOrdersInDateRange(
      startMillis,
      endMillis,
      branchId: branchId,
    );
    final commissions = await _dbHelper.getCommissionsInDateRange(
      startMillis,
      endMillis,
      branchId: branchId,
    );
    final fuelLogs = await _dbHelper.getFuelLogsInDateRange(
      startMillis,
      endMillis,
    );
    final maintenanceLogs = await _dbHelper.getMaintenanceLogsInDateRange(
      startMillis,
      endMillis,
    );
    final materialUsage = await _dbHelper.getMaterialUsageInDateRange(
      startMillis,
      endMillis,
    );
    final payments = await _dbHelper.getPaymentsInDateRange(
      startMillis,
      endMillis,
      branchId: branchId,
    );
    final losses = await _dbHelper.getLossesInDateRange(
      startMillis,
      endMillis,
      branchId: branchId,
    );
    final landlordPayments = await _dbHelper.getLandlordPaymentsInDateRange(
      startMillis,
      endMillis,
    );
    final materials = await _dbHelper.query('materials');
    final products = await _dbHelper.query('products');

    final ordersById = <String, Map<String, dynamic>>{
      for (final order in allOrders)
        if ((order['id']?.toString() ?? '').isNotEmpty)
          order['id'].toString(): order,
    };
    bool withinRange(dynamic value, int start, int end) {
      final timestamp = _toInt(value);
      return timestamp >= start && timestamp <= end;
    }

    bool matchesCurrency(Map<String, dynamic> record) {
      if (currency == null) return true;
      return (record['currency']?.toString() ?? 'ETB') == currency;
    }

    final activeOrders = allOrders
        .where(
          (order) =>
              (order['status'] as String?)?.toLowerCase() != 'cancelled' &&
              matchesCurrency(order) &&
              withinRange(order['createdAt'], startMillis, endMillis),
        )
        .toList();
    final cancelledOrders = allOrders
        .where(
          (order) =>
              (order['status'] as String?)?.toLowerCase() == 'cancelled' &&
              matchesCurrency(order),
        )
        .toList();
    final activeOrderIds = {
      for (final order in activeOrders)
        if ((order['id']?.toString() ?? '').isNotEmpty) order['id'].toString(),
    };
    bool matchesBranch(Map<String, dynamic> record) {
      if (branchId == null) return true;
      if (record['branchId']?.toString() == branchId) return true;
      final orderId = record['orderId']?.toString();
      if (orderId == null || orderId.isEmpty) return false;
      return ordersById[orderId]?['branchId']?.toString() == branchId;
    }

    final materialNamesById = <String, String>{
      for (final material in materials)
        if ((material['id'] as String?)?.isNotEmpty ?? false)
          material['id'] as String:
              (material['name'] as String?) ?? material['id'] as String,
    };
    final productById = <String, Map<String, dynamic>>{
      for (final product in products)
        if ((product['id'] as String?)?.isNotEmpty ?? false)
          product['id'] as String: product,
    };

    final cancelledOrderIds = {
      for (final order in cancelledOrders)
        if ((order['id']?.toString() ?? '').isNotEmpty) order['id'].toString(),
    };
    final revenueByOrderId = <String, double>{};
    double cancelledPayments = 0.0;
    for (final payment in payments) {
      final orderId = payment['orderId']?.toString();
      if (orderId == null || orderId.isEmpty) continue;
      final amount = _toDouble(payment['amount']);
      final signedAmount =
          payment['type']?.toString() == 'refund' ? -amount : amount;

      if (activeOrderIds.contains(orderId)) {
        revenueByOrderId[orderId] =
            (revenueByOrderId[orderId] ?? 0.0) + signedAmount;
      } else if (cancelledOrderIds.contains(orderId)) {
        cancelledPayments += signedAmount;
      }
    }
    if (cancelledPayments < 0) {
      cancelledPayments = 0.0;
    }

    final activeCommissions = commissions
        .where((commission) => activeOrderIds.contains(commission['orderId']?.toString()))
        .toList();

    double revenue = 0.0;

    final expenseItems = <ExpenseItem>[];
    final orderProfitItems = <OrderProfitItem>[];
    double salesTotal = 0.0;
    double cogsFromOrders = 0.0;
    double orderMaterialCogs = 0.0;

    for (final order in activeOrders) {
      final createdAt = _toInt(order['createdAt']);
      final status = (order['status'] as String?)?.toLowerCase() ?? '';
      final totalAmount = _toDouble(order['totalAmount']);
      final orderId = order['id']?.toString() ?? '';
      final actualRevenue = revenueByOrderId[orderId] ?? 0.0;

      if (status != 'returned') {
        salesTotal += totalAmount;
      }
      revenue += actualRevenue;

      double linkedOrderMaterialCost = 0.0;
      if (status == 'completed' || status == 'delivered') {
        final cogsAmount = _toDouble(order['cogs']);
        cogsFromOrders += cogsAmount;

        double itemCogsTotal = 0.0;
        final rawItems = order['items'];
        final orderItems = rawItems is String
            ? (jsonDecode(rawItems) as List<dynamic>)
            : List<dynamic>.from(rawItems as List? ?? const []);
        for (final rawItem in orderItems) {
          if (rawItem is! Map) continue;
          final item = Map<String, dynamic>.from(rawItem);
          final productId = item['productId']?.toString();
          if (productId == null || productId.isEmpty) continue;

          final product = productById[productId];
          if (product == null) continue;

          final quantity = _toDouble(item['quantity']);
          final unitCost = _toDouble(product['costPrice']);
          final lineCogs = quantity * unitCost;
          if (lineCogs <= 0) continue;

          itemCogsTotal += lineCogs;
          expenseItems.add(
            ExpenseItem(
              category: 'COGS',
              title: product['name'] ?? item['description'] ?? 'Product',
              subtitle:
                  'Order #${_shortOrderId(orderId)} - Qty ${quantity.toStringAsFixed(0)} x ${order['currency'] ?? 'ETB'} ${unitCost.toStringAsFixed(2)}',
              amount: lineCogs,
              date: createdAt,
              branchId: order['branchId']?.toString(),
              currency: order['currency']?.toString() ?? 'ETB',
            ),
          );
        }

        for (final usage in materialUsage) {
          final usageType = usage['type']?.toString() ?? 'order';
          final usageOrderId = usage['orderId']?.toString();
          if (usageType != 'order' || usageOrderId != orderId) continue;
          if (!matchesBranch(usage)) continue;
          final amount = _toDouble(usage['cost']);
          if (amount <= 0) continue;
          linkedOrderMaterialCost += amount;
          expenseItems.add(
            ExpenseItem(
              category: 'COGS',
              title:
                  materialNamesById[usage['material_id']?.toString()] ??
                  usage['material_id']?.toString() ??
                  'Order material usage',
              subtitle: 'Order #${_shortOrderId(orderId)}',
              amount: amount,
              date: createdAt,
              branchId: order['branchId']?.toString(),
              currency: order['currency']?.toString() ?? 'ETB',
            ),
          );
        }

        orderMaterialCogs += linkedOrderMaterialCost;

        if (cogsAmount > itemCogsTotal) {
          expenseItems.add(
            ExpenseItem(
              category: 'COGS',
              title: 'Unmapped COGS',
              subtitle: 'Order #${_shortOrderId(orderId)}',
              amount: cogsAmount - itemCogsTotal,
              date: createdAt,
              branchId: order['branchId']?.toString(),
              currency: order['currency']?.toString() ?? 'ETB',
            ),
          );
        }
      }

      final orderCommissions = activeCommissions
          .where((commission) {
            if (commission['status'] == 'voided') return false;
            if (commission['orderId']?.toString() != orderId) return false;
            return matchesBranch(commission);
          })
          .fold<double>(
            0.0,
            (total, commission) => total + _toDouble(commission['amount']),
          );
      final cogsValue = _toDouble(order['cogs']) + linkedOrderMaterialCost;
      final idealRevenue = totalAmount;
      orderProfitItems.add(
        OrderProfitItem(
          orderId: orderId,
          customerName: order['customerName']?.toString() ?? 'Unknown',
          status: order['status']?.toString() ?? '',
          actualRevenue: actualRevenue,
          idealRevenue: idealRevenue,
          cogs: cogsValue,
          commissions: orderCommissions,
          actualProfit: actualRevenue - cogsValue - orderCommissions,
          idealProfit: idealRevenue - cogsValue - orderCommissions,
          date: createdAt,
          branchId: order['branchId']?.toString(),
          currency: order['currency']?.toString() ?? 'ETB',
        ),
      );
    }

    double tailorCommissions = 0.0;
    double salesCommissions = 0.0;
    double deliveryCommissions = 0.0;
    double commissionExpenses = 0.0;
    for (final commission in activeCommissions) {
      if (commission['status'] == 'voided') continue;
      final effectiveDate = commission['createdAt'] ?? commission['paidAt'];
      if (!matchesBranch(commission)) continue;
      final amount = _toDouble(commission['amount']);
      commissionExpenses += amount;
      switch (commission['type']) {
        case 'tailor':
          tailorCommissions += amount;
          break;
        case 'sales':
          salesCommissions += amount;
          break;
        case 'delivery':
          deliveryCommissions += amount;
          break;
      }
      final linkedOrder = ordersById[commission['orderId']?.toString() ?? ''];
      expenseItems.add(
        ExpenseItem(
          category: 'Commission',
          title: commission['employeeName']?.toString() ?? 'Commission',
          subtitle:
              'Order #${_shortOrderId(commission['orderId']?.toString() ?? '')}',
          amount: amount,
          date: _toInt(effectiveDate),
          branchId:
              linkedOrder?['branchId']?.toString() ??
              commission['branchId']?.toString(),
          currency: linkedOrder?['currency']?.toString() ?? currency ?? 'ETB',
        ),
      );
    }

    double fuelExpenses = 0.0;
    for (final fuel in fuelLogs) {
      if (!matchesBranch(fuel)) continue;
      if (currency != null && currency != 'ETB') continue;
      final amount = _toDouble(fuel['cost']);
      fuelExpenses += amount;
      expenseItems.add(
        ExpenseItem(
          category: 'Fuel',
          title: fuel['vehicleId']?.toString() ?? 'Fuel expense',
          subtitle: 'Odometer ${fuel['odometer'] ?? '-'}',
          amount: amount,
          date: _toInt(fuel['date']),
          branchId: fuel['branchId']?.toString(),
          currency: 'ETB',
        ),
      );
    }

    double maintenanceExpenses = 0.0;
    for (final maintenance in maintenanceLogs) {
      if (!matchesBranch(maintenance)) continue;
      if (currency != null && currency != 'ETB') continue;
      final amount = _toDouble(maintenance['cost']);
      maintenanceExpenses += amount;
      expenseItems.add(
        ExpenseItem(
          category: 'Maintenance',
          title: maintenance['type']?.toString() ?? 'Maintenance',
          subtitle:
              maintenance['description']?.toString() ??
              maintenance['notes']?.toString() ??
              'Maintenance expense',
          amount: amount,
          date: _toInt(maintenance['date']),
          branchId: maintenance['branchId']?.toString(),
          currency: 'ETB',
        ),
      );
    }

    double materialExpenses = 0.0;
    for (final usage in materialUsage) {
      if (!matchesBranch(usage)) continue;
      final usageType = usage['type']?.toString() ?? 'order';
      if (usageType != 'general') continue;
      if (currency != null && currency != 'ETB') continue;
      final amount = _toDouble(usage['cost']);
      materialExpenses += amount;
      expenseItems.add(
        ExpenseItem(
          category: 'Material',
          title:
              materialNamesById[usage['material_id']?.toString()] ??
              usage['material_id']?.toString() ??
              'General material usage',
          subtitle: 'Qty ${_toDouble(usage['quantity']).toStringAsFixed(0)}',
          amount: amount,
          date: _toInt(usage['date']),
          branchId: usage['branchId']?.toString(),
          currency: 'ETB',
        ),
      );
    }

    double lossesExpense = 0.0;
    for (final loss in losses) {
      if (!matchesBranch(loss)) continue;
      if (currency != null && currency != 'ETB') continue;
      final amount = _toDouble(loss['amount']);
      if (amount <= 0) continue;
      lossesExpense += amount;
      expenseItems.add(
        ExpenseItem(
          category: 'Loss',
          title: loss['type']?.toString() ?? 'Loss',
          subtitle: loss['reason']?.toString() ?? 'Uncategorised loss',
          amount: amount,
          date: _toInt(loss['date']),
          branchId: loss['branchId']?.toString(),
          currency: 'ETB',
        ),
      );
    }

    double rentalExpense = 0.0;
    for (final payment in landlordPayments) {
      if (currency != null && currency != 'ETB') continue;
      final amount = _toDouble(payment['amount']);
      if (amount <= 0) continue;
      rentalExpense += amount;
      expenseItems.add(
        ExpenseItem(
          category: 'Rent Expense',
          title: payment['landlordName']?.toString() ?? 'Landlord',
          subtitle: 'Property rent',
          amount: amount,
          date: _toInt(payment['paidAt']),
          branchId: null,
          currency: 'ETB',
        ),
      );
    }

    expenseItems.sort((a, b) => b.date.compareTo(a.date));
    orderProfitItems.sort((a, b) => b.date.compareTo(a.date));
    final actualOrderProfitTotal = orderProfitItems.fold<double>(
      0.0,
      (total, item) => total + item.actualProfit,
    );
    final idealOrderProfitTotal = orderProfitItems.fold<double>(
      0.0,
      (total, item) => total + item.idealProfit,
    );

    final cogs = cogsFromOrders + orderMaterialCogs;
    final otherExpenses = commissionExpenses; // only order-linked commissions
    final overheadExpenses = fuelExpenses + maintenanceExpenses + rentalExpense + materialExpenses;
    final grossProfit = revenue - cogs;
    final netProfit = grossProfit - otherExpenses - lossesExpense;
    final weekProfit = netProfit;

    return FinancialSummary(
      revenue: revenue,
      salesTotal: salesTotal,
      cogs: cogs,
      cogsFromOrders: cogsFromOrders,
      tailorCommissions: tailorCommissions,
      salesCommissions: salesCommissions,
      deliveryCommissions: deliveryCommissions,
      commissionExpenses: commissionExpenses,
      fuelExpenses: fuelExpenses,
      maintenanceExpenses: maintenanceExpenses,
      materialExpenses: materialExpenses,
      cancelledPayments: cancelledPayments,
      losses: lossesExpense,
      otherExpenses: otherExpenses,
      overheadExpenses: overheadExpenses,
      grossProfit: grossProfit,
      netProfit: netProfit,
      actualOrderProfitTotal: actualOrderProfitTotal,
      idealOrderProfitTotal: idealOrderProfitTotal,
      totalExpenses: otherExpenses + lossesExpense,
      profit: netProfit,
      weekProfit: weekProfit,
      expenseItems: expenseItems,
      orderProfitItems: orderProfitItems,
    );
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is String) return double.tryParse(value) ?? 0.0;
    return (value as num?)?.toDouble() ?? 0.0;
  }

  int _toInt(dynamic value) => (value as num?)?.toInt() ?? 0;

  String _shortOrderId(String id) {
    if (id.isEmpty) return '';
    return id.substring(0, id.length < 6 ? id.length : 6);
  }
}

class FinancialSummary {
  const FinancialSummary({
    required this.revenue,
    required this.salesTotal,
    required this.cogs,
    required this.cogsFromOrders,
    required this.tailorCommissions,
    required this.salesCommissions,
    required this.deliveryCommissions,
    required this.commissionExpenses,
    required this.fuelExpenses,
    required this.maintenanceExpenses,
    required this.materialExpenses,
    required this.cancelledPayments,
    required this.overheadExpenses,
    required this.losses,
    required this.otherExpenses,
    required this.grossProfit,
    required this.netProfit,
    required this.actualOrderProfitTotal,
    required this.idealOrderProfitTotal,
    required this.totalExpenses,
    required this.profit,
    required this.weekProfit,
    required this.expenseItems,
    required this.orderProfitItems,
  });

  final double revenue;
  final double salesTotal;
  final double cogs;
  final double cogsFromOrders;
  final double tailorCommissions;
  final double salesCommissions;
  final double deliveryCommissions;
  final double commissionExpenses;
  final double fuelExpenses;
  final double maintenanceExpenses;
  final double materialExpenses;
  final double overheadExpenses;
  final double cancelledPayments;
  final double losses;
  final double otherExpenses;
  final double grossProfit;
  final double netProfit;
  final double actualOrderProfitTotal;
  final double idealOrderProfitTotal;
  final double totalExpenses;
  final double profit;
  final double weekProfit;
  final List<ExpenseItem> expenseItems;
  final List<OrderProfitItem> orderProfitItems;
}

class CurrencyFinancialSummary {
  const CurrencyFinancialSummary({
    required this.currency,
    required this.summary,
  });

  final String currency;
  final FinancialSummary summary;
}

/// Simplified per-currency summary used by UI components.
class CurrencySummary {
  CurrencySummary({
    required this.currency,
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    required this.commissionExpenses,
    required this.lossesExpense,
    required this.netProfit,
    required this.overheadExpenses,
    required this.expenseItems,
    required this.orderProfitItems,
  });

  final String currency;
  final double revenue;
  final double cogs;
  final double grossProfit;
  final double commissionExpenses;
  final double lossesExpense;
  final double netProfit;
  final double overheadExpenses;
  final List<ExpenseItem> expenseItems;
  final List<OrderProfitItem> orderProfitItems;
}

class ExpenseItem {
  const ExpenseItem({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.date,
    this.branchId,
    this.currency = 'ETB',
  });

  final String category;
  final String title;
  final String subtitle;
  final double amount;
  final int date;
  final String? branchId;
  final String currency;

  Map<String, dynamic> toMap() => {
    'category': category,
    'title': title,
    'subtitle': subtitle,
    'amount': amount,
    'date': date,
    'branchId': branchId,
    'currency': currency,
  };
}

class OrderProfitItem {
  const OrderProfitItem({
    required this.orderId,
    required this.customerName,
    required this.status,
    required this.actualRevenue,
    required this.idealRevenue,
    required this.cogs,
    required this.commissions,
    required this.actualProfit,
    required this.idealProfit,
    required this.date,
    this.branchId,
    this.currency = 'ETB',
  });

  final String orderId;
  final String customerName;
  final String status;
  final double actualRevenue;
  final double idealRevenue;
  final double cogs;
  final double commissions;
  final double actualProfit;
  final double idealProfit;
  final int date;
  final String? branchId;
  final String currency;

  Map<String, dynamic> toMap() => {
    'orderId': orderId,
    'customerName': customerName,
    'status': status,
    'actualRevenue': actualRevenue,
    'idealRevenue': idealRevenue,
    'cogs': cogs,
    'commissions': commissions,
    'actualProfit': actualProfit,
    'idealProfit': idealProfit,
    'date': date,
    'branchId': branchId,
    'currency': currency,
  };
}
