import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:orpheus_project/config.dart';

/// A purchasable plan, defined server-side (prices are never hardcoded in the app).
class Tariff {
  final String id;
  final String title;
  final int durationDays; // 0 = lifetime
  final String priceUsdt; // kept as string to avoid float rounding

  const Tariff({
    required this.id,
    required this.title,
    required this.durationDays,
    required this.priceUsdt,
  });

  factory Tariff.fromJson(Map<String, dynamic> j) => Tariff(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        durationDays: j['duration_days'] is int
            ? j['duration_days'] as int
            : int.tryParse('${j['duration_days']}') ?? 0,
        priceUsdt: (j['price_usdt'] ?? '').toString(),
      );
}

/// A payment invoice: a fresh TRON address per order plus the exact amount.
class Invoice {
  final String orderId;
  final String address;
  final String amountUsdt;
  final String network; // e.g. "TRC20"
  final DateTime? expiresAt;

  const Invoice({
    required this.orderId,
    required this.address,
    required this.amountUsdt,
    required this.network,
    this.expiresAt,
  });

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        orderId: j['order_id'].toString(),
        address: (j['address'] ?? '').toString(),
        amountUsdt: (j['amount_usdt'] ?? '').toString(),
        network: (j['network'] ?? 'TRC20').toString(),
        expiresAt: _parseExpiry(j['expires_at']),
      );

  static DateTime? _parseExpiry(dynamic v) {
    if (v == null) return null;
    // epoch seconds
    if (v is int) {
      return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true).toLocal();
    }
    // ISO-8601 string
    return DateTime.tryParse(v.toString())?.toLocal();
  }
}

enum PurchaseStatus { pending, seen, confirmed, expired, unknown }

/// Client for the server-driven USDT-TRC20 purchase flow.
/// See docs/USDT_TRON_SPEC.md. Activation is decided server-side from the chain;
/// this client only creates invoices and polls status.
class PurchaseService {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  Future<List<Tariff>> fetchTariffs() async {
    final url = Uri.parse(AppConfig.httpUrl('/api/purchase/tariffs'));
    final resp = await http.get(url).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('tariffs failed: ${resp.statusCode}');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final list = (data['tariffs'] as List?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Tariff.fromJson)
        .toList(growable: false);
  }

  Future<Invoice> createInvoice({
    required String tariffId,
    required String pubkey,
  }) async {
    final url = Uri.parse(AppConfig.httpUrl('/api/purchase/invoice'));
    final resp = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'pubkey': pubkey, 'tariff_id': tariffId}),
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception('invoice failed: ${resp.statusCode}');
    }
    return Invoice.fromJson(json.decode(resp.body) as Map<String, dynamic>);
  }

  Future<PurchaseStatus> getStatus(String orderId) async {
    final url = Uri.parse(
        AppConfig.httpUrl('/api/purchase/status?order_id=$orderId'));
    final resp = await http.get(url).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return PurchaseStatus.unknown;
    final data = json.decode(resp.body) as Map<String, dynamic>;
    switch ((data['status'] ?? '').toString()) {
      case 'pending':
        return PurchaseStatus.pending;
      case 'seen':
        return PurchaseStatus.seen;
      case 'confirmed':
      case 'active':
        return PurchaseStatus.confirmed;
      case 'expired':
        return PurchaseStatus.expired;
      default:
        return PurchaseStatus.unknown;
    }
  }
}
