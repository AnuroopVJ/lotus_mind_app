// lib/reflections.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart' show kVercelApiUrl;

const _moodIcons = <int, IconData>{
  1: Icons.sentiment_very_dissatisfied,
  2: Icons.sentiment_dissatisfied,
  3: Icons.sentiment_neutral,
  4: Icons.sentiment_satisfied,
  5: Icons.sentiment_very_satisfied,
};

final _crisisPatterns = <RegExp>[
  RegExp(
    r"\b(kill myself|end my life|want to die|suicide)\b",
    caseSensitive: false,
  ),
  RegExp(
    r"\b(mujhe marna hai|marna chahta hoon|marna chahti hoon)\b",
    caseSensitive: false,
  ),
  RegExp(r"\b(sleep forever|don'?t want to wake up)\b", caseSensitive: false),
];

bool looksLikeCrisis(String text) =>
    _crisisPatterns.any((r) => r.hasMatch(text));

Future<void> showCrisisDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.favorite_outline),
      title: const Text("You're not alone"),
      content: const Text(
        "That sounds really heavy, and I'm glad you wrote it down. "
        "I can't help with something this serious on my own.\n\n"
        "Please talk to someone now:\n"
        "• Tele-MANAS: 14416 (24/7)\n"
        "• KIRAN: 1800-599-0019 (24/7)\n"
        "• A trusted adult near you",
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class Reflection {
  Reflection({
    required this.id,
    required this.mood,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'mood': mood,
        'title': title,
        'body': body,
        'created_at': createdAt.toIso8601String(),
      };

  factory Reflection.fromJson(Map<String, dynamic> r) => Reflection(
        id: r['id'] as String,
        mood: (r['mood'] as num).toInt(),
        title: r['title'] as String?,
        body: r['body'] as String,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      );

  final String id;
  final int mood;
  final String? title;
  final String body;
  final DateTime createdAt;

  String get heading {
    if (title != null && title!.isNotEmpty) return title!;
    final line = body.split('\n').first.trim();
    return line.length > 50 ? '${line.substring(0, 50)}...' : line;
  }
}

String _fmtDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
}

void _snack(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------
class ReflectionsPage extends StatefulWidget {
  const ReflectionsPage({super.key});

  @override
  State<ReflectionsPage> createState() => _ReflectionsPageState();
}

class _ReflectionsPageState extends State<ReflectionsPage> {
  List<Reflection> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('local_reflections');
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _items = [
          for (final item in list) Reflection.fromJson(item as Map<String, dynamic>)
        ];
        _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ReflectionEditorPage()),
    );
    if (saved == true) _load();
  }

  Future<void> _openDetail(Reflection r) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReflectionDetailPage(entry: r)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget body;
    if (_loading && _items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_items.isEmpty) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nothing here yet. Tap "New reflection" to write your first one.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final r = _items[i];
            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(_moodIcons[r.mood], color: scheme.primary),
                title: Text(
                  r.heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_fmtDate(r.createdAt)}\n${r.body}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                onTap: () => _openDetail(r),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reflections')),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        icon: const Icon(Icons.edit),
        label: const Text('New reflection'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Editor
// ---------------------------------------------------------------------------
class ReflectionEditorPage extends StatefulWidget {
  const ReflectionEditorPage({super.key});

  @override
  State<ReflectionEditorPage> createState() => _ReflectionEditorPageState();
}

class _ReflectionEditorPageState extends State<ReflectionEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  int _mood = 3;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final title = _title.text.trim();
    final body = _body.text.trim();

    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final newEntry = Reflection(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        mood: _mood,
        title: title.isEmpty ? null : title,
        body: body,
        createdAt: DateTime.now(),
      );

      final raw = prefs.getString('local_reflections');
      List<dynamic> list = raw != null ? jsonDecode(raw) as List : [];
      list.add(newEntry.toJson());
      await prefs.setString('local_reflections', jsonEncode(list));

      if (!mounted) return;
      if (looksLikeCrisis('$title $body')) await showCrisisDialog(context);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      _snack(context, 'Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('New reflection')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('How are you feeling?', style: textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final e in _moodIcons.entries)
                    ButtonSegment<int>(
                      value: e.key,
                      icon: Icon(e.value),
                      tooltip: 'Mood ${e.key} of 5',
                    ),
                ],
                selected: {_mood},
                onSelectionChanged: (s) => setState(() => _mood = s.first),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _title,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Title (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _body,
                maxLength: 10000,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                minLines: 6,
                maxLines: null,
                decoration: const InputDecoration(
                  labelText: 'What is on your mind?',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Write something first'
                    : null,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Save reflection'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail + opt-in AI reflection
// ---------------------------------------------------------------------------
class ReflectionDetailPage extends StatefulWidget {
  const ReflectionDetailPage({super.key, required this.entry});

  final Reflection entry;

  @override
  State<ReflectionDetailPage> createState() => _ReflectionDetailPageState();
}

class _ReflectionDetailPageState extends State<ReflectionDetailPage> {
  bool _aiLoading = false;
  String? _aiText;

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this reflection?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('local_reflections');
      if (raw != null) {
        List<dynamic> list = jsonDecode(raw) as List;
        list.removeWhere((item) => item['id'] == widget.entry.id);
        await prefs.setString('local_reflections', jsonEncode(list));
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      _snack(context, 'Could not delete. Try again.');
    }
  }

  Future<void> _reflectWithAi() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reflect with AI?'),
        content: const Text(
          'This sends the text of this one entry to an AI service to write a '
          'short reflection. Nothing else from your journal is sent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (agreed != true) return;

    final e = widget.entry;
    final text = StringBuffer('Mood: ${e.mood}/5\n');
    if (e.title != null && e.title!.isNotEmpty)
      text.writeln('Title: ${e.title}');
    text.write(e.body);

    setState(() {
      _aiLoading = true;
      _aiText = null;
    });
    try {
      final res = await http.post(
        Uri.parse(kVercelApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'purpose': 'reflection',
          'messages': [
            {'role': 'user', 'content': text.toString()},
          ],
          'temperature': 0.4,
          'max_tokens': 300,
        }),
      );

      if (res.statusCode != 200) {
        throw Exception('AI unavailable (${res.statusCode})');
      }

      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data is Map && data['crisis'] == true) {
        await showCrisisDialog(context);
      } else if (data is Map && data['reply'] is String) {
        setState(() => _aiText = data['reply'] as String);
      } else {
        _snack(context, 'Empty reply. Try again.');
      }
    } catch (_) {
      _snack(context, 'Could not reach the AI. Check your connection.');
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reflection'),
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Icon(_moodIcons[e.mood], color: scheme.primary),
                const SizedBox(width: 8),
                Text(_fmtDate(e.createdAt), style: textTheme.labelLarge),
              ],
            ),
            if (e.title != null && e.title!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(e.title!, style: textTheme.titleLarge),
            ],
            const SizedBox(height: 12),
            SelectableText(e.body, style: textTheme.bodyLarge),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _aiLoading ? null : _reflectWithAi,
              icon: _aiLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: const Text('Reflect with AI'),
            ),
            const SizedBox(height: 4),
            Text(
              'Optional. Sends only this entry to the AI.',
              style: textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (_aiText != null) ...[
              const SizedBox(height: 16),
              Card(
                color: scheme.secondaryContainer,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(_aiText!),
                      const SizedBox(height: 8),
                      Text(
                        'AI can be wrong. You know yourself best.',
                        style: textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
