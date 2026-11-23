import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'reflections.dart';

const kVercelApiUrl = 'https://lotusmind.vercel.app/api/chat';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lotusmind',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: const HomeShell(),
    );
  }
}

/// Bottom navigation: Study Assistant (chat) and Reflections (journal).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [ChatPage(), ReflectionsPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Study',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: 'Reflect',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------
class _Msg {
  _Msg(this.role, this.content, {this.isCrisis = false}) : model = null;
  final String role; // 'user' | 'assistant'
  String content;
  final bool isCrisis;
  String? model;
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _client = http.Client();
  final _input = TextEditingController();
  final _custom = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[];

  String _mode = 'normal'; // normal | simpler | deeper
  double _temperature = 0.4;
  bool _stream = true;
  bool _sending = false;

  @override
  void dispose() {
    _client.close();
    _input.dispose();
    _custom.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_Msg('user', text));
      _input.clear();
      _sending = true;
    });
    _scrollToEnd();

    final history = _messages
        .where((m) => !m.isCrisis && m.content.isNotEmpty)
        .toList();
    final recent = history.length > 10
        ? history.sublist(history.length - 10)
        : history;

    final body = jsonEncode({
      'messages': [
        for (final m in recent) {'role': m.role, 'content': m.content},
      ],
      'mode': _mode,
      'custom_instructions': _custom.text.trim(),
      'temperature': _temperature,
      'stream': _stream,
    });

    final reply = _Msg('assistant', '');
    try {
      final req = http.Request('POST', Uri.parse(kVercelApiUrl))
        ..headers.addAll({
          'Content-Type': 'application/json',
        })
        ..body = body;

      final res = await _client.send(req).timeout(const Duration(seconds: 45));

      if (res.statusCode != 200) {
        final err = await res.stream.bytesToString();
        throw Exception(_friendlyError(res.statusCode, err));
      }

      reply.model = res.headers['x-model'];
      final contentType = res.headers['content-type'] ?? '';

      if (contentType.contains('text/event-stream')) {
        setState(() => _messages.add(reply));
        await for (final line
            in res.stream
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim();
          if (data == '[DONE]') break;
          try {
            final delta = jsonDecode(data)['choices'][0]['delta']['content'];
            if (delta is String && delta.isNotEmpty) {
              setState(() => reply.content += delta);
              _scrollToEnd();
            }
          } catch (_) {
            // ignore
          }
        }
        if (reply.content.isEmpty) {
          setState(() => _messages.remove(reply));
          throw Exception('Empty reply. Try again.');
        }
      } else {
        final data = jsonDecode(await res.stream.bytesToString());
        if (data['crisis'] == true) {
          setState(
            () => _messages.add(
              _Msg('assistant', data['message'] as String, isCrisis: true),
            ),
          );
        } else {
          reply
            ..content = data['reply'] as String
            ..model = data['model'] as String?;
          setState(() => _messages.add(reply));
        }
      }
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  void _newChat() => setState(() {
    _messages.clear();
  });

  String _friendlyError(int status, String body) {
    if (status == 429) return 'Too many requests. Wait a moment and retry.';
    if (status == 502) return 'AI service temporarily unavailable. Try again.';
    return 'Something went wrong ($status). Try again.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Study Assistant'),
        actions: [
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _sending ? null : _newChat,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSettings(),
          const Divider(height: 1),
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('Ask a study question to begin.'))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _bubble(_messages[i], scheme),
                  ),
          ),
          if (_sending) const LinearProgressIndicator(minHeight: 2),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    return ExpansionTile(
      title: const Text('Customise'),
      leading: const Icon(Icons.tune),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'normal', label: Text('Normal')),
            ButtonSegment(value: 'simpler', label: Text('Simpler')),
            ButtonSegment(value: 'deeper', label: Text('Deeper')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _custom,
          maxLength: 600,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Your instructions (tone, format, length)',
            hintText: 'e.g. Use short bullet points and examples',
            border: OutlineInputBorder(),
          ),
        ),
        Row(
          children: [
            const Text('Creativity'),
            Expanded(
              child: Slider(
                value: _temperature,
                divisions: 10,
                label: _temperature.toStringAsFixed(1),
                onChanged: (v) => setState(() => _temperature = v),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Stream replies'),
          value: _stream,
          onChanged: (v) => setState(() => _stream = v),
        ),
      ],
    );
  }

  Widget _bubble(_Msg m, ColorScheme scheme) {
    final isUser = m.role == 'user';
    final color = m.isCrisis
        ? scheme.errorContainer
        : isUser
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(m.content),
            if (!isUser && !m.isCrisis && m.model != null) ...[
              const SizedBox(height: 6),
              Text(
                'nvidia · ${m.model}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Ask a question',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}
