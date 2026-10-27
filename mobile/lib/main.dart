import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'app_language.dart';
import 'api.dart';
import 'config.dart';
import 'storage_settings.dart';
import 'push_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSavedLocale();
  try {
    if (kIsWeb) {
      // Web Firebase config is injected at build time. Missing values should
      // not prevent the web bundle from compiling; show setup instructions instead.
      const apiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
      const appId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
      const messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
      const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
      const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
      if ([apiKey, appId, messagingSenderId, projectId, authDomain]
          .any((value) => value.isEmpty)) {
        runApp(const FirebaseSetupApp());
        return;
      }
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          authDomain: authDomain,
        ),
      );
    } else {
      // Explicit public client options avoid requiring generated
      // firebase_options.dart. If these are not supplied, use the standard
      // google-services.json setup when the Android project has that plugin.
      const apiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
      const appId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
      const messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
      const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
      if (apiKey.isNotEmpty && appId.isNotEmpty &&
          messagingSenderId.isNotEmpty && projectId.isNotEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: apiKey,
            appId: appId,
            messagingSenderId: messagingSenderId,
            projectId: projectId,
          ),
        );
      } else {
        await Firebase.initializeApp();
      }
    }
    runApp(const RelayApp());
  } catch (_) {
    runApp(const FirebaseSetupApp());
  }
}

class FirebaseSetupApp extends StatelessWidget {
  const FirebaseSetupApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: relayGreen)),
    home: Scaffold(body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(28), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(mainAxisSize: MainAxisSize.min, children: const [
      Icon(Icons.settings_suggest_rounded, size: 56, color: relayGreen),
      SizedBox(height: 18), Text('Finish Firebase setup', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      SizedBox(height: 10), Text('Configure Firebase for this target, enable Phone sign-in, and rebuild. Android needs google-services.json; Web needs Firebase web configuration supplied with --dart-define. See FIREBASE_SETUP.md in the project root.', textAlign: TextAlign.center),
    ])))))),
  );
}

const relayGreen = Color(0xFF176B55);
const relayMint = Color(0xFFE6F4ED);
const ink = Color(0xFF17231F);
const muted = Color(0xFF7B8983);
const canvas = Color(0xFFF6F8F6);

class RelayApp extends StatelessWidget {
  const RelayApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Locale?>(
        valueListenable: appLocale,
        builder: (context, locale, _) => MaterialApp(
        title: 'Veyra',
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('mr'), Locale('hi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        localeResolutionCallback: (deviceLocale, supportedLocales) {
          if (locale != null) return locale;
          if (deviceLocale != null) {
            for (final supported in supportedLocales) {
              if (supported.languageCode == deviceLocale.languageCode) return supported;
            }
          }
          return const Locale('en');
        },
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: canvas,
          colorScheme: ColorScheme.fromSeed(seedColor: relayGreen, primary: relayGreen, surface: Colors.white),
          fontFamily: 'Roboto',
          appBarTheme: const AppBarTheme(backgroundColor: canvas, foregroundColor: ink, elevation: 0, centerTitle: false),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.black.withValues(alpha: .045))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: relayGreen, width: 1.4)),
          ),
        ),
        home: const AuthGate(),
      ),
      );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override State<AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  bool? loggedIn;
  @override void initState() { super.initState(); _check(); }
  Future<void> _check() async {
    final token = await Api.token();
    if (mounted) setState(() => loggedIn = token != null);
  }
  @override Widget build(BuildContext context) {
    if (loggedIn == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: relayGreen)));
    return loggedIn! ? const HomeShell() : LoginScreen(onSuccess: () => setState(() => loggedIn = true));
  }
}

class LoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  const LoginScreen({super.key, required this.onSuccess});
  @override State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final phone = TextEditingController(), code = TextEditingController(), name = TextEditingController();
  String? verificationId, error;
  ConfirmationResult? webConfirmationResult;
  int? resendToken;
  bool codeRequested = false, busy = false;
  @override void dispose() { phone.dispose(); code.dispose(); name.dispose(); super.dispose(); }

  Future<void> requestCode() async {
    final number = phone.text.trim();
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Enter your name to set up your Veyra profile.');
      return;
    }
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(number)) {
      setState(() => error = 'Enter your number with country code, for example +919876543210.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      if (kIsWeb) {
        // FlutterFire Web uses signInWithPhoneNumber (reCAPTCHA), not the
        // native verifyPhoneNumber API.
        webConfirmationResult = await FirebaseAuth.instance.signInWithPhoneNumber(number);
        if (mounted) {
          setState(() {
            codeRequested = true;
            busy = false;
            error = null;
          });
        }
      } else {
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: number,
          timeout: const Duration(seconds: 60),
          forceResendingToken: resendToken,
          verificationCompleted: (credential) async {
            try { await _finishSignIn(credential); } catch (e) { if (mounted) setState(() { busy = false; error = _cleanError(e); }); }
          },
          verificationFailed: (e) { if (mounted) setState(() { busy = false; error = e.message ?? 'Could not send a verification code.'; }); },
          codeSent: (id, token) { if (mounted) setState(() { verificationId = id; resendToken = token; codeRequested = true; busy = false; }); },
          codeAutoRetrievalTimeout: (id) { verificationId = id; },
        );
      }
    } on FirebaseAuthException catch (e) { if (mounted) setState(() { busy = false; error = e.message ?? 'Phone verification failed.'; }); }
    catch (e) { if (mounted) setState(() { busy = false; error = _cleanError(e); }); }
  }

  Future<void> verifyCode() async {
    if ((kIsWeb && webConfirmationResult == null) || (!kIsWeb && verificationId == null)) {
      setState(() => error = 'Request a new verification code.');
      return;
    }
    if (code.text.trim().length != 6) { setState(() => error = 'Enter the 6-digit code.'); return; }
    setState(() { busy = true; error = null; });
    try {
      if (kIsWeb) {
        final result = await webConfirmationResult!.confirm(code.text.trim());
        await _finishFirebaseUser(result.user);
      } else {
        final credential = PhoneAuthProvider.credential(verificationId: verificationId!, smsCode: code.text.trim());
        await _finishSignIn(credential);
      }
    } on FirebaseAuthException catch (e) { if (mounted) setState(() => error = e.message ?? 'That code was not accepted.'); }
    catch (e) { if (mounted) setState(() => error = _cleanError(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _finishSignIn(PhoneAuthCredential credential) async {
    final result = await FirebaseAuth.instance.signInWithCredential(credential);
    await _finishFirebaseUser(result.user);
  }

  Future<void> _finishFirebaseUser(User? firebaseUser) async {
    if (firebaseUser == null) throw Exception('Firebase could not verify this account.');
    final idToken = await firebaseUser.getIdToken(true);
    if (idToken == null) throw Exception('Could not obtain a verified sign-in token.');
    await Api.exchangeFirebaseToken(idToken, displayName: name.text.trim());
    if (mounted) widget.onSuccess();
  }

  String _cleanError(Object e) => e.toString().replaceFirst('Exception: ', '');
  @override Widget build(BuildContext context) => Scaffold(
    body: Stack(children: [
      Positioned(top: -100, right: -80, child: Container(width: 270, height: 270, decoration: BoxDecoration(color: relayMint.withValues(alpha: .8), shape: BoxShape.circle))),
      SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 28, 24, 24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(width: 78, height: 78, alignment: Alignment.center, decoration: BoxDecoration(color: relayGreen, borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: relayGreen.withValues(alpha: .22), blurRadius: 25, offset: const Offset(0, 12))]), child: const Icon(Icons.forum_rounded, color: Colors.white, size: 38)),
        const SizedBox(height: 25),
        const Text('Good conversations\nstart here.', style: TextStyle(fontSize: 34, height: 1.12, fontWeight: FontWeight.w800, letterSpacing: -.8, color: ink)),
        const SizedBox(height: 12),
        const Text('A calmer space to stay close to the people who matter.', style: TextStyle(fontSize: 15, height: 1.5, color: muted)),
        const SizedBox(height: 30),
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .035), blurRadius: 25, offset: const Offset(0, 8))]), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(codeRequested ? 'Verify your number' : 'Get started', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ink)),
          const SizedBox(height: 6),
          Text(codeRequested ? 'Enter the code Firebase sent to your phone.' : 'Sign in securely with your phone number.', style: const TextStyle(fontSize: 13, color: muted, height: 1.4)),
          const SizedBox(height: 20),
          TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded), labelText: 'Your name', hintText: 'Shown to your contacts')),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, enabled: !codeRequested, decoration: const InputDecoration(prefixIcon: Icon(Icons.phone_iphone_rounded), labelText: 'Phone number', hintText: '+919876543210')),
          if (codeRequested) ...[
            const SizedBox(height: 12),
            TextField(controller: code, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(prefixIcon: Icon(Icons.verified_user_outlined), labelText: 'Verification code', hintText: '6 digits')),
          ],
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Color(0xFFB42318), fontSize: 13))),
          const SizedBox(height: 18),
          SizedBox(height: 54, child: FilledButton(onPressed: busy ? null : codeRequested ? verifyCode : requestCode, style: FilledButton.styleFrom(backgroundColor: relayGreen, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(codeRequested ? 'Verify and continue' : 'Send verification code', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(width: 8), const Icon(Icons.arrow_forward_rounded, size: 18)]))),
          if (codeRequested) Center(child: TextButton(onPressed: busy ? null : () => setState(() { codeRequested = false; verificationId = null; webConfirmationResult = null; code.clear(); error = null; }), child: const Text('Change phone number'))),
        ])),
        const SizedBox(height: 18),
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.lock_outline_rounded, size: 15, color: muted), SizedBox(width: 6), Flexible(child: Text('Phone verification is provided by Firebase. End-to-end encryption is a separate release requirement.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: muted)))]),
      ]))))),
    ]),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override State<HomeShell> createState() => _HomeShellState();
}
class _HomeShellState extends State<HomeShell> {
  int selectedTab = 0;
  @override void initState() {
    super.initState();
    // Push registration is optional and isolated from the core sign-in path.
    PushNotifications.initialize();
  }
  Future<void> logout() async {
    await PushNotifications.unregister();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    try { await FirebaseAuth.instance.signOut(); } catch (_) {}
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthGate()), (_) => false);
  }
  @override Widget build(BuildContext context) {
    final pages = [const ChatsScreen(), const UpdatesScreen(), const CallsScreen(), SettingsScreen(onLogout: logout)];
    return Scaffold(
      body: IndexedStack(index: selectedTab, children: pages),
      bottomNavigationBar: Container(decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 18, offset: const Offset(0, -4))]), child: NavigationBar(
        height: 72, selectedIndex: selectedTab, backgroundColor: Colors.white, indicatorColor: relayMint,
        onDestinationSelected: (index) => setState(() => selectedTab = index),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline_rounded), selectedIcon: const Icon(Icons.chat_bubble_rounded), label: tr(context, 'chats')),
          NavigationDestination(icon: const Icon(Icons.auto_awesome_outlined), selectedIcon: const Icon(Icons.auto_awesome_rounded), label: tr(context, 'updates')),
          NavigationDestination(icon: const Icon(Icons.call_outlined), selectedIcon: const Icon(Icons.call_rounded), label: tr(context, 'calls')),
          NavigationDestination(icon: const Icon(Icons.tune_rounded), selectedIcon: const Icon(Icons.tune_rounded), label: tr(context, 'settings')),
        ],
      )),
    );
  }
}

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override State<ChatsScreen> createState() => _ChatsScreenState();
}
class _ChatsScreenState extends State<ChatsScreen> {
  List<dynamic> chats = [];
  bool loading = true;
  String? error;
  final search = TextEditingController();
  WebSocketChannel? _socket;
  Timer? _inboxTimer;
  @override void initState() {
    super.initState();
    load();
    syncInboxQuietly();
    connectSocket();
    // Periodic cursor sync is the recovery path for missed Redis Pub/Sub events and
    // transient WebSocket disconnects. It is intentionally low-frequency.
    _inboxTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      syncInboxQuietly();
      if (_socket == null) connectSocket();
    });
  }
  @override void dispose() { _inboxTimer?.cancel(); search.dispose(); _socket?.sink.close(); super.dispose(); }
  Future<void> syncInboxQuietly() async {
    try {
      await Api.syncInbox();
      if (mounted) await load();
    } catch (_) {
      // Offline mode is expected; the next timer tick or WebSocket event retries.
    }
  }
  Future<void> load() async {
    // Paint the last known conversation list immediately so an offline launch does not
    // leave the user behind a network spinner while the API request times out.
    final cachedFirst = await Api.cachedConversations();
    if (cachedFirst.isNotEmpty && mounted) {
      setState(() { chats = cachedFirst; loading = false; });
    }
    try {
      await Api.prepareInboxAccount();
      chats = await Api.getList('/conversations');
      await Api.cacheConversations(chats);
      error = null;
    } catch (e) {
      chats = await Api.cachedConversations();
      error = chats.isNotEmpty ? null : e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => loading = false);
  }
  Future<void> connectSocket() async {
    final token = await Api.token(); if (token == null) return;
    try {
      final uri = Uri.parse('${AppConfig.wsBaseUrl}/ws').replace(queryParameters: {'token': token});
      final channel = WebSocketChannel.connect(uri);
      _socket = channel;
      channel.stream.listen((event) async {
        try { await Api.syncInbox(); } catch (_) {}
        if (mounted) await load();
      }, onError: (_) {
        if (identical(_socket, channel)) _socket = null;
      }, onDone: () {
        if (identical(_socket, channel)) _socket = null;
      });
    } catch (_) { _socket = null; }
  }
  Future<void> createChat() async {
    final idController = TextEditingController();
    final id = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Start a conversation'),
      content: TextField(controller: idController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Contact user ID', hintText: 'Ask your contact for their ID')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, idController.text), child: const Text('Create chat'))],
    ));
    if (id == null || int.tryParse(id) == null) return;
    try { await Api.request('/conversations', method: 'POST', body: {'member_ids': [int.parse(id)]}); await load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    finally { idController.dispose(); }
  }
  @override Widget build(BuildContext context) {
    final filtered = chats.where((raw) {
      final c = raw as Map<String, dynamic>;
      return ((c['title'] as String?) ?? 'Conversation ${c['id']}').toLowerCase().contains(search.text.toLowerCase());
    }).toList();
    return SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(22, 18, 22, 12), child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: relayGreen, borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.forum_rounded, color: Colors.white, size: 24)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Veyra', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -.8, color: ink)), Text(tr(context, 'chat_subtitle'), style: const TextStyle(fontSize: 12, color: muted))])),
        IconButton(onPressed: createChat, style: IconButton.styleFrom(backgroundColor: Colors.white), icon: const Icon(Icons.edit_square, color: relayGreen)),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF145C49), Color(0xFF278267)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(23)), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr(context, 'banner_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19, height: 1.2)), const SizedBox(height: 8), Text(tr(context, 'banner_subtitle'), style: const TextStyle(color: Color(0xFFD8EEE5), fontSize: 12))])),
        Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .13), shape: BoxShape.circle), child: const Icon(Icons.forum_outlined, color: Colors.white, size: 32)),
      ]))),
      Padding(padding: const EdgeInsets.fromLTRB(22, 18, 22, 10), child: TextField(controller: search, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: tr(context, 'search_chats'), prefixIcon: const Icon(Icons.search_rounded), suffixIcon: const Icon(Icons.tune_rounded)))),
      Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 10), child: Row(children: [Text(tr(context, 'messages'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink)), const Spacer(), Text('${filtered.length} chats', style: const TextStyle(fontSize: 12, color: muted))])),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator(color: relayGreen)) : error != null ? _StatePanel(icon: Icons.cloud_off_outlined, title: 'Could not load chats', subtitle: error!, action: 'Try again', onAction: load) : filtered.isEmpty ? _StatePanel(icon: Icons.chat_bubble_outline_rounded, title: search.text.isEmpty ? 'Your conversations start here' : 'No matches found', subtitle: search.text.isEmpty ? 'Start a chat with someone and keep the conversation going.' : 'Try another name or start a new conversation.', action: search.text.isEmpty ? 'New conversation' : 'Clear search', onAction: search.text.isEmpty ? createChat : () { search.clear(); setState(() {}); }) : RefreshIndicator(color: relayGreen, onRefresh: load, child: ListView.separated(padding: const EdgeInsets.fromLTRB(14, 2, 14, 16), itemCount: filtered.length, separatorBuilder: (_, __) => const SizedBox(height: 4), itemBuilder: (ctx, i) {
        final c = filtered[i] as Map<String, dynamic>;
        final title = (c['title'] as String?) ?? 'Conversation ${c['id']}';
        return Material(color: Colors.white, borderRadius: BorderRadius.circular(18), child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          leading: CircleAvatar(radius: 25, backgroundColor: _avatarColor(i), child: Text(_initials(title), style: const TextStyle(color: relayGreen, fontWeight: FontWeight.w800))),
          title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
          subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text('${(c['member_ids'] as List).length} members · Conversation ready', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: muted))),
          trailing: const Icon(Icons.chevron_right_rounded, color: muted),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: c['id'] as int, title: title))),
        ));
      }))),
    ]));
  }
}

class ChatScreen extends StatefulWidget {
  final int conversationId;
  final String title;
  const ChatScreen({super.key, required this.conversationId, required this.title});
  @override State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController();
  List<dynamic> messages = [];
  bool loading = true, sending = false;
  int? myUserId;
  @override void initState() { super.initState(); load(); loadCurrentUser(); }
  @override void dispose() { input.dispose(); super.dispose(); }
  Future<void> loadCurrentUser() async {
    try { final me = await Api.request('/users/me/phone'); if (mounted) setState(() => myUserId = me['id'] as int?); } catch (_) {}
  }
  Future<void> load() async {
    List<dynamic> remote = <dynamic>[];
    Object? loadError;
    try {
      remote = await Api.getList('/conversations/${widget.conversationId}/messages');
    } catch (e) {
      loadError = e;
    }
    final cached = await Api.cachedInbox(widget.conversationId);
    final merged = <int, Map<String, dynamic>>{};
    for (final raw in remote) {
      if (raw is Map) {
        final item = Map<String, dynamic>.from(raw);
        if (item['id'] is int) merged[item['id'] as int] = item;
      }
    }
    for (final item in cached) {
      final id = item['id'];
      if (id is! int) continue;
      final current = merged[id];
      // Preserve the locally cached encrypted marker/metadata while the legacy history
      // endpoint returns only its placeholder body and omits ciphertext fields.
      if (current == null || current['body'] == '[encrypted]' || current['body'] == '[Encrypted message]') {
        merged[id] = <String, dynamic>{...?current, ...item};
      }
    }
    messages = merged.values.toList()
      ..sort((a, b) => ((a['id'] as int?) ?? 0).compareTo((b['id'] as int?) ?? 0));
    if (loadError != null && messages.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loadError.toString())));
    }
    if (mounted) setState(() => loading = false);
  }
  Future<void> send() async {
    final body = input.text.trim(); if (body.isEmpty || sending) return;
    setState(() => sending = true);
    try { await Api.request('/conversations/${widget.conversationId}/messages', method: 'POST', body: {'body': body}); input.clear(); await load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    finally { if (mounted) setState(() => sending = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leadingWidth: 42, titleSpacing: 4, title: Row(children: [CircleAvatar(backgroundColor: relayMint, child: Text(_initials(widget.title), style: const TextStyle(color: relayGreen, fontWeight: FontWeight.w800))), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)), const Text('Conversation', style: TextStyle(fontSize: 11, color: muted))]))]), actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.call_outlined)), IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert_rounded))]),
    body: Column(children: [
      Container(margin: const EdgeInsets.fromLTRB(14, 0, 14, 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), decoration: BoxDecoration(color: const Color(0xFFFFF4D8), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.info_outline_rounded, size: 17, color: Color(0xFF946200)), const SizedBox(width: 8), Expanded(child: Text(AppConfig.allowPlaintextMessages ? 'Development demo: messages are not end-to-end encrypted. Never share sensitive information.' : 'Sending is disabled until end-to-end encryption is implemented and reviewed.', style: const TextStyle(fontSize: 11, color: Color(0xFF795700))))])),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator(color: relayGreen)) : messages.isEmpty ? const _StatePanel(icon: Icons.waving_hand_outlined, title: 'Say hello', subtitle: 'A good conversation can start with one simple message.') : ListView.builder(reverse: true, padding: const EdgeInsets.fromLTRB(14, 12, 14, 18), itemCount: messages.length, itemBuilder: (ctx, i) {
        final m = messages[messages.length - 1 - i] as Map<String, dynamic>;
        final mine = myUserId != null && m['sender_id'] == myUserId;
        return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.fromLTRB(14, 10, 14, 8), constraints: const BoxConstraints(maxWidth: 300), decoration: BoxDecoration(color: mine ? relayMint : Colors.white, borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(mine ? 18 : 5), bottomRight: Radius.circular(mine ? 5 : 18))), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Align(alignment: Alignment.centerLeft, child: Text(m['body'] as String? ?? '[Encrypted message]', style: const TextStyle(fontSize: 14, height: 1.35, color: ink))), const SizedBox(height: 4), Text('Message #${m['id']}', style: const TextStyle(fontSize: 9, color: muted))])));
      })),
      SafeArea(child: Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(10, 10, 10, 8), child: Row(children: [
        IconButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Media sharing is planned for a later phase.'))), icon: const Icon(Icons.add_circle_outline_rounded, color: relayGreen)),
        Expanded(child: TextField(controller: input, readOnly: !AppConfig.allowPlaintextMessages, minLines: 1, maxLines: 5, onSubmitted: (_) { if (AppConfig.allowPlaintextMessages) send(); }, decoration: InputDecoration(hintText: AppConfig.allowPlaintextMessages ? 'Write a message…' : 'Messaging is disabled until E2EE is ready', fillColor: canvas, border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11)))),
        const SizedBox(width: 8), Container(width: 46, height: 46, decoration: BoxDecoration(color: relayGreen, borderRadius: BorderRadius.circular(16)), child: IconButton(onPressed: (!AppConfig.allowPlaintextMessages || sending) ? null : send, icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_upward_rounded, color: Colors.white))),
      ]))),
    ]),
  );
}

class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});
  @override Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.all(22), children: [
    Text(tr(context, 'updates'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: ink)),
    const SizedBox(height: 6), Text(tr(context, 'updates_subtitle'), style: const TextStyle(color: muted)),
    const SizedBox(height: 24),
    Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)), child: Column(children: [const Icon(Icons.auto_awesome_outlined, size: 44, color: relayGreen), const SizedBox(height: 12), Text(tr(context, 'updates_empty_title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink)), const SizedBox(height: 7), Text(tr(context, 'updates_empty_body'), textAlign: TextAlign.center, style: const TextStyle(color: muted, height: 1.45))])),
  ]));
}
class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});
  @override Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.all(22), children: [
    Text(tr(context, 'calls'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: ink)),
    const SizedBox(height: 6), Text(tr(context, 'calls_subtitle'), style: const TextStyle(color: muted)),
    const SizedBox(height: 24),
    Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)), child: Column(children: [const Icon(Icons.video_call_outlined, size: 46, color: relayGreen), const SizedBox(height: 12), Text(tr(context, 'calls_title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink)), const SizedBox(height: 7), Text(tr(context, 'calls_body'), textAlign: TextAlign.center, style: const TextStyle(color: muted, height: 1.45))])),
  ]));
}
class SettingsScreen extends StatelessWidget {
  final Future<void> Function() onLogout;
  const SettingsScreen({super.key, required this.onLogout});

  @override
  Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.all(22), children: [
    Text(tr(context, 'settings'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: ink)),
    const SizedBox(height: 6), Text(tr(context, 'settings_subtitle'), style: const TextStyle(color: muted)),
    const SizedBox(height: 24),
    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), child: Row(children: [
      const CircleAvatar(radius: 26, backgroundColor: relayMint, child: Icon(Icons.person_outline_rounded, color: relayGreen, size: 28)),
      const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, 'account'), style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 4), Text(tr(context, 'account_subtitle'), style: const TextStyle(fontSize: 12, color: muted)),
      ])),
    ])),
    const SizedBox(height: 12),
    _SettingsTile(icon: Icons.lock_outline_rounded, title: tr(context, 'privacy'), subtitle: tr(context, 'privacy_subtitle'), onTap: () => showDialog(context: context, builder: (_) => const AlertDialog(title: Text('Privacy and security'), content: Text('End-to-end encryption is not yet implemented or audited. This development build should not be used for sensitive conversations.')))),
    _SettingsTile(icon: Icons.notifications_none_rounded, title: tr(context, 'notifications'), subtitle: tr(context, 'notifications_subtitle'), onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'notifications_subtitle'))))),
    _SettingsTile(icon: Icons.storage_rounded, title: tr(context, 'storage'), subtitle: tr(context, 'storage_subtitle'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StorageDataScreen()))),
    _SettingsTile(icon: Icons.language_rounded, title: tr(context, 'language'), subtitle: tr(context, 'language_subtitle'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LanguageSettingsScreen()))),
    _SettingsTile(icon: Icons.help_outline_rounded, title: tr(context, 'help'), subtitle: tr(context, 'help_subtitle'), onTap: () => showAboutDialog(context: context, applicationName: 'Veyra', applicationVersion: '0.1.0', children: const [Text('Veyra is an early development build. Some features are not yet available.')])),
    const SizedBox(height: 10),
    OutlinedButton.icon(onPressed: onLogout, icon: const Icon(Icons.logout_rounded), label: Text(tr(context, 'sign_out')), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB42318), padding: const EdgeInsets.symmetric(vertical: 15), side: BorderSide(color: const Color(0xFFB42318).withValues(alpha: .25)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)))),
    const SizedBox(height: 22), const Center(child: Text('VEYRA · CLOSER, WHEREVER LIFE TAKES YOU', style: TextStyle(fontSize: 9, letterSpacing: 1.1, color: muted, fontWeight: FontWeight.w700))),
  ]));
}

class _SettingsTile extends StatelessWidget {
  final IconData icon; final String title; final String subtitle; final VoidCallback onTap;
  const _SettingsTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17)), child: ListTile(leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: relayMint, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: relayGreen)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: ink, fontSize: 14)), subtitle: Text(subtitle, style: const TextStyle(color: muted, fontSize: 11)), trailing: const Icon(Icons.chevron_right_rounded, color: muted), onTap: onTap));
}

class _StatePanel extends StatelessWidget {
  final IconData icon; final String title; final String subtitle; final String? action; final VoidCallback? onAction;
  const _StatePanel({required this.icon, required this.title, required this.subtitle, this.action, this.onAction});
  @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 76, height: 76, decoration: const BoxDecoration(color: relayMint, shape: BoxShape.circle), child: Icon(icon, color: relayGreen, size: 34)), const SizedBox(height: 18), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink)), const SizedBox(height: 8), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: muted, height: 1.45)), if (action != null && onAction != null) ...[const SizedBox(height: 18), FilledButton.tonal(onPressed: onAction, child: Text(action!))]])));
}

String _initials(String value) {
  final words = value.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (words.isEmpty) return 'R';
  return words.take(2).map((w) => w[0].toUpperCase()).join();
}
Color _avatarColor(int index) {
  const colors = [Color(0xFFE4F2EA), Color(0xFFE9E8FA), Color(0xFFFFEEDB), Color(0xFFDFF0F4), Color(0xFFF7E4EC)];
  return colors[index % colors.length];
}
