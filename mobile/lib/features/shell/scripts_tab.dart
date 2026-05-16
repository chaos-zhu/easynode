import 'package:flutter/material.dart';

class ScriptsTab extends StatelessWidget {
  const ScriptsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Scripts')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_books_outlined, size: 48, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              '即将上线：脚本库',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
