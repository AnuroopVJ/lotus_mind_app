// lib/main.dart
// pubspec.yaml: add
//   http: ^1.2.0
//   supabase_flutter: ^2.8.0
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'reflections.dart';


// The publishable key is safe to ship in the app. Never put a secret key (sb_secret_...) here.
const kSupabaseUrl = 'https://nbjtrbzrdkrkloiocapo.supabase.co';
const kSupabasePublishableKey = 'sb_publishable_Z-IJKTFj_X8_R4U17lLeDQ_tAV2FIMr';
const kFunctionUrl = '$kSupabaseUrl/functions/v1/invidia-chat';

SupabaseClient get supabase => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: kSupabaseUrl,
    publishableKey: kSupabasePublishableKey,
  );
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
      home: const AuthGate(),
    );
  }
}

/// Shows the login page when signed out, the chat when signed in.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? supabase.auth.currentSession;
        return session == null ? const LoginPage() : const HomeShell();
      },
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
// Login / sign-up
// ---------------------------------------------------------------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _isSignUp = false;
  bool _loading = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_isSignUp) {
        final res = await supabase.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'display_name': _name.text.trim()},
        );
        // With email confirmation on (the default) there is no session yet.
        if (res.session == null) {
          _snack('Check your email to confirm your account, then sign in.');
          if (mounted) setState(() => _isSignUp = false);
        }
      } else {
        await supabase.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        // AuthGate swaps to ChatPage automatically.
      }
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Something went wrong. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      _snack('Enter your email above first.');
      return;
    }
    try {
      await supabase.auth.resetPasswordForEmail(email);
      _snack('If that email has an account, a reset link is on its way.');
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not send the reset email. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.spa_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Lotusmind',
                      textAlign: TextAlign.center,
                      style: textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isSignUp ? 'Create your account' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    if (_isSignUp) ...[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final s = v?.trim() ?? '';
                        return (s.contains('@') && s.contains('.'))
                            ? null
                            : 'Enter a valid email';
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      autofillHints: [
                        _isSignUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _loading ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _hidePassword ? 'Show' : 'Hide',
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 8)
                          ? 'Use at least 8 characters'
                          : null,
                    ),
                    if (!_isSignUp)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _loading ? null : _forgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isSignUp ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() => _isSignUp = !_isSignUp),
                      child: Text(
                        _isSignUp
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
  String? _displayName;
  String? _sessionId; // null until the first message of a chat is saved

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _client.close();
    _input.dispose();
    _custom.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Reads this user's row from the `profiles` table (RLS: own row only).
  Future<void> _loadProfile() async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      final row = await supabase
          .from('profiles')
          .select('display_name, custom_instructions, default_mode')
          .eq('id', uid)
          .maybeSingle();
      if (mounted && row != null) {
        setState(() {
          _displayName = row['display_name'] as String?;
          _custom.text = (row['custom_instructions'] as String?) ?? '';
          final m = row['default_mode'] as String?;
          if (m == 'normal' || m == 'simpler' || m == 'deeper') _mode = m!;
        });
      }
    } catch (_) {
      // Greeting is optional; ignore failures.
    }
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

    // Last 10 turns, skipping crisis replies so they are not fed back to the model.
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
      // The signed-in user's JWT; the function rejects anything else.
      final token = supabase.auth.currentSession?.accessToken;
      if (token == null) throw Exception('Please sign in again.');

      final req = http.Request('POST', Uri.parse(kFunctionUrl))
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'apikey': kSupabasePublishableKey,
        })
        ..body = body;

      final res = await _client.send(req).timeout(const Duration(seconds: 30));

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
            // ignore keep-alive or partial lines
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
      // Save the turn (user message + reply) without blocking the UI.
      _persist(text, _messages.last);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  /// Saves one finished turn. Failures are ignored so chat never breaks.
  Future<void> _persist(String userText, _Msg last) async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      if (_sessionId == null) {
        final row = await supabase
            .from('chat_sessions')
            .insert({
              'user_id': uid,
              'title': userText.length > 60
                  ? userText.substring(0, 60)
                  : userText,
            })
            .select('id')
            .single();
        _sessionId = row['id'] as String;
      }
      await supabase.from('chat_messages').insert([
        {
          'session_id': _sessionId,
          'user_id': uid,
          'role': 'user',
          'content': userText,
        },
        {
          'session_id': _sessionId,
          'user_id': uid,
          'role': 'assistant',
          'content': last.content,
          'model': last.model,
          'is_crisis': last.isCrisis,
        },
      ]);
    } catch (_) {
      // History is a convenience; ignore save failures.
    }
  }

  void _newChat() => setState(() {
    _messages.clear();
    _sessionId = null;
  });

  Future<void> _openHistory() async {
    try {
      final rows = await supabase
          .from('chat_sessions')
          .select('id, title, created_at')
          .order('created_at', ascending: false)
          .limit(30);
      if (!mounted) return;
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => rows.isEmpty
            ? const SizedBox(
                height: 160,
                child: Center(child: Text('No saved chats yet.')),
              )
            : ListView(
                children: [
                  for (final r in rows)
                    ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(
                        (r['title'] as String?) ?? 'Chat',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        DateTime.parse(r['created_at'] as String)
                            .toLocal()
                            .toString()
                            .substring(0, 16),
                      ),
                      onTap: () => Navigator.pop(ctx, r['id'] as String),
                    ),
                ],
              ),
      );
      if (picked != null) await _loadSession(picked);
    } catch (_) {
      _snack('Could not load your chats.');
    }
  }

  Future<void> _loadSession(String id) async {
    try {
      final rows = await supabase
          .from('chat_messages')
          .select('role, content, model, is_crisis')
          .eq('session_id', id)
          .order('id');
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll([
            for (final r in rows)
              _Msg(
                r['role'] as String,
                r['content'] as String,
                isCrisis: r['is_crisis'] == true,
              )..model = r['model'] as String?,
          ]);
        _sessionId = id;
      });
      _scrollToEnd();
    } catch (_) {
      _snack('Could not open that chat.');
    }
  }

  /// Stores the custom prompt + mode on the user's profile row.
  Future<void> _saveDefaults() async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      await supabase
          .from('profiles')
          .update({
            'custom_instructions': _custom.text.trim(),
            'default_mode': _mode,
          })
          .eq('id', uid);
      _snack('Saved as your default.');
    } catch (_) {
      _snack('Could not save. Try again.');
    }
  }

  String _friendlyError(int status, String body) {
    if (status == 429) return 'Too many requests. Wait a moment and retry.';
    if (status == 401 || status == 403) {
      return 'Session expired. Please sign out and sign in again.';
    }
    return 'Something went wrong ($status). Try again.';
  }

  Future<void> _signOut() async {
    try {
      await supabase.auth.signOut();
      // AuthGate returns to LoginPage; this page (and the chat) is disposed.
    } catch (_) {
      _snack('Could not sign out. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasName = _displayName != null && _displayName!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(hasName ? 'Hi, $_displayName' : 'Study Assistant'),
        actions: [
          IconButton(
            tooltip: 'Chat history',
            icon: const Icon(Icons.history),
            onPressed: _sending ? null : _openHistory,
          ),
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _sending ? null : _newChat,
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _sending ? null : _signOut,
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
            hintText: 'e.g. Use short bullet points and Hinglish examples',
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _saveDefaults,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save as my default'),
          ),
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
