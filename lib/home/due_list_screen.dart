import 'package:flutter/material.dart';

import 'due_items.dart';
import 'due_row.dart';

/// Every payment of one dashboard group.
class DueListScreen extends StatelessWidget {
  const DueListScreen({super.key, required this.title, required this.items});

  final String title;
  final List<DueItem> items;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        children: [for (final i in items) DueRow(item: i, now: now)],
      ),
    );
  }
}
