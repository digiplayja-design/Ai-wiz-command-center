String metaCount(dynamic value) =>
    '$value'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
String metaMoney(String currency, dynamic value) {
  final parts = '$value'.split('.');
  return '$currency ${metaCount(parts.first)}${parts.length > 1 ? '.${parts.last}' : ''}';
}
