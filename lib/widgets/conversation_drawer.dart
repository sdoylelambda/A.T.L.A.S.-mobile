import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ConversationEntry {
  final String  role;    // 'you' or 'atlas'
  final String  text;
  final DateTime time;
  ConversationEntry({required this.role, required this.text, required this.time});
}

class ConversationDrawer extends StatelessWidget {
  final List<ConversationEntry> entries;
  const ConversationDrawer({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text('No conversation yet',
          style: TextStyle(color: Color(0xFF4a5a6a), fontSize: 14)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e      = entries[i];
        final isYou  = e.role == 'you';
        return Align(
          alignment: isYou ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: e.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isYou ? const Color(0xFF1a3a6e) : const Color(0xFF1a1a2e),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isYou ? const Color(0xFF1a6aff) : const Color(0xFF2a2a4e),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isYou ? 'You' : 'Atlas',
                    style: TextStyle(
                      color: isYou ? const Color(0xFF4499ff) : const Color(0xFF66ccff),
                      fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(e.text,
                    style: const TextStyle(color: Color(0xFFc8d8e8), fontSize: 14, height: 1.4)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
