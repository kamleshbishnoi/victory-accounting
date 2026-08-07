class Txn {
  final String id;
  final String type; // "income" | "expense"
  final String desc;
  final double amount;
  final DateTime date;

  Txn({
    required this.id,
    required this.type,
    required this.desc,
    required this.amount,
    required this.date,
  });
}
