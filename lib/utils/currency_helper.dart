class CurrencyHelper {
  static String getSymbol(String currencyCode) {
    switch (currencyCode) {
      case 'ETB':
        return 'ETB';
      case 'AED':
        return 'AED';
      case 'SAR':
        return 'SAR';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return currencyCode;
    }
  }

  static String formatAmount(num? amount, String? currencyCode) {
    final value = amount ?? 0;
    final symbol = getSymbol(currencyCode ?? 'ETB');
    return '$symbol ${value.toStringAsFixed(2)}';
  }
}
