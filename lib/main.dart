import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
// permission_handler not required for nutrition; we rely on health plugin's auth flow

// Simple app settings with locale persistence
class AppSettings extends ChangeNotifier {
  Locale? _locale;
  Locale? get locale => _locale;
  bool _daltonian = false;
  bool get daltonian => _daltonian;

  static const _prefsKey = 'app_locale'; // values: 'system', 'en', 'fr'
  static const _prefsDaltonian = 'daltonian_mode';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    if (code == null || code == 'system') {
      _locale = null; // follow system
    } else {
      _locale = Locale(code);
      Intl.defaultLocale = code;
    }
  _daltonian = prefs.getBool(_prefsDaltonian) ?? false;
  }

  Future<void> setLocale(Locale? value) async {
    _locale = value;
    Intl.defaultLocale = value?.languageCode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.setString(_prefsKey, 'system');
    } else {
      await prefs.setString(_prefsKey, value.languageCode);
    }
  }

  Future<void> setDaltonian(bool value) async {
    _daltonian = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsDaltonian, value);
  }
}

final appSettings = AppSettings();
String get kDefaultBaseUrl => dotenv.maybeGet('APP_BASE_URL') ?? 'http://141.145.210.115:3007';
class AuthState extends ChangeNotifier {
  String? _token;
  String? get token => _token;

  static const _tokenKey = 'jwt_token';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    notifyListeners();
  }

  Future<void> setToken(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    _token = value;
    if (value == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, value);
    }
    notifyListeners();
  }
}

final authState = AuthState();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env.client');
  } catch (_) {}
  await appSettings.load();
  await authState.load();
  runApp(const RootApp());
}

class RootApp extends StatelessWidget {
  const RootApp({super.key});

  @override
  Widget build(BuildContext context) {
    const fallbackSeed = Color(0xFF6750A4);
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final ColorScheme lightScheme = lightDynamic ?? ColorScheme.fromSeed(seedColor: fallbackSeed, brightness: Brightness.light);
        final ColorScheme darkScheme = darkDynamic ?? ColorScheme.fromSeed(seedColor: fallbackSeed, brightness: Brightness.dark);

        final ThemeData lightTheme = ThemeData(
          colorScheme: lightScheme,
          useMaterial3: true,
          appBarTheme: AppBarTheme(
            backgroundColor: lightScheme.surface,
            foregroundColor: lightScheme.onSurface,
            elevation: 0,
            centerTitle: true,
          ),
          cardTheme: const CardThemeData(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          ),
        );

        final ThemeData darkTheme = ThemeData(
          colorScheme: darkScheme,
          useMaterial3: true,
          appBarTheme: AppBarTheme(
            backgroundColor: darkScheme.surface,
            foregroundColor: darkScheme.onSurface,
            elevation: 0,
            centerTitle: true,
          ),
          cardTheme: const CardThemeData(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          ),
        );

        return AnimatedBuilder(
          animation: appSettings,
          builder: (context, _) => MaterialApp(
            onGenerateTitle: (ctx) => S.of(ctx).appTitle,
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.system,
            locale: appSettings.locale,
            supportedLocales: const [Locale('en'), Locale('fr')],
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const AuthGate(),
          ),
        );
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    authState.addListener(_onAuth);
  }

  @override
  void dispose() {
    authState.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (authState.token == null) return const LoginScreen();
    return const MainScreen();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _u = TextEditingController();
  final _p = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
  final uri = Uri.parse('$kDefaultBaseUrl/auth/login');
      final resp = await http.post(uri, headers: {
        'Content-Type': 'application/json',
      }, body: jsonEncode({ 'username': _u.text.trim(), 'password': _p.text }));
      if (resp.statusCode != 200) {
        setState(() { _error = S.of(context).loginFailedCode(resp.statusCode); });
        return;
      }
      final jsonBody = json.decode(resp.body) as Map;
      if (jsonBody['ok'] != true) {
  setState(() { _error = (jsonBody['error']?.toString() ?? S.of(context).loginError); });
        return;
      }
      final token = jsonBody['token']?.toString();
      final force = jsonBody['forcePasswordReset'] == true;
      if (token == null || token.isEmpty) {
  setState(() { _error = S.of(context).noTokenReceived; });
        return;
      }
      await authState.setToken(token);
      if (!mounted) return;
      if (force) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const SetPasswordScreen()));
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
      }
    } catch (e) {
      setState(() { _error = S.of(context).networkError; });
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
  appBar: AppBar(title: Text('${s.appTitle} • ${s.login}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _u,
                    decoration: InputDecoration(labelText: s.username),
                    validator: (v) => (v==null||v.trim().isEmpty) ? s.required : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _p,
                    obscureText: true,
                    decoration: InputDecoration(labelText: s.password),
                    validator: (v) => (v==null||v.isEmpty) ? s.required : null,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : _login,
                    child: _busy ? const SizedBox(width: 18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : Text(s.login),
                  ),
                  const SizedBox(height: 24),
                  Text(s.betaSignup, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  IconButton(
                    tooltip: s.joinDiscordAction,
                    iconSize: 28,
                    onPressed: () async {
                      final uri = Uri.parse('https://discord.gg/8bDDqbvr8K');
                      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.openDiscordFailed)),
                          );
                        }
                      }
                    },
                    icon: const FaIcon(FontAwesomeIcons.discord),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});
  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
  if (!_formKey.currentState!.validate()) return;
  if (_p1.text != _p2.text) { setState((){_error=S.of(context).passwordsDoNotMatch;}); return; }
    setState(() { _busy = true; _error = null; });
    try {
  final uri = Uri.parse('$kDefaultBaseUrl/auth/set-password');
      final resp = await http.post(uri, headers: {
        'Content-Type': 'application/json',
        if (authState.token != null) 'Authorization': 'Bearer ${authState.token}',
      }, body: jsonEncode({ 'newPassword': _p1.text }));
      if (resp.statusCode != 200) {
        setState(() { _error = S.of(context).failedWithCode(resp.statusCode); });
        return;
      }
      final body = json.decode(resp.body) as Map;
      if (body['ok'] != true) {
        setState(() { _error = (body['error']?.toString() ?? S.of(context).error); });
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
    } catch (e) {
      setState(() { _error = S.of(context).networkError; });
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
  appBar: AppBar(title: Text('${s.appTitle} • ${s.setPasswordTitle}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _p1,
                    obscureText: true,
                    decoration: InputDecoration(labelText: s.newPassword),
                    validator: (v) => (v==null||v.length<6) ? s.min6 : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _p2,
                    obscureText: true,
                    decoration: InputDecoration(labelText: s.confirmPassword),
                    validator: (v) => (v==null||v.length<6) ? s.min6 : null,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy ? const SizedBox(width: 18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

// Moved _image and _controller to the class level to ensure state persistence
class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<Map<String, dynamic>> _history = [];
  final TextEditingController _controller = TextEditingController();
  XFile? _image;
  String _resultText = '';
  bool _loading = false;
  int _dailyLimit = 2000;
  String? _serverHostOverride; // legacy host-only override
  final Health _health = Health();
  bool _healthConfigured = false;
  bool? _healthAuthorized; // null = unknown
  String? _healthLastError;
  HealthConnectSdkStatus? _hcSdkStatus;
  // Health: energy burned cache for today
  double? _todayTotalBurnedKcal;
  double? _todayActiveBurnedKcal;
  bool _loadingBurned = false;
  // When set, newly added foods can be appended to this grouped meal until finished
  Map<String, dynamic>? _pendingMealGroup;
  // Announcement
  bool _announcementChecked = false;
  bool _announcementsDisabled = false;
  // Queue & notifications
  final List<Map<String, dynamic>> _queue = [];
  final List<Map<String, dynamic>> _notifications = [];
  bool _queueMode = false;

  @override
  void initState() {
    super.initState();
  _tabController = TabController(length: 3, vsync: this);
  _loadPrefs();
  _loadHistory();
  _pruneHistory();
  // Proactively check Health Connect status on supported platforms
  if (!kIsWeb && Platform.isAndroid) {
    // fire and forget; UI will update when done
    // ignore: discarded_futures
    _checkHealthStatus();
  }
  // Try to prefetch burned energy for today (no-op on unsupported platforms)
  // ignore: discarded_futures
  _loadTodayBurned();
  // Fetch announcement after first frame so context is ready
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // ignore: discarded_futures
    _checkAnnouncement();
  });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkAnnouncement() async {
    if (_announcementChecked) return;
    _announcementChecked = true;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('disable_announcements_globally') == true) return;
    try {
      final localeCode = (S.of(context).locale.languageCode == 'fr') ? 'fr' : 'en';
    final uri = Uri.parse('${kDefaultBaseUrl}/announcement?lang=$localeCode');
      final res = await http.get(uri, headers: {
        'Accept-Language': localeCode,
      });
      if (res.statusCode == 200) {
        final map = json.decode(res.body);
        if (map is Map && map['ok'] == true) {
          final md = (map['markdown']?.toString() ?? '').trim();
          final id = map['id']?.toString();
          final hiddenId = prefs.getString('hidden_announcement_id_$localeCode')
              ?? prefs.getString('hidden_announcement_id'); // legacy fallback
          if (md.isNotEmpty && (id == null || id != hiddenId) && mounted) {
            await _showAnnouncementDialog(md, id: id, localeCode: localeCode);
          }
        }
      }
    } catch (_) {
      // ignore network errors
    }
  }

  Future<void> _showAnnouncementDialog(String md, {String? id, String? localeCode}) async {
    final s = S.of(context);
    bool hideForever = false;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final scrollCtrl = ScrollController();
        final maxHeight = MediaQuery.of(ctx).size.height * 0.6; // responsive height for high-DPI
        final dialogWidth = MediaQuery.of(ctx).size.width.clamp(320.0, 520.0);
        return AlertDialog(
          title: Text(s.info),
          content: SizedBox(
            width: dialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: Scrollbar(
                    controller: scrollCtrl,
                    interactive: true,
                    thumbVisibility: true,
                    thickness: 6,
                    radius: const Radius.circular(8),
                    child: SingleChildScrollView(
                      controller: scrollCtrl,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.only(right: 8),
                      child: MarkdownBody(
                        data: md,
                        onTapLink: (text, href, title) async {
                          if (href == null) return;
                          try {
                            await launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
                          } catch (_) {}
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (ctx2, setSB) => CheckboxListTile(
                    value: hideForever,
                    onChanged: (v) => setSB(() => hideForever = v ?? false),
                    title: Text(S.of(context).hideForever),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.ok),
            ),
          ],
        );
      },
    );
    if (hideForever) {
      final prefs = await SharedPreferences.getInstance();
      if (id != null && id.isNotEmpty) {
  final key = 'hidden_announcement_id_${localeCode ?? S.of(context).locale.languageCode}';
  await prefs.setString(key, id);
      } else {
        await prefs.setBool('hide_announcement_forever', true);
      }
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dailyLimit = prefs.getInt('daily_limit_kcal') ?? 2000;
  _serverHostOverride = prefs.getString('server_host');
  _announcementsDisabled = prefs.getBool('disable_announcements_globally') ?? false;
  _queueMode = prefs.getBool('queue_mode_enabled') ?? true;
    });
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('history_json');
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = json.decode(raw);
      if (decoded is List) {
        final List<Map<String, dynamic>> loaded = [];
        for (final e in decoded) {
          if (e is Map) {
            final m = Map<String, dynamic>.from(e);
            // Ensure types
            if (m['time'] is String) {
              final t = DateTime.tryParse(m['time']);
              if (t != null) m['time'] = t;
            }
            if (m['hcStart'] is String) {
              final t = DateTime.tryParse(m['hcStart']);
              if (t != null) m['hcStart'] = t; else m.remove('hcStart');
            }
            if (m['hcEnd'] is String) {
              final t = DateTime.tryParse(m['hcEnd']);
              if (t != null) m['hcEnd'] = t; else m.remove('hcEnd');
            }
            // Groups: normalize children
            if (m['children'] is List) {
              final List<Map<String, dynamic>> kids = [];
              for (final c in (m['children'] as List)) {
                if (c is Map) {
                  final cm = Map<String, dynamic>.from(c);
                  if (cm['time'] is String) {
                    final t = DateTime.tryParse(cm['time']);
                    if (t != null) cm['time'] = t;
                  }
                  if (cm['hcStart'] is String) {
                    final t = DateTime.tryParse(cm['hcStart']);
                    if (t != null) cm['hcStart'] = t; else cm.remove('hcStart');
                  }
                  if (cm['hcEnd'] is String) {
                    final t = DateTime.tryParse(cm['hcEnd']);
                    if (t != null) cm['hcEnd'] = t; else cm.remove('hcEnd');
                  }
                  kids.add(cm);
                }
              }
              m['children'] = kids;
            }
            loaded.add(m);
          }
        }
        setState(() {
          _history
            ..clear()
            ..addAll(loaded);
        });
      }
    } catch (_) {
      // ignore malformed history
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> toJson(Map<String, dynamic> x) {
      return {
        'isGroup': x['isGroup'] == true,
        'imagePath': (x['imagePath'] as String?) ?? (x['image'] is XFile ? (x['image'] as XFile).path : null),
        'description': x['description'],
        'name': x['name'],
        'result': x['result'],
        'structured': x['structured'],
  'grams': x['grams'],
        'kcal': x['kcal'],
        'carbs': x['carbs'],
        'protein': x['protein'],
        'fat': x['fat'],
        'time': (x['time'] is DateTime) ? (x['time'] as DateTime).toIso8601String() : x['time'],
        'hcStart': (x['hcStart'] is DateTime) ? (x['hcStart'] as DateTime).toIso8601String() : x['hcStart'],
        'hcEnd': (x['hcEnd'] is DateTime) ? (x['hcEnd'] as DateTime).toIso8601String() : x['hcEnd'],
        'hcWritten': x['hcWritten'] == true,
        if (x['children'] is List) 'children': (x['children'] as List).map((c) => toJson(Map<String, dynamic>.from(c))).toList(),
      };
    }
    final serializable = _history.map((m) => toJson(m)).toList();
    await prefs.setString('history_json', json.encode(serializable));
  }

  // Queue & notifications UI
  void _addNotification(String msg) {
    setState(() {
      _notifications.insert(0, {
        'time': DateTime.now(),
        'message': msg,
      });
      if (_notifications.length > 50) _notifications.removeLast();
    });
  }

  void _openQueue() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(S.of(context).backgroundQueue, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (_queue.isEmpty) Text(S.of(context).noPendingJobs),
                if (_queue.isNotEmpty)
                  ..._queue.map((j) {
                    final created = j['createdAt'] as DateTime? ?? DateTime.now();
                    final img = j['imagePath'] as String?;
                    final desc = j['description'] as String?;
                            final status = j['status']?.toString() ?? 'pending';
                            final statusLabel = status == 'error' ? S.of(context).statusError : S.of(context).statusPending;
                    return ListTile(
                      leading: img != null && img.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(img), width: 40, height: 40, fit: BoxFit.cover),
                            )
                          : const Icon(Icons.image_not_supported),
                              title: Text(desc?.isNotEmpty == true ? desc! : S.of(context).noDescription),
                              subtitle: Text('#${j['id']} • ${_formatTimeShort(created)} • $statusLabel'),
                    );
                  }),
                const Divider(),
                Text(S.of(context).notifications, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_notifications.isEmpty) Text(S.of(context).noNotificationsYet),
                if (_notifications.isNotEmpty)
                  SizedBox(
                    height: 200,
                    child: ListView(
                      children: _notifications.map((n) {
                        final t = n['time'] as DateTime? ?? DateTime.now();
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.notifications),
                          title: Text(n['message']?.toString() ?? ''),
                          subtitle: Text(_formatTimeShort(t)),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _ensureHealthConfigured() async {
    if (_healthConfigured) return;
    await _health.configure();
    _healthConfigured = true;
  }

  Future<void> _saveDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('daily_limit_kcal', _dailyLimit);
  }

  

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    setState(() {
      if (pickedFile != null) {
        _image = XFile(pickedFile.path);
      }
    });
  }

  Future<void> _captureImage() async {
    // Camera not supported on Linux/Windows/macOS via image_picker.
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera capture not supported on this platform. Use Pick Image instead.')),
      );
      return;
    }
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.camera);
      if (!mounted) return;
      setState(() {
        if (pickedFile != null) {
          _image = XFile(pickedFile.path);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open camera: $e')),
      );
    }
  }

  // _sendMessage removed in favor of _sendOrQueue()

  String _newJobId() => 'job_${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecondsSinceEpoch % 10000}';

  Future<void> _sendOrQueue() async {
    final capturedImage = _image;
    final capturedText = _controller.text;
    if (capturedImage == null && capturedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).provideMsgOrImage)),
      );
      return;
    }
    if (_queueMode) {
      final jobId = _newJobId();
      setState(() {
        _queue.add({
          'id': jobId,
          'imagePath': capturedImage?.path,
          'description': capturedText,
          'createdAt': DateTime.now(),
          'status': 'pending',
        });
        _image = null;
        _controller.clear();
      });
      // ignore: discarded_futures
      _sendMessageCore(image: capturedImage, text: capturedText, useFlash: false, jobId: jobId);
  _addNotification(S.of(context).queuedRequest(jobId));
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).queuedWorking)));
    } else {
      setState(() => _loading = true);
      try {
        await _sendMessageCore(image: capturedImage, text: capturedText, useFlash: false);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<void> _sendMessageCore({required XFile? image, required String text, required bool useFlash, String? jobId}) async {
    final uri = Uri.parse('${_baseUrl()}/data${useFlash ? '?flash=1' : ''}');
    final request = http.MultipartRequest('POST', uri)
      ..fields['message'] = text;
    request.headers['x-app-token'] = 'FromHectaroxWithLove';
    final _lang = S.of(context).locale.languageCode;
    request.headers['Accept-Language'] = _lang;
    request.fields['lang'] = _lang;
    if (authState.token != null) {
      request.headers['Authorization'] = 'Bearer ${authState.token}';
    }
    if (image != null) {
      request.files.add(await http.MultipartFile.fromPath(
        'image',
        image.path,
        contentType: MediaType.parse(lookupMimeType(image.path) ?? 'application/octet-stream'),
      ));
    }
    http.StreamedResponse? response;
    String responseBody = '';
    try {
      response = await request.send();
      responseBody = await response.stream.bytesToString();

  if (response.statusCode == 200) {
  String pretty;
        try {
          final decoded = json.decode(responseBody);
          if (decoded is Map && decoded['ok'] == true) {
            final data = decoded['data'];
            if (data is String) {
              pretty = data;
            } else {
              pretty = const JsonEncoder.withIndent('  ').convert(data);
            }
          } else if (decoded is Map && decoded.containsKey('response')) {
            pretty = decoded['response'].toString();
          } else {
            pretty = responseBody;
          }
        } catch (_) {
          pretty = responseBody;
        }

  // Try to extract a structured map and kcal value for better UI
  Map<String, dynamic>? structured;
  int? kcal;
  int? carbs;
  int? protein;
  int? fat;
  String? mealName;
        try {
          final decoded = json.decode(responseBody);
          if (decoded is Map && decoded['ok'] == true && decoded['data'] is Map) {
            structured = Map<String, dynamic>.from(decoded['data'] as Map);
          } else if (decoded is Map) {
            structured = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
        // Extract preferred fields if present
  if (structured != null) {
          // Localize/normalize structured keys for the current UI locale
          structured = _localizedStructured(structured);
          mealName = structured['Name']?.toString() ?? structured["Nom de l'aliment"]?.toString() ?? structured['name']?.toString();
        }

        // Fallback: attempt to parse calories & carbs/protein/fat from any text
        String textSource = structured != null ? jsonEncode(structured) : pretty;
        // kcal can be integer or decimal (rare); round to nearest int
        final kcalMatch = RegExp(r'(\d{1,5}(?:[\.,]\d{1,2})?)\s*(k?cal|kilo?calories?)', caseSensitive: false)
            .firstMatch(textSource);
        if (kcalMatch != null) {
          final raw = kcalMatch.group(1)!.replaceAll(',', '.');
          final d = double.tryParse(raw);
          if (d != null) kcal = d.round();
        } else if (structured != null) {
          final calVal = structured['Calories'] ?? structured['kcal'] ?? structured['calories'];
          if (calVal != null) {
            final numMatch = RegExp(r'(\d+(?:[\.,]\d+)?)').firstMatch(calVal.toString());
            if (numMatch != null) {
              final d = double.tryParse(numMatch.group(1)!.replaceAll(',', '.'));
              if (d != null) kcal = d.round();
            }
          }
        }

  // carbs can be decimal like 60.2g; round to nearest gram
        final carbsMatch = RegExp(r'(\d{1,4}(?:[\.,]\d{1,2})?)\s*g\s*(carb|glucid\w*)', caseSensitive: false)
            .firstMatch(textSource);
        if (carbsMatch != null) {
          final raw = carbsMatch.group(1)!.replaceAll(',', '.');
          final d = double.tryParse(raw);
          if (d != null) carbs = d.round();
        } else if (structured != null) {
          final cVal = structured['Glucides'] ?? structured['carbs'] ?? structured['Carbs'];
          if (cVal != null) {
            final numMatch = RegExp(r'(\d+(?:[\.,]\d+)?)').firstMatch(cVal.toString());
            if (numMatch != null) {
              final d = double.tryParse(numMatch.group(1)!.replaceAll(',', '.'));
              if (d != null) carbs = d.round();
            }
          }
        }

        // proteins
        final proteinMatch = RegExp(r'(\d{1,4}(?:[\.,]\d{1,2})?)\s*g\s*(protein|prot\w*)', caseSensitive: false)
            .firstMatch(textSource);
        if (proteinMatch != null) {
          final raw = proteinMatch.group(1)!.replaceAll(',', '.');
          final d = double.tryParse(raw);
          if (d != null) protein = d.round();
        } else if (structured != null) {
          final pVal = structured['Proteines'] ?? structured['protein'] ?? structured['Proteins'];
          if (pVal != null) {
            final numMatch = RegExp(r'(\d+(?:[\.,]\d+)?)').firstMatch(pVal.toString());
            if (numMatch != null) {
              final d = double.tryParse(numMatch.group(1)!.replaceAll(',', '.'));
              if (d != null) protein = d.round();
            }
          }
        }

        // fats
        final fatMatch = RegExp(r'(\d{1,4}(?:[\.,]\d{1,2})?)\s*g\s*(fat|lipid\w*|gras)', caseSensitive: false)
            .firstMatch(textSource);
        if (fatMatch != null) {
          final raw = fatMatch.group(1)!.replaceAll(',', '.');
          final d = double.tryParse(raw);
          if (d != null) fat = d.round();
        } else if (structured != null) {
          final fVal = structured['Lipides'] ?? structured['fat'] ?? structured['Fats'];
          if (fVal != null) {
            final numMatch = RegExp(r'(\d+(?:[\.,]\d+)?)').firstMatch(fVal.toString());
            if (numMatch != null) {
              final d = double.tryParse(numMatch.group(1)!.replaceAll(',', '.'));
              if (d != null) fat = d.round();
            }
          }
        }

        // Capture overall grams from AI output (structured or text)
        final aiGrams = _extractGrams(structured, textSource);

        final newMeal = {
          'image': image,
          'imagePath': image?.path,
          'description': text,
          'name': mealName ?? (text.isNotEmpty ? text : null),
          // Prefer pretty-printed, locale-normalized JSON when available
          'result': structured != null ? const JsonEncoder.withIndent('  ').convert(structured) : pretty,
          'structured': structured,
          'grams': aiGrams,
          'kcal': kcal,
          'carbs': carbs,
          'protein': protein,
          'fat': fat,
          'time': DateTime.now(),
          'hcWritten': false,
        };
        setState(() {
          _resultText = pretty;
          _history.add(newMeal);
          _pruneHistory();
          if (jobId != null) {
            final idx = _queue.indexWhere((j) => j['id'] == jobId);
            if (idx >= 0) _queue.removeAt(idx);
          }
        });
    await _saveHistory();

        // If user is building a meal, append this item into the active group
        if (_pendingMealGroup != null) {
          _appendToGroup(_pendingMealGroup!, newMeal);
          await _saveHistory();
        }

        // Notify, reset composer, and show the result in History so users see success
  if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).resultSaved)),
          );
          if (jobId == null) {
            setState(() {
              _image = null;
              _controller.clear();
            });
            _tabController.animateTo(0);
          }
          _addNotification('Result saved${jobId != null ? ' (#$jobId)' : ''}');
          // Open details after the tab switches
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) _showMealDetails(newMeal);
          });
        }

        // Try to sync to Health Connect (Android) when available
        // Request permissions only when we have data to write
        try {
          await _ensureHealthConfigured();
          if (mounted && (kcal != null || carbs != null || protein != null || fat != null)) {
            // On Android, ensure Health Connect is installed/updated before asking permissions
            if (!kIsWeb && Platform.isAndroid) {
              final status = await _health.getHealthConnectSdkStatus();
              if (mounted) setState(() => _hcSdkStatus = status);
              if (status != HealthConnectSdkStatus.sdkAvailable) {
                if (mounted) {
                  final s = S.of(context);
                  final msg = status == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired
                      ? s.updateHc
                      : s.installHc;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                }
                // Offer to install/update via the Daily tab button; bail out of writing
                return;
              }
            }
            // Request Nutrition permissions (covers calories/macros on Android HC)
            final ok = await _health.requestAuthorization(
              [HealthDataType.NUTRITION],
              permissions: [HealthDataAccess.READ_WRITE],
            );
            if (ok) {
              final start = DateTime.now();
              // Ensure endTime is after startTime; some HC providers reject equal timestamps
              final end = start.add(const Duration(minutes: 1));
              // Store timestamps so we can delete the same record later
              newMeal['hcStart'] = start;
              newMeal['hcEnd'] = end;
              final written = await _health.writeMeal(
                mealType: MealType.UNKNOWN,
                startTime: start,
                endTime: end,
                caloriesConsumed: kcal?.toDouble(),
                carbohydrates: carbs?.toDouble(),
                protein: protein?.toDouble(),
                fatTotal: fat?.toDouble(),
                name: mealName ?? (text.isNotEmpty ? text : null),
              );
              if (mounted) {
                setState(() => _healthAuthorized = true);
                // Show quick feedback and capture failures for troubleshooting
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(written ? S.of(context).hcWriteOk : S.of(context).hcWriteFail)),
                );
                if (written) {
                  // mark written and persist
                  setState(() {
                    newMeal['hcWritten'] = true;
                  });
                  await _saveHistory();
                } else {
                  setState(() => _healthLastError = 'writeMeal returned false');
                }
              }
            }
          }
        } catch (e) {
          if (mounted) setState(() => _healthLastError = e.toString());
        }
      } else {
        // Try to show a friendly server-provided error first
        String? serverMsg;
        try {
          final decoded = json.decode(responseBody);
          if (decoded is Map && decoded['ok'] == false && decoded['error'] is String) {
            serverMsg = decoded['error'] as String;
          }
        } catch (_) {}
  final is50x = response.statusCode == 503 || response.statusCode == 500;
    final s = S.of(context);
    final msg = (serverMsg != null && serverMsg.isNotEmpty)
      ? serverMsg
      : (is50x
        ? s.aiOverloaded
        : s.requestFailedWithCode(response.statusCode));
        if (mounted) {
          if (jobId != null) {
            final idx = _queue.indexWhere((j) => j['id'] == jobId);
            if (idx >= 0) setState(() => _queue[idx]['status'] = 'error');
            _addNotification('Request failed (#$jobId): $msg');
          }
          if (is50x) {
            // Show a popup dialog to switch to flash model
      showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
        title: Text(s.flashTitle),
        content: Text('$msg\n\n${s.flashExplain}'),
                actions: [
                  TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(s.cancel),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _sendMessageFlashDebug();
                    },
                    child: Text(s.debugRaw),
                  ),
                  FilledButton(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _sendMessageCore(image: image, text: text, useFlash: true, jobId: jobId);
                    },
          child: Text(s.useFlash),
                  ),
                ],
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)),
            );
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).serviceUnavailable)),
      );
      if (jobId != null) {
        final idx = _queue.indexWhere((j) => j['id'] == jobId);
        if (idx >= 0) setState(() => _queue[idx]['status'] = 'error');
        _addNotification('Request failed (#$jobId)');
      }
    } finally {
      // _loading handled by caller for non-queue mode
    }
  }

  // _sendMessageWithModel removed; flash path reuses _sendMessageCore with useFlash=true.

  Future<void> _sendMessageFlashDebug() async {
    // Sends the same request with flash=1 and shows the raw response body in a dialog for debugging.
    if (_image == null && _controller.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).provideMsgOrImage)),
        );
      }
      return;
    }
  // Force pro model for debugging to compare against flash behavior
  final uri = Uri.parse('${_baseUrl()}/data?flash=0');
    final request = http.MultipartRequest('POST', uri)
      ..fields['message'] = _controller.text;
    request.headers['x-app-token'] = 'FromHectaroxWithLove';
    if (authState.token != null) request.headers['Authorization'] = 'Bearer ${authState.token}';
    if (_image != null) {
      request.files.add(await http.MultipartFile.fromPath(
        'image',
        _image!.path,
        contentType: MediaType.parse(lookupMimeType(_image!.path) ?? 'application/octet-stream'),
      ));
    }
    if (mounted) setState(() => _loading = true);
    String body = '';
    int status = 0;
    try {
      final response = await request.send();
      status = response.statusCode;
      body = await response.stream.bytesToString();
    } catch (e) {
      body = 'Error: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;
    final s = S.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.debugRawTitle} (${status})'),
        content: SingleChildScrollView(child: SelectableText(body.isEmpty ? s.emptyResponse : body)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(s.ok)),
        ],
      ),
    );
  }

  void _pruneHistory() {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    _history.removeWhere((e) => (e['time'] as DateTime).isBefore(cutoff));
  }

  Future<void> _checkHealthStatus() async {
    try {
      await _ensureHealthConfigured();
      final status = await _health.getHealthConnectSdkStatus();
      final has = await _health.hasPermissions([HealthDataType.NUTRITION], permissions: [HealthDataAccess.READ_WRITE]);
      if (mounted) {
        setState(() {
          _hcSdkStatus = status;
          _healthAuthorized = has ?? false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _healthLastError = e.toString());
    }
  }

  Future<void> _requestHealthPermissions() async {
    try {
      await _ensureHealthConfigured();
  final ok = await _health.requestAuthorization([HealthDataType.NUTRITION], permissions: [HealthDataAccess.READ_WRITE]);
      if (mounted) setState(() => _healthAuthorized = ok);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? S.of(context).hcGranted : S.of(context).hcDenied)));
      }
    } catch (e) {
      if (mounted) setState(() => _healthLastError = e.toString());
    }
  }

  Future<void> _loadTodayBurned() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    DateTime now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = now;
    try {
      await _ensureHealthConfigured();
      if (Platform.isAndroid) {
        final status = await _health.getHealthConnectSdkStatus();
        if (mounted) setState(() => _hcSdkStatus = status);
        if (status != HealthConnectSdkStatus.sdkAvailable) return;
      }
      // Mandatory permission: TOTAL_CALORIES_BURNED
      final totalGranted = await _health.requestAuthorization(
        [HealthDataType.TOTAL_CALORIES_BURNED],
        permissions: const [HealthDataAccess.READ],
      );
      if (!totalGranted) {
        if (mounted) setState(() => _healthLastError = 'Permission denied for TOTAL_CALORIES_BURNED');
        return;
      }
      // Optional permission: ACTIVE_ENERGY_BURNED (may be unavailable on some devices)
      bool activeGranted = false;
      try {
        activeGranted = await _health.requestAuthorization(
          [HealthDataType.ACTIVE_ENERGY_BURNED],
          permissions: const [HealthDataAccess.READ],
        );
      } catch (_) {
        activeGranted = false;
      }
      if (mounted) setState(() => _loadingBurned = true);
      // Fetch TOTAL points
      final totalPoints = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: end,
        types: const [HealthDataType.TOTAL_CALORIES_BURNED],
      );
      double sumTotal = 0.0;
      for (final dp in totalPoints) {
        final v = _asDouble(dp.value);
        if (v == null || !v.isFinite) continue;
        sumTotal += v;
      }
      // Fetch ACTIVE if granted
      double? sumActive;
      if (activeGranted) {
        try {
          final activePoints = await _health.getHealthDataFromTypes(
            startTime: start,
            endTime: end,
            types: const [HealthDataType.ACTIVE_ENERGY_BURNED],
          );
          double tmp = 0.0;
          for (final dp in activePoints) {
            final v = _asDouble(dp.value);
            if (v == null || !v.isFinite) continue;
            tmp += v;
          }
          sumActive = tmp;
        } catch (_) {
          sumActive = null;
        }
      }
      final total = sumTotal;
      if (mounted) {
        setState(() {
          _todayActiveBurnedKcal = sumActive;
          _todayTotalBurnedKcal = total;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _healthLastError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingBurned = false);
    }
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString();
    final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(s);
    if (m != null) return double.tryParse(m.group(0)!);
    return null;
  }

  // --- Helpers to extract grams (overall weight) from AI outputs ---
  int? _extractGrams(dynamic structured, String textSource) {
    int? fromStructured(dynamic node) {
      if (node is Map) {
        for (final entry in node.entries) {
          final k = entry.key.toString().toLowerCase();
          if (k.contains('weight') || k.contains('poids')) {
            final n = _numberFromAny(entry.value);
            if (n != null) return n.round();
          }
          final inner = fromStructured(entry.value);
          if (inner != null) return inner;
        }
      } else if (node is List) {
        for (final e in node) {
          final inner = fromStructured(e);
          if (inner != null) return inner;
        }
      }
      return null;
    }

    int? fromText(String s) {
      final r1 = RegExp(r'(?:weight|poids)[^\d]{0,12}(\d{1,4}(?:[\.,]\d{1,2})?)\s*g', caseSensitive: false);
      final m1 = r1.firstMatch(s);
      if (m1 != null) {
        final d = double.tryParse(m1.group(1)!.replaceAll(',', '.'));
        if (d != null) return d.round();
      }
      final r2 = RegExp(r'(\d{1,4}(?:[\.,]\d{1,2})?)\s*g[^A-Za-z]{0,6}(?:weight|poids)', caseSensitive: false);
      final m2 = r2.firstMatch(s);
      if (m2 != null) {
        final d = double.tryParse(m2.group(1)!.replaceAll(',', '.'));
        if (d != null) return d.round();
      }
      return null;
    }

    return fromStructured(structured) ?? fromText(textSource);
  }

  double? _numberFromAny(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString();
    final m = RegExp(r'(\d{1,4}(?:[\.,]\d{1,2})?)').firstMatch(s);
    if (m != null) return double.tryParse(m.group(1)!.replaceAll(',', '.'));
    return null;
  }

  Map<String, List<Map<String, dynamic>>> _groupHistoryByDay() {
    final Map<String, List<Map<String, dynamic>>> groups = {};
    final now = DateTime.now();
    for (final item in _history..sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime))) {
      final dt = (item['time'] as DateTime).toLocal();
      final dayKey = _dayBucket(now, dt);
      groups.putIfAbsent(dayKey, () => []).add(item);
    }
    return groups;
  }

  String _dayBucket(DateTime now, DateTime dt) {
    final dNow = DateTime(now.year, now.month, now.day);
    final dDt = DateTime(dt.year, dt.month, dt.day);
    final diff = dNow.difference(dDt).inDays;
  if (diff == 0) return S.of(context).today;
  if (diff == 1) return S.of(context).yesterday;
    return DateFormat('d MMMM').format(dDt);
  }

  int _todayKcal() {
    final today = DateTime.now();
    final dToday = DateTime(today.year, today.month, today.day);
    int sum = 0;
    for (final item in _history) {
      final t = (item['time'] as DateTime);
      final d = DateTime(t.year, t.month, t.day);
      if (d == dToday && item['kcal'] is int) sum += item['kcal'] as int;
    }
    return sum;
  }

  String _baseUrl() {
    // Legacy host-only override
    if (_serverHostOverride != null && _serverHostOverride!.isNotEmpty) {
      return 'http://${_serverHostOverride}:3000';
    }
    // Defaults
    return 'http://141.145.210.115:3007';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.appTitle),
        leading: IconButton(
          tooltip: S.of(context).info,
          icon: const Icon(Icons.info_outline),
          onPressed: _openInfo,
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                tooltip: S.of(context).queueAndNotifications,
                onPressed: _openQueue,
                icon: const Icon(Icons.notifications_outlined),
              ),
              if (_queue.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _queue.length.toString(),
                      style: TextStyle(color: scheme.onError, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: s.settings,
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          )
        ],
      ),
    body: TabBarView(
        controller: _tabController,
        children: [
          _buildHistoryTab(),
          _buildMainTab(),
      _buildDailyTab(),
        ],
      ),
      bottomNavigationBar: Material(
        color: scheme.surface,
        child: SafeArea(
          top: false,
          child: TabBar(
            controller: _tabController,
            tabs: [
              Tab(icon: const Icon(Icons.history), text: s.tabHistory),
              Tab(icon: const Icon(Icons.camera_alt), text: s.tabMain),
              Tab(icon: const Icon(Icons.local_fire_department), text: s.tabDaily),
            ],
            indicatorColor: scheme.primary,
            labelColor: scheme.primary,
            unselectedLabelColor: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  void _openSettings() {
    final s = S.of(context);
    final current = appSettings.locale?.languageCode ?? 'system';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 0,
              right: 0,
              top: 0,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(title: Text(s.settings, style: Theme.of(ctx).textTheme.titleLarge)),
                RadioListTile<String>(
                  value: 'system',
                  groupValue: current,
                  title: Text(s.systemLanguage),
                  onChanged: (_) {
                    appSettings.setLocale(null);
                    Navigator.pop(ctx);
                  },
                ),
                RadioListTile<String>(
                  value: 'en',
                  groupValue: current,
                  title: const Text('English'),
                  onChanged: (_) {
                    appSettings.setLocale(const Locale('en'));
                    Navigator.pop(ctx);
                  },
                ),
                RadioListTile<String>(
                  value: 'fr',
                  groupValue: current,
                  title: const Text('Français'),
                  onChanged: (_) {
                    appSettings.setLocale(const Locale('fr'));
                    Navigator.pop(ctx);
                  },
                ),
                const Divider(),
                SwitchListTile(
                  value: _announcementsDisabled,
                  title: Text(S.of(context).disableAnnouncements),
                  subtitle: Text(S.of(context).disableAnnouncementsHint),
                  onChanged: (v) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('disable_announcements_globally', v);
                    if (!mounted) return;
                    setState(() => _announcementsDisabled = v);
                    Navigator.pop(ctx);
                  },
                ),
                const Divider(),
                SwitchListTile(
                  value: appSettings.daltonian,
                  title: Text(s.daltonianMode),
                  subtitle: Text(s.daltonianModeHint),
                  onChanged: (v) async {
                    await appSettings.setDaltonian(v);
                    if (mounted) Navigator.pop(ctx);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: Text(s.exportHistory),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _exportHistory();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: Text(s.importHistory),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _importHistory();
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(S.of(context).logout),
                  onTap: () async {
                    await authState.setToken(null);
                    if (mounted) {
                      Navigator.pop(ctx);
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('history_json') ?? json.encode(_history.map((m) {
        Map<String, dynamic> toJson(Map<String, dynamic> x) {
          return {
            'isGroup': x['isGroup'] == true,
            'imagePath': (x['imagePath'] as String?) ?? (x['image'] is XFile ? (x['image'] as XFile).path : null),
            'description': x['description'],
            'name': x['name'],
            'result': x['result'],
            'structured': x['structured'],
            'grams': x['grams'],
            'kcal': x['kcal'],
            'carbs': x['carbs'],
            'protein': x['protein'],
            'fat': x['fat'],
            'time': (x['time'] is DateTime) ? (x['time'] as DateTime).toIso8601String() : x['time'],
            'hcStart': (x['hcStart'] is DateTime) ? (x['hcStart'] as DateTime).toIso8601String() : x['hcStart'],
            'hcEnd': (x['hcEnd'] is DateTime) ? (x['hcEnd'] as DateTime).toIso8601String() : x['hcEnd'],
            'hcWritten': x['hcWritten'] == true,
            if (x['children'] is List) 'children': (x['children'] as List).map((c) => toJson(Map<String, dynamic>.from(c))).toList(),
          };
        }
        return toJson(Map<String, dynamic>.from(m));
      }).toList());

      final bytes = utf8.encode(raw);
      final filename = 'nutrilens-history-${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: S.of(context).exportHistory,
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(bytes),
      );
      if (!mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).exportCanceled)));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).exportSuccess)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).exportFailed)));
    }
  }

  Future<void> _importHistory() async {
    final s = S.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.importHistory),
        content: Text(s.confirmImportReplace),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(MaterialLocalizations.of(ctx).okButtonLabel)),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final res = await FilePicker.platform.pickFiles(
        dialogTitle: S.of(context).importHistory,
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.first;
      final data = file.bytes ?? await File(file.path!).readAsBytes();
      final decoded = json.decode(utf8.decode(data));
      if (decoded is! List) throw Exception('Invalid history');

      final List<Map<String, dynamic>> loaded = [];
      for (final e in decoded) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          if (m['time'] is String) {
            final t = DateTime.tryParse(m['time']);
            if (t != null) m['time'] = t;
          }
          if (m['hcStart'] is String) {
            final t = DateTime.tryParse(m['hcStart']);
            if (t != null) m['hcStart'] = t; else m.remove('hcStart');
          }
          if (m['hcEnd'] is String) {
            final t = DateTime.tryParse(m['hcEnd']);
            if (t != null) m['hcEnd'] = t; else m.remove('hcEnd');
          }
          if (m['children'] is List) {
            final List<Map<String, dynamic>> kids = [];
            for (final c in (m['children'] as List)) {
              if (c is Map) {
                final cm = Map<String, dynamic>.from(c);
                if (cm['time'] is String) {
                  final t = DateTime.tryParse(cm['time']);
                  if (t != null) cm['time'] = t;
                }
                if (cm['hcStart'] is String) {
                  final t = DateTime.tryParse(cm['hcStart']);
                  if (t != null) cm['hcStart'] = t; else cm.remove('hcStart');
                }
                if (cm['hcEnd'] is String) {
                  final t = DateTime.tryParse(cm['hcEnd']);
                  if (t != null) cm['hcEnd'] = t; else cm.remove('hcEnd');
                }
                kids.add(cm);
              }
            }
            m['children'] = kids;
          }
          loaded.add(m);
        }
      }
      setState(() {
        _history
          ..clear()
          ..addAll(loaded);
      });
      await _saveHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).importSuccess)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).importFailed)));
    }
  }

  Future<void> _openInfo() async {
    final s = S.of(context);
    PackageInfo info;
    try {
      info = await PackageInfo.fromPlatform();
    } catch (_) {
      info = PackageInfo(appName: 'App', packageName: 'app', version: 'unknown', buildNumber: '-', buildSignature: '', installerStore: null);
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.about, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(s.versionBuild(info.version, info.buildNumber)),
                const SizedBox(height: 12),
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.discord),
                  title: Text(s.joinDiscord),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () async {
                    final uri = Uri.parse('https://discord.gg/8bDDqbvr8K');
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                ),
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.github),
                  title: Text(s.openGithubIssue),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () async {
                    final uri = Uri.parse('https://github.com/hectarox/NutriLens/issues');
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    final scheme = Theme.of(context).colorScheme;
  final s = S.of(context);
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
      Text(s.noHistory, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    final grouped = _groupHistoryByDay();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: grouped.entries.map((entry) {
        final totalCarbs = entry.value.fold<int>(0, (s, e) => s + (e['carbs'] as int? ?? 0));
        final totalProtein = entry.value.fold<int>(0, (s, e) => s + (e['protein'] as int? ?? 0));
        final totalFat = entry.value.fold<int>(0, (s, e) => s + (e['fat'] as int? ?? 0));
        return _ExpandableDaySection(
          title: entry.key,
          totalKcal: entry.value.fold<int>(0, (s, e) => s + (e['kcal'] as int? ?? 0)),
          totalCarbs: totalCarbs,
          totalProtein: totalProtein,
          totalFat: totalFat,
          children: entry.value.map<Widget>((meal) {
            return _HistoryMealCard(
              meal: meal,
              onDelete: () async {
                // Attempt to delete from Health Connect if previously written
                try {
                  await _ensureHealthConfigured();
                  if (!kIsWeb && Platform.isAndroid && (meal['hcWritten'] == true)) {
                    final hs = meal['hcStart'];
                    final he = meal['hcEnd'];
                    final start = hs is DateTime ? hs : (hs is String ? DateTime.tryParse(hs) : null);
                    final end = he is DateTime ? he : (he is String ? DateTime.tryParse(he) : null);
                    if (start != null && end != null) {
                      // Ensure permissions and delete nutrition entries in the same timespan
                      await _health.requestAuthorization([HealthDataType.NUTRITION], permissions: [HealthDataAccess.READ_WRITE]);
                      await _health.delete(type: HealthDataType.NUTRITION, startTime: start, endTime: end);
                    }
                  }
                } catch (_) {}
                setState(() => _history.remove(meal));
                await _saveHistory();
              },
              onTap: () => _showMealDetails(meal),
              onDrop: (source) => _mergeMeals(source, meal),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _buildMainTab() {
    final s = S.of(context);
    final canUseCamera = !kIsWeb && !(Platform.isLinux || Platform.isWindows || Platform.isMacOS);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_pendingMealGroup != null)
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  const Icon(Icons.restaurant, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.mealBuilderActive)),
                  TextButton.icon(onPressed: _finishPendingMeal, icon: const Icon(Icons.check), label: Text(s.finishMeal)),
                ],
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _controller,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: s.describeMeal,
                    hintText: s.describeMealHint,
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _queueMode,
                  onChanged: (v) async {
                    final enabled = v ?? false;
                    setState(() => _queueMode = enabled);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('queue_mode_enabled', enabled);
                  },
                  contentPadding: EdgeInsets.zero,
                  title: Text(S.of(context).queueInBackground),
                  subtitle: Text(S.of(context).queueInBackgroundHint),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _addManualFood,
                      icon: const Icon(Icons.add),
                      label: Text(s.addManual),
                    ),
                    if (canUseCamera)
                      FilledButton.icon(
                        onPressed: _scanBarcode,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: Text(s.scanBarcode),
                      ),
                    if (canUseCamera)
                      FilledButton.icon(
                        onPressed: _captureImage,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(s.takePhoto),
                      ),
                    FilledButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(s.pickImage),
                    ),
                    FilledButton.icon(
                      onPressed: (_loading && !_queueMode) ? null : _sendOrQueue,
                      icon: const Icon(Icons.send_rounded),
                      label: Text((_loading && !_queueMode) ? s.sending : s.sendToAI),
                    ),
                  ],
                ),
                if (_image != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_image!.path),
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_resultText.isNotEmpty) _FormattedResultCard(resultText: _resultText),
      ],
    );
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _BarcodeScannerScreen()),
    );
    if (!mounted || code == null || code.isEmpty) return;
    // Fetch product from Open Food Facts
    final product = await _fetchOffProduct(code);
    if (product == null) {
      if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).productNotFound)));
      return;
    }
    // Ask user quantity: empty for full package, or custom weight
    final qty = await _askQuantity(defaultServing: product.servingSizeGrams);
    if (!mounted) return;
    final grams = qty?.trim().isEmpty == true ? product.servingSizeGrams : int.tryParse(qty ?? '');
    // Build meal from OFF nutrients (per 100g scaled or per serving)
    final scaled = product.scaleFor(grams);
    final localizedStructured = _localizedStructured({
      'Name': product.name ?? '-',
      'Calories': '${scaled.kcal?.toStringAsFixed(0) ?? '-'} kcal',
      'Carbs': '${scaled.carbs?.toStringAsFixed(0) ?? '-'} g',
      'Proteins': '${scaled.protein?.toStringAsFixed(0) ?? '-'} g',
      'Fats': '${scaled.fat?.toStringAsFixed(0) ?? '-'} g',
  if (grams != null) 'Weight (g)': '${grams} g',
    });
    final newMeal = {
      'image': null,
      'imagePath': null,
  'description': product.name ?? S.of(context).packagedFood,
      'name': product.name,
      'result': const JsonEncoder.withIndent('  ').convert(localizedStructured),
      'structured': localizedStructured,
  'grams': grams,
      'kcal': scaled.kcal?.round(),
      'carbs': scaled.carbs?.round(),
      'protein': scaled.protein?.round(),
      'fat': scaled.fat?.round(),
      'time': DateTime.now(),
      'hcWritten': false,
    };
    setState(() {
      _history.add(newMeal);
      _pruneHistory();
    });
    await _saveHistory();
    if (_pendingMealGroup != null) {
      _appendToGroup(_pendingMealGroup!, newMeal);
      await _saveHistory();
    }
    if (mounted) {
      _tabController.animateTo(0);
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _showMealDetails(newMeal);
      });
  _maybeOfferAddAnother(newMeal);
    }
    // Optionally, write to Health Connect if desired
    try {
      await _ensureHealthConfigured();
      final kcal = scaled.kcal?.round();
      final carbs = scaled.carbs?.round();
      final protein = scaled.protein?.round();
      final fat = scaled.fat?.round();
      if ((kcal != null || carbs != null || protein != null || fat != null) && !kIsWeb && Platform.isAndroid) {
        final status = await _health.getHealthConnectSdkStatus();
        if (mounted) setState(() => _hcSdkStatus = status);
        if (status == HealthConnectSdkStatus.sdkAvailable) {
          final ok = await _health.requestAuthorization([HealthDataType.NUTRITION], permissions: [HealthDataAccess.READ_WRITE]);
          if (ok) {
            final start = DateTime.now();
            final end = start.add(const Duration(minutes: 1));
            newMeal['hcStart'] = start;
            newMeal['hcEnd'] = end;
            final written = await _health.writeMeal(
              mealType: MealType.UNKNOWN,
              startTime: start,
              endTime: end,
              caloriesConsumed: kcal?.toDouble(),
              carbohydrates: carbs?.toDouble(),
              protein: protein?.toDouble(),
              fatTotal: fat?.toDouble(),
              name: product.name,
            );
            if (mounted && written) {
              setState(() => newMeal['hcWritten'] = true);
              await _saveHistory();
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<String?> _askQuantity({int? defaultServing}) async {
    final controller = TextEditingController();
    final s = S.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.quantityTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(defaultServing != null
                ? s.quantityHelpDefaultServing(defaultServing)
                : s.quantityHelpPackage),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: s.exampleNumber),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(s.save)),
        ],
      ),
    );
  }

  Future<_OffProduct?> _fetchOffProduct(String barcode) async {
    try {
      // Open Food Facts public API (no key required); "run the api on the device" interpreted as direct device-side HTTP call
      final uri = Uri.parse('https://world.openfoodfacts.org/api/v2/product/$barcode.json');
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;
      final jsonMap = json.decode(res.body);
      if (jsonMap is! Map || jsonMap['product'] is! Map) return null;
      return _OffProduct.fromJson(jsonMap['product'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Widget _buildDailyTab() {
    final s = S.of(context);
    final todayKcal = _todayKcal();
    final todayCarbs = _todayCarbs();
    final pct = _dailyLimit == 0 ? 0.0 : (todayKcal / _dailyLimit).clamp(0.0, 2.0);
    Color barColor;
    if (pct < 0.7) {
      barColor = Colors.green;
    } else if (pct < 1.0) {
      barColor = Colors.orange;
    } else {
      final over = (pct - 1.0).clamp(0.0, 1.0);
      barColor = Color.lerp(Colors.red.shade600, Colors.red.shade900, over) ?? Colors.red;
    }
  return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(s.dailyIntake, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('${s.today}: $todayKcal / $_dailyLimit ${s.kcalSuffix} • $todayCarbs ${s.carbsSuffix}'),
                  const SizedBox(height: 12),
                  _ProgressBar(value: pct.clamp(0.0, 1.5), color: barColor),
                  const SizedBox(height: 16),
                  Text(s.dailyLimit),
                  Slider(
                    value: _dailyLimit.toDouble(),
                    min: 1000,
                    max: 4000,
                    divisions: 30,
                    label: '$_dailyLimit ${s.kcalSuffix}',
                    onChanged: (v) {
                      setState(() => _dailyLimit = v.round());
                    },
                    onChangeEnd: (_) async {
                      await _saveDailyLimit();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_fire_department),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s.burnedTodayTitle, style: Theme.of(context).textTheme.titleLarge)),
                        IconButton(
                          tooltip: s.burnedHelp,
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(s.burnedTodayTitle),
                                content: Text(s.burnedHelpText),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.ok)),
                                ],
                              ),
                            );
                          },
                          icon: const Icon(Icons.help_outline),
                        ),
                        IconButton(
                          tooltip: s.refreshBurned,
                          onPressed: _loadingBurned ? null : _loadTodayBurned,
                          icon: _loadingBurned
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Total burned (basal + active) — compare to today's consumed kcal instead of daily limit
                    Text(_todayTotalBurnedKcal != null
                        ? '${s.totalLabel}: ${_todayTotalBurnedKcal!.round()} ${s.kcalSuffix}'
                        : s.burnedNotAvailable),
                    const SizedBox(height: 8),
                    _ProgressBar(
                      value: todayKcal <= 0 || _todayTotalBurnedKcal == null
                          ? 0
                          : (_todayTotalBurnedKcal! / todayKcal).clamp(0.0, 1.5),
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(height: 12),
                    // Active burned only
                    if (_todayActiveBurnedKcal != null) ...[
                      Text('${s.activeLabel}: ${_todayActiveBurnedKcal!.round()} ${s.kcalSuffix}'),
                      const SizedBox(height: 8),
                      _ProgressBar(
                        value: todayKcal <= 0
                            ? 0
                            : (_todayActiveBurnedKcal! / todayKcal).clamp(0.0, 1.5),
                        color: Colors.orangeAccent,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Builder(builder: (_) {
                      final burned = _todayTotalBurnedKcal?.round() ?? 0;
                      final net = todayKcal - burned; // positive -> surplus, negative -> deficit
                      final isSurplus = net > 0;
                      final label = isSurplus ? s.surplusLabel : (net < 0 ? s.deficitLabel : s.netKcalLabel);
                      final display = net == 0 ? '0' : net.abs().toString();
                      return Text('${s.netKcalLabel}: ${isSurplus ? '+' : (net < 0 ? '-' : '')}$display ${s.kcalSuffix} • $label');
                    }),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          // Health Connect status & actions
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.favorite, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s.healthConnect, style: Theme.of(context).textTheme.titleLarge)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _healthAuthorized == true ? Icons.verified_user : Icons.report_gmailerrorred,
                          color: _healthAuthorized == true ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _healthAuthorized == null
                                ? s.hcUnknown
                                : (_healthAuthorized == true ? s.hcAuthorized : s.hcNotAuthorized),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_hcSdkStatus != null)
                      Text('HC SDK: ${_hcSdkStatus}', style: Theme.of(context).textTheme.bodySmall),
                    if (_healthLastError != null) ...[
                      const SizedBox(height: 6),
                      Text('${s.lastError}: $_healthLastError', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _checkHealthStatus,
                          icon: const Icon(Icons.refresh),
                          label: Text(s.checkStatus),
                        ),
                        FilledButton.icon(
                          onPressed: _requestHealthPermissions,
                          icon: const Icon(Icons.lock_open),
                          label: Text(s.grantPermissions),
                        ),
                        if (_hcSdkStatus == HealthConnectSdkStatus.sdkUnavailable || _hcSdkStatus == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired)
                          FilledButton.icon(
                            onPressed: () async { try { await _health.installHealthConnect(); } catch (e) { if (mounted) setState(() => _healthLastError = e.toString()); } },
                            icon: const Icon(Icons.download_rounded),
                            label: Text(_hcSdkStatus == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired ? (s.updateHc) : (s.installHc)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _todayCarbs() {
    final today = DateTime.now();
    final dToday = DateTime(today.year, today.month, today.day);
    int sum = 0;
    for (final item in _history) {
      final t = (item['time'] as DateTime);
      final d = DateTime(t.year, t.month, t.day);
      if (d == dToday && item['carbs'] is int) sum += item['carbs'] as int;
    }
    return sum;
  }

  void _showMealDetails(Map<String, dynamic> meal) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, controller) => SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (meal['name'] as String?)?.isNotEmpty == true ? meal['name'] : (meal['isGroup'] == true ? S.of(context).meal : S.of(context).mealDetails),
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Builder(builder: (ctx) {
                      final dt = _asDateTime(meal['time']);
                      if (dt == null) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _formatTimeShort(dt),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 12),
                if (meal['image'] != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(meal['image'].path), height: 220, fit: BoxFit.cover),
                  ),
                const SizedBox(height: 8),
                if (meal['description'] != null)
                  Text(meal['description'], style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _FormattedResultCard(resultText: meal['result'] ?? ''),
                if (meal['isGroup'] == true && meal['children'] is List) ...[
                  const SizedBox(height: 8),
                  StatefulBuilder(builder: (localCtx, setLocal) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(S.of(context).itemsInMeal((meal['children'] as List).length), style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        ...((meal['children'] as List).cast<Map<String, dynamic>>()).map((child) {
                          final name = child['name'] ?? child['description'] ?? S.of(context).noDescription;
                          final kcal = child['kcal'] as int?;
                          final dt = _asDateTime(child['time']);
                          String? subtitle;
                          if (dt != null && kcal != null) {
                            subtitle = '${_formatTimeShort(dt)} • ${kcal} ${S.of(context).kcalSuffix}';
                          } else if (dt != null) {
                            subtitle = _formatTimeShort(dt);
                          } else if (kcal != null) {
                            subtitle = '${kcal} ${S.of(context).kcalSuffix}';
                          }
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.fastfood),
                            title: Text(name),
                            subtitle: subtitle != null ? Text(subtitle) : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: S.of(context).remove,
                              onPressed: () async {
                                setState(() {
                                  (meal['children'] as List).remove(child);
                                  final restored = Map<String, dynamic>.from(child);
                                  restored.remove('isGroup');
                                  restored.remove('children');
                                  restored['time'] = (restored['time'] is DateTime || restored['time'] is String)
                                      ? restored['time']
                                      : DateTime.now();
                                  _history.add(restored);
                                  _recomputeGroupSums(meal);
                                });
                                setLocal(() {});
                                await _saveHistory();
                                if ((meal['children'] as List).isEmpty && context.mounted) {
                                  final idx = _history.indexOf(meal);
                                  if (idx >= 0) {
                                    setState(() {
                                      _history.removeAt(idx);
                                      if (identical(_pendingMealGroup, meal)) _pendingMealGroup = null;
                                    });
                                    await _saveHistory();
                                  }
                                  Navigator.pop(ctx);
                                }
                              },
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      _ungroupMeal(meal);
                      await _saveHistory();
                      if (context.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.call_split),
                    label: Text(S.of(context).ungroup),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (meal['kcal'] != null)
                      _Pill(icon: Icons.local_fire_department, label: "${meal['kcal']} ${S.of(context).kcalSuffix}", color: Colors.redAccent),
                    if (meal['carbs'] != null)
                      _Pill(
                        icon: Icons.grain,
                        label: "${meal['carbs']} ${S.of(context).carbsSuffix}",
                        color: Theme.of(context).brightness == Brightness.light ? Colors.orange : Colors.amber,
                      ),
                    if (meal['protein'] != null)
                      _Pill(icon: Icons.egg_alt, label: "${meal['protein']} ${S.of(context).proteinSuffix}", color: Colors.teal),
                    if (meal['fat'] != null)
                      _Pill(icon: Icons.blur_on, label: "${meal['fat']} ${S.of(context).fatSuffix}", color: Colors.purple),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          setState(() {
                            if (meal['isGroup'] == true) {
                              _pendingMealGroup = meal;
                            } else {
                              _startMealGroupWith(meal);
                            }
                          });
                          await _saveHistory();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).mealBuilderActive)));
                            Navigator.pop(ctx);
                            _tabController.animateTo(1); // Go to Main tab to add more
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_circle_outline),
                            const SizedBox(height: 6),
                            Text(S.of(context).addAnother, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final updated = await showDialog<Map<String, dynamic>>(
                            context: context,
                            builder: (dCtx) {
                              final nameCtrl = TextEditingController(text: meal['name']?.toString() ?? '');
                              final kcalCtrl = TextEditingController(text: meal['kcal']?.toString() ?? '');
                              final carbsCtrl = TextEditingController(text: meal['carbs']?.toString() ?? '');
                              final proteinCtrl = TextEditingController(text: meal['protein']?.toString() ?? '');
                              final fatCtrl = TextEditingController(text: meal['fat']?.toString() ?? '');
                              // Prefill grams with AI-provided value or, for groups, the combined sum of children
                              int? defaultG = meal['grams'] as int?;
                              if (defaultG == null && meal['isGroup'] == true && meal['children'] is List) {
                                int sum = 0;
                                int count = 0;
                                for (final c in (meal['children'] as List)) {
                                  if (c is Map && c['grams'] is int) { sum += c['grams'] as int; count++; }
                                }
                                if (count > 0 && sum > 0) defaultG = sum;
                              }
                              final gramsCtrl = TextEditingController(text: defaultG?.toString() ?? '');
                              bool linkValues = true;
                              final oldK = meal['kcal'] as int?;
                              final oldC = meal['carbs'] as int?;
                              final oldP = meal['protein'] as int?;
                              final oldF = meal['fat'] as int?;
                              // Use the AI/default grams or combined group grams as baseline when linking
                              final int? oldG = defaultG;
                              return StatefulBuilder(
                                builder: (context, setSB) => AlertDialog(
                                  title: Text(S.of(context).editMeal),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextField(controller: nameCtrl, decoration: InputDecoration(labelText: S.of(context).name)),
                                        const SizedBox(height: 8),
                                        TextField(controller: gramsCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.of(context).weightLabel)),
                                        CheckboxListTile(
                                          contentPadding: EdgeInsets.zero,
                                          value: linkValues,
                                          onChanged: (v) => setSB(() => linkValues = v ?? true),
                                          title: Text(S.of(context).linkValues),
                                        ),
                                        TextField(controller: kcalCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.of(context).kcalLabel)),
                                        const SizedBox(height: 8),
                                        TextField(controller: carbsCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.of(context).carbsLabel)),
                                        const SizedBox(height: 8),
                                        TextField(controller: proteinCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.of(context).proteinLabel)),
                                        const SizedBox(height: 8),
                                        TextField(controller: fatCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.of(context).fatLabel)),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        setSB(() {
                                          nameCtrl.text = meal['name']?.toString() ?? '';
                                          gramsCtrl.text = (defaultG?.toString() ?? '');
                                          kcalCtrl.text = (meal['kcal']?.toString() ?? '');
                                          carbsCtrl.text = (meal['carbs']?.toString() ?? '');
                                          proteinCtrl.text = (meal['protein']?.toString() ?? '');
                                          fatCtrl.text = (meal['fat']?.toString() ?? '');
                                        });
                                      },
                                      child: Text(S.of(context).restoreDefaults),
                                    ),
                                    TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(S.of(context).cancel)),
                                    FilledButton(
                                      onPressed: () {
                                        int? newG = int.tryParse(gramsCtrl.text.trim());
                                        int? newK = int.tryParse(kcalCtrl.text.trim());
                                        int? newC = int.tryParse(carbsCtrl.text.trim());
                                        int? newP = int.tryParse(proteinCtrl.text.trim());
                                        int? newF = int.tryParse(fatCtrl.text.trim());
                                        if (linkValues) {
                                          double? factor;
                                          if (oldC != null && newC != null && oldC > 0 && newC != oldC) {
                                            factor = newC / oldC;
                                          } else if (oldP != null && newP != null && oldP > 0 && newP != oldP) {
                                            factor = newP / oldP;
                                          } else if (oldF != null && newF != null && oldF > 0 && newF != oldF) {
                                            factor = newF / oldF;
                                          } else if (oldK != null && newK != null && oldK > 0 && newK != oldK) {
                                            factor = newK / oldK;
                                          } else if (newG != null && oldG != null && oldG > 0 && newG != oldG) {
                                            factor = newG / oldG;
                                          }
                                          if (factor != null) {
                                            if ((newG == null || newG == oldG) && oldG != null) newG = (oldG * factor).round();
                                            if (newK == null || newK == oldK) newK = oldK != null ? (oldK * factor).round() : null;
                                            if (newC == null || newC == oldC) newC = oldC != null ? (oldC * factor).round() : null;
                                            if (newP == null || newP == oldP) newP = oldP != null ? (oldP * factor).round() : null;
                                            if (newF == null || newF == oldF) newF = oldF != null ? (oldF * factor).round() : null;
                                          }
                                        }
                                        Navigator.pop(dCtx, {
                                          'name': nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                                          'grams': newG,
                                          'kcal': newK,
                                          'carbs': newC,
                                          'protein': newP,
                                          'fat': newF,
                                        });
                                      },
                                      child: Text(S.of(context).save),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                          if (updated != null) {
                            setState(() {
                              meal['name'] = updated['name'] ?? meal['name'];
                              meal['grams'] = updated['grams'] ?? meal['grams'];
                              meal['kcal'] = updated['kcal'] ?? meal['kcal'];
                              meal['carbs'] = updated['carbs'] ?? meal['carbs'];
                              meal['protein'] = updated['protein'] ?? meal['protein'];
                              meal['fat'] = updated['fat'] ?? meal['fat'];
                            });
                            await _saveHistory();
                            if (context.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).mealUpdated)));
                            }
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.edit_outlined),
                            const SizedBox(height: 6),
                            Text(S.of(context).editMeal, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (dCtx) => AlertDialog(
                              title: Text(S.of(context).deleteItem),
                              content: Text(S.of(context).deleteConfirm),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(S.of(context).cancel)),
                                FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: Text(S.of(context).delete)),
                              ],
                            ),
                          );
                          if (ok == true) {
                            try {
                              await _ensureHealthConfigured();
                              if (!kIsWeb && Platform.isAndroid && (meal['hcWritten'] == true)) {
                                final hs = meal['hcStart'];
                                final he = meal['hcEnd'];
                                final start = hs is DateTime ? hs : (hs is String ? DateTime.tryParse(hs) : null);
                                final end = he is DateTime ? he : (he is String ? DateTime.tryParse(he) : null);
                                if (start != null && end != null) {
                                  await _health.requestAuthorization([HealthDataType.NUTRITION], permissions: [HealthDataAccess.READ_WRITE]);
                                  await _health.delete(type: HealthDataType.NUTRITION, startTime: start, endTime: end);
                                }
                              }
                            } catch (_) {}
                            setState(() {
                              _history.remove(meal);
                            });
                            await _saveHistory();
                            if (context.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).delete)));
                            }
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.delete_outline),
                            const SizedBox(height: 6),
                            Text(S.of(context).delete, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- Manual add & meal grouping helpers ----
  Future<void> _addManualFood() async {
    final s = S.of(context);
    final nameCtrl = TextEditingController();
    final kcalCtrl = TextEditingController();
    final carbsCtrl = TextEditingController();
    final proteinCtrl = TextEditingController();
    final fatCtrl = TextEditingController();
    final gramsCtrl = TextEditingController();
    bool linkValues = true; // reserved for future scaling on edit
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (context, setSB) => AlertDialog(
          title: Text(s.addManual),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: InputDecoration(labelText: s.name)),
                const SizedBox(height: 8),
                TextField(controller: gramsCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.weightLabel)),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: linkValues,
                  onChanged: (v) => setSB(() => linkValues = v ?? true),
                  title: Text(s.linkValues),
                ),
                TextField(controller: kcalCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.kcalLabel)),
                const SizedBox(height: 8),
                TextField(controller: carbsCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.carbsLabel)),
                const SizedBox(height: 8),
                TextField(controller: proteinCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.proteinLabel)),
                const SizedBox(height: 8),
                TextField(controller: fatCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.fatLabel)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(s.cancel)),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) {
                  Navigator.pop(dCtx);
                  return;
                }
                Navigator.pop(dCtx, {
                  'name': nameCtrl.text.trim(),
                  'grams': int.tryParse(gramsCtrl.text.trim()),
                  'kcal': int.tryParse(kcalCtrl.text.trim()),
                  'carbs': int.tryParse(carbsCtrl.text.trim()),
                  'protein': int.tryParse(proteinCtrl.text.trim()),
                  'fat': int.tryParse(fatCtrl.text.trim()),
                });
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
    if (data == null) return;
    final localizedStructured = _localizedStructured({
      'Name': data['name'] ?? '-',
      'Calories': data['kcal'] != null ? '${data['kcal']} kcal' : '-',
      'Carbs': data['carbs'] != null ? '${data['carbs']} g' : '-',
      'Proteins': data['protein'] != null ? '${data['protein']} g' : '-',
      'Fats': data['fat'] != null ? '${data['fat']} g' : '-',
  if (data['grams'] != null) 'Weight (g)': '${data['grams']} g',
    });
    final newMeal = {
      'image': null,
      'imagePath': null,
  'description': data['name'] ?? S.of(context).packagedFood,
      'name': data['name'],
      'result': const JsonEncoder.withIndent('  ').convert(localizedStructured),
      'structured': localizedStructured,
      'grams': data['grams'],
      'kcal': data['kcal'],
      'carbs': data['carbs'],
      'protein': data['protein'],
      'fat': data['fat'],
      'time': DateTime.now(),
      'hcWritten': false,
    };
    setState(() {
      _history.add(newMeal);
      _pruneHistory();
    });
    await _saveHistory();
    // If building a meal, append inside current group
    if (_pendingMealGroup != null) {
      _appendToGroup(_pendingMealGroup!, newMeal);
      await _saveHistory();
    }
    if (!mounted) return;
    _tabController.animateTo(0);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _showMealDetails(newMeal);
    });
    _maybeOfferAddAnother(newMeal);
  }

  void _maybeOfferAddAnother(Map<String, dynamic> newMeal) {
    final s = S.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.addAnotherQ, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (_pendingMealGroup == null) {
                    _startMealGroupWith(newMeal);
                  } else {
                    _appendToGroup(_pendingMealGroup!, newMeal);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(s.mealStarted),
                      action: SnackBarAction(label: s.finishMeal, onPressed: _finishPendingMeal),
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: Text(s.addAnother),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.notNow)),
            ],
          ),
        ),
      ),
    );
  }

  void _startMealGroupWith(Map<String, dynamic> first) {
    final idx = _history.indexOf(first);
    if (idx < 0) return;
    final group = <String, dynamic>{
      'isGroup': true,
      'name': S.of(context).meal,
      'time': first['time'],
      'children': [first],
      'image': first['image'],
      'imagePath': first['imagePath'],
      'hcWritten': false,
    };
    _recomputeGroupSums(group);
    setState(() {
      _history[idx] = group;
      _pendingMealGroup = group;
    });
    // ignore: discarded_futures
    _saveHistory();
  }

  void _appendToGroup(Map<String, dynamic> group, Map<String, dynamic> item) {
    setState(() {
      _history.remove(item);
      (group['children'] as List).add(item);
      _recomputeGroupSums(group);
    });
    // ignore: discarded_futures
    _saveHistory();
  }

  void _recomputeGroupSums(Map<String, dynamic> group) {
    int sumK = 0, sumC = 0, sumP = 0, sumF = 0;
    bool hasK = false, hasC = false, hasP = false, hasF = false;
    if (group['children'] is List) {
      for (final e in (group['children'] as List).cast<Map>()) {
        final k = e['kcal'];
        final c = e['carbs'];
        final p = e['protein'];
        final f = e['fat'];
        if (k is int) { sumK += k; hasK = true; }
        if (c is int) { sumC += c; hasC = true; }
        if (p is int) { sumP += p; hasP = true; }
        if (f is int) { sumF += f; hasF = true; }
      }
    }
    group['kcal'] = hasK ? sumK : null;
    group['carbs'] = hasC ? sumC : null;
    group['protein'] = hasP ? sumP : null;
    group['fat'] = hasF ? sumF : null;
    group['result'] = S.of(context).groupSummary(sumK, sumC, sumP, sumF);
  }

  void _finishPendingMeal() {
    setState(() => _pendingMealGroup = null);
  }

  // --- Formatting helpers ---
  DateTime? _asDateTime(dynamic t) {
    if (t is DateTime) return t;
    if (t is String) return DateTime.tryParse(t);
    return null;
  }

  String _formatTimeShort(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // Normalize keys in a structured nutrition map to the current locale so UI shows consistent labels
  Map<String, dynamic> _localizedStructured(Map<String, dynamic> raw) {
    final code = S.of(context).locale.languageCode;
    String mapKey(String key) {
      if (code == 'fr') {
        switch (key) {
          case 'Name':
            return "Nom de l'aliment";
          case 'Carbs':
            return 'Glucides';
          case 'Proteins':
            return 'Proteines';
          case 'Fats':
            return 'Lipides';
          case 'Weight':
          case 'Weight (g)':
          case 'Weight(g)':
            return 'Poids (g)';
        }
      } else {
        switch (key) {
          case "Nom de l'aliment":
            return 'Name';
          case 'Glucides':
            return 'Carbs';
          case 'Proteines':
          case 'Protéines':
            return 'Proteins';
          case 'Lipides':
            return 'Fats';
          case 'Poids':
          case 'Poids (g)':
            return 'Weight (g)';
        }
      }
      return key;
    }

    Map<String, dynamic> walk(Map<String, dynamic> m) {
      final out = <String, dynamic>{};
      m.forEach((key, value) {
        final nk = mapKey(key);
        if (value is Map<String, dynamic>) {
          out[nk] = walk(value);
        } else if (value is Map) {
          out[nk] = walk(Map<String, dynamic>.from(value));
        } else if (value is List) {
      out[nk] = value
        .map((e) => e is Map ? walk(Map<String, dynamic>.from(e)) : e)
        .toList();
        } else {
          out[nk] = value;
        }
      });
      return out;
    }

    return walk(raw);
  }

  void _ungroupMeal(Map<String, dynamic> group) {
    if (group['isGroup'] == true && group['children'] is List) {
      final idx = _history.indexOf(group);
      if (idx >= 0) {
        setState(() {
          _history.removeAt(idx);
          final kids = (group['children'] as List).cast<Map<String, dynamic>>();
          _history.insertAll(idx, kids);
          if (identical(_pendingMealGroup, group)) _pendingMealGroup = null;
        });
      }
    }
  }

  void _mergeMeals(Map<String, dynamic> source, Map<String, dynamic> target) async {
    if (identical(source, target)) return;
    final tIdx = _history.indexOf(target);
    final sIdx = _history.indexOf(source);
    if (tIdx < 0 || sIdx < 0) return;
    setState(() {
      if (target['isGroup'] == true) {
        final List kids = target['children'] as List? ?? [];
        if (source['isGroup'] == true) {
          kids.addAll((source['children'] as List?) ?? const []);
        } else {
          kids.add(source);
        }
        target['children'] = kids;
        _recomputeGroupSums(target);
        _history.removeAt(sIdx);
      } else {
        final group = <String, dynamic>{
          'isGroup': true,
          'name': S.of(context).meal,
          'time': target['time'],
          'children': source['isGroup'] == true ? [target, ...(source['children'] as List? ?? const [])] : [target, source],
          'image': target['image'],
          'imagePath': target['imagePath'],
          'hcWritten': false,
        };
        _recomputeGroupSums(group);
        final keepIdx = _history.indexOf(target);
        _history[keepIdx] = group;
        final rmIdx = _history.indexOf(source);
        if (rmIdx >= 0) _history.removeAt(rmIdx);
      }
    });
    await _saveHistory();
  }

}

class _BarcodeScannerScreen extends StatefulWidget {
  const _BarcodeScannerScreen();

  @override
  State<_BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<_BarcodeScannerScreen> {
  bool _locked = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).scanBarcodeTitle)),
      body: MobileScanner(
        onDetect: (capture) {
          if (_locked) return;
          final barcodes = capture.barcodes;
          if (barcodes.isEmpty) return;
          final value = barcodes.first.rawValue;
          if (value != null && value.isNotEmpty) {
            _locked = true;
            Navigator.pop(context, value);
          }
        },
      ),
    );
  }
}

class _OffProduct {
  final String? name;
  final int? servingSizeGrams; // parsed from serving_size when possible
  final int? packageSizeGrams; // parsed from quantity (full package)
  final double? kcalPer100g;
  final double? carbsPer100g;
  final double? proteinPer100g;
  final double? fatPer100g;

  _OffProduct({this.name, this.servingSizeGrams, this.packageSizeGrams, this.kcalPer100g, this.carbsPer100g, this.proteinPer100g, this.fatPer100g});

  static _OffProduct? fromJson(Map<String, dynamic> p) {
    String? name = (p['product_name'] ?? p['generic_name']) as String?;
    final nutriments = p['nutriments'] as Map<String, dynamic>?;
    double? kcal100, carbs100, protein100, fat100;
    if (nutriments != null) {
      kcal100 = _toDouble(nutriments['energy-kcal_100g'] ?? nutriments['energy_100g']);
      carbs100 = _toDouble(nutriments['carbohydrates_100g']);
      protein100 = _toDouble(nutriments['proteins_100g']);
      fat100 = _toDouble(nutriments['fat_100g']);
    }
    int? servingSizeGrams;
    int? packageSizeGrams;
    final ss = p['serving_size'] as String?;
    if (ss != null) {
      final m = RegExp(r'(\d{1,4})\s*(g|ml)', caseSensitive: false).firstMatch(ss);
      if (m != null) {
        servingSizeGrams = int.tryParse(m.group(1)!);
      }
    }
    final qty = p['quantity'] as String?; // e.g., "330 ml" or "500 g"
    if (qty != null) {
      final m = RegExp(r'(\d{1,5})\s*(g|ml)', caseSensitive: false).firstMatch(qty);
      if (m != null) {
        packageSizeGrams = int.tryParse(m.group(1)!);
      }
    }
    return _OffProduct(
      name: name,
      servingSizeGrams: servingSizeGrams,
      packageSizeGrams: packageSizeGrams,
      kcalPer100g: kcal100,
      carbsPer100g: carbs100,
      proteinPer100g: protein100,
      fatPer100g: fat100,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  _ScaledNutrients scaleFor(int? grams) {
    if (grams == null || grams <= 0) {
      // fallback to full package if provided, else serving size, else assume 100g
      final g = packageSizeGrams ?? servingSizeGrams ?? 100;
      return _ScaledNutrients(
        kcal: kcalPer100g != null ? kcalPer100g! * g / 100.0 : null,
        carbs: carbsPer100g != null ? carbsPer100g! * g / 100.0 : null,
        protein: proteinPer100g != null ? proteinPer100g! * g / 100.0 : null,
        fat: fatPer100g != null ? fatPer100g! * g / 100.0 : null,
      );
    }
    return _ScaledNutrients(
      kcal: kcalPer100g != null ? kcalPer100g! * grams / 100.0 : null,
      carbs: carbsPer100g != null ? carbsPer100g! * grams / 100.0 : null,
      protein: proteinPer100g != null ? proteinPer100g! * grams / 100.0 : null,
      fat: fatPer100g != null ? fatPer100g! * grams / 100.0 : null,
    );
  }

  String prettyDescription(int? grams) {
    final parts = <String>[];
    if (name != null) parts.add(name!);
    if (grams != null && grams > 0) parts.add('~${grams}g');
    return parts.isEmpty ? 'Packaged food' : parts.join(' ');
  }
}

class _ScaledNutrients {
  final double? kcal;
  final double? carbs;
  final double? protein;
  final double? fat;
  _ScaledNutrients({this.kcal, this.carbs, this.protein, this.fat});
}


 

class _FormattedResultCard extends StatelessWidget {
  final String resultText;
  const _FormattedResultCard({required this.resultText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Map<String, dynamic>? jsonMap;
    try {
      final decoded = json.decode(resultText);
      if (decoded is Map<String, dynamic>) jsonMap = decoded;
    } catch (_) {}

    Widget content;
    if (jsonMap != null) {
      final entries = jsonMap.entries.toList();
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(e.key, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSecondaryContainer)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.value is Map || e.value is List
                          ? const JsonEncoder.withIndent('  ').convert(e.value)
                          : e.value.toString(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    } else {
      // Try to parse simple key: value lines
      final lines = resultText.trim().split('\n');
      final kvRegex = RegExp(r'^\s*([^:]{2,})\s*:\s*(.+)$');
      final kvs = <MapEntry<String, String>>[];
      for (final l in lines) {
        final m = kvRegex.firstMatch(l);
        if (m != null) kvs.add(MapEntry(m.group(1)!, m.group(2)!));
      }
      if (kvs.isNotEmpty) {
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in kvs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(e.key, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onTertiaryContainer)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.value)),
                  ],
                ),
              ),
          ],
        );
      } else {
        content = Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(resultText, style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')),
        );
      }
    }

    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          title: Row(
            children: [
              Expanded(child: Text(S.of(context).result, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: S.of(context).copy,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: resultText));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).copied)));
                },
                icon: const Icon(Icons.copy_all_outlined),
              ),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandableDaySection extends StatefulWidget {
  final String title;
  final int totalKcal;
  final int? totalCarbs;
  final int? totalProtein;
  final int? totalFat;
  final List<Widget> children;
  const _ExpandableDaySection({
    required this.title,
    required this.totalKcal,
    this.totalCarbs,
    this.totalProtein,
    this.totalFat,
    required this.children,
  });

  @override
  State<_ExpandableDaySection> createState() => _ExpandableDaySectionState();
}

class _ExpandableDaySectionState extends State<_ExpandableDaySection> {
  bool _expanded = true;
  @override
  Widget build(BuildContext context) {
  // final scheme = Theme.of(context).colorScheme;
    final s = S.of(context);
    final kcal = widget.totalKcal;
    final color = kcal < 1400
        ? Colors.green
        : (kcal < 2000 ? Colors.orange : Colors.red);
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          title: Text(
            widget.title,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Icon(Icons.local_fire_department, size: 16, color: color),
                    const SizedBox(width: 6),
                    Text('$kcal ${s.kcalSuffix}', style: TextStyle(color: color)),
                  ]),
                ),
                if (widget.totalCarbs != null)
                  Builder(builder: (ctx) {
                    final c = _carbsColor(ctx);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        Icon(Icons.grain, size: 16, color: c),
                        const SizedBox(width: 6),
                        Text('${widget.totalCarbs} ${s.carbsSuffix}', style: TextStyle(color: c)),
                      ]),
                    );
                  }),
                if (widget.totalProtein != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.teal.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.egg_alt, size: 16, color: Colors.teal),
                      const SizedBox(width: 6),
                      Text('${widget.totalProtein} ${s.proteinSuffix}', style: const TextStyle(color: Colors.teal)),
                    ]),
                  ),
                if (widget.totalFat != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.purple.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.blur_on, size: 16, color: Colors.purple),
                      const SizedBox(width: 6),
                      Text('${widget.totalFat} ${s.fatSuffix}', style: const TextStyle(color: Colors.purple)),
                    ]),
                  ),
              ],
            ),
          ),
          children: widget.children,
        ),
      ),
    );
  }
}

class _HistoryMealCard extends StatelessWidget {
  final Map<String, dynamic> meal;
  final VoidCallback onDelete;
  final VoidCallback? onTap;
  final void Function(Map<String, dynamic> source)? onDrop;
  const _HistoryMealCard({required this.meal, required this.onDelete, this.onTap, this.onDrop});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = S.of(context);
    final kcal = meal['kcal'] as int?;
    final kcalColor = kcal == null
        ? scheme.onSurfaceVariant
        : (kcal < 700 ? Colors.green : (kcal < 1000 ? Colors.orange : Colors.red));
    final carbs = meal['carbs'] as int?;
    final protein = meal['protein'] as int?;
    final fat = meal['fat'] as int?;

    final Widget cardContent = Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meal['image'] != null || (meal['imagePath'] is String && (meal['imagePath'] as String).isNotEmpty))
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(meal['image'] != null ? meal['image'].path : (meal['imagePath'] as String)),
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.fastfood, color: scheme.onSurfaceVariant),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        meal['name'] ?? meal['description'] ?? s.noDescription,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Builder(builder: (ctx) {
                      final dt = context.findAncestorStateOfType<_MainScreenState>()?._asDateTime(meal['time']);
                      return dt == null
                          ? const SizedBox.shrink()
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                context.findAncestorStateOfType<_MainScreenState>()!._formatTimeShort(dt),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            );
                    }),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (kcal != null)
                      _Pill(
                        icon: Icons.local_fire_department,
                        label: '$kcal ${s.kcalSuffix}',
                        color: kcalColor,
                      ),
                    if (carbs != null) const SizedBox(height: 4),
                    if (carbs != null)
                      _Pill(
                        icon: Icons.grain,
                        label: '$carbs ${s.carbsSuffix}',
                        color: _carbsColor(context),
                      ),
                    if (protein != null)
                      _Pill(
                        icon: Icons.egg_alt,
                        label: '$protein ${s.proteinSuffix}',
                        color: Colors.teal,
                      ),
                    if (fat != null)
                      _Pill(
                        icon: Icons.blur_on,
                        label: '$fat ${s.fatSuffix}',
                        color: Colors.purple,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (val) async {
              if (val == 'edit') {
                final updated = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (ctx) {
                    final nameCtrl = TextEditingController(text: meal['name']?.toString() ?? '');
                    final kcalCtrl = TextEditingController(text: meal['kcal']?.toString() ?? '');
                    final carbsCtrl = TextEditingController(text: meal['carbs']?.toString() ?? '');
                    final proteinCtrl = TextEditingController(text: meal['protein']?.toString() ?? '');
                    final fatCtrl = TextEditingController(text: meal['fat']?.toString() ?? '');
                    // Prefill grams with AI-provided value or, for groups, the combined sum of children
                    int? defaultG = meal['grams'] as int?;
                    if (defaultG == null && meal['isGroup'] == true && meal['children'] is List) {
                      int sum = 0;
                      int count = 0;
                      for (final c in (meal['children'] as List)) {
                        if (c is Map && c['grams'] is int) { sum += c['grams'] as int; count++; }
                      }
                      if (count > 0 && sum > 0) defaultG = sum;
                    }
                    final gramsCtrl = TextEditingController(text: (defaultG?.toString() ?? ''));
                    bool linkValues = true;
                    final oldK = meal['kcal'] as int?;
                    final oldC = meal['carbs'] as int?;
                    final oldP = meal['protein'] as int?;
                    final oldF = meal['fat'] as int?;
                    // Use AI/default grams or combined group grams as baseline when linking
                    final int? oldG = defaultG;
                    return StatefulBuilder(
                      builder: (context, setSB) => AlertDialog(
                        title: Text(S.of(context).editMeal),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(controller: nameCtrl, decoration: InputDecoration(labelText: S.of(context).name)),
                              const SizedBox(height: 8),
                              TextField(controller: gramsCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.of(context).weightLabel)),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: linkValues,
                                onChanged: (v) => setSB(() => linkValues = v ?? true),
                                title: Text(S.of(context).linkValues),
                              ),
                              TextField(controller: kcalCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.of(context).kcalLabel)),
                              const SizedBox(height: 8),
                              TextField(controller: carbsCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.of(context).carbsLabel)),
                              const SizedBox(height: 8),
                              TextField(controller: proteinCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.of(context).proteinLabel)),
                              const SizedBox(height: 8),
                              TextField(controller: fatCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.of(context).fatLabel)),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              setSB(() {
                                nameCtrl.text = meal['name']?.toString() ?? '';
                                gramsCtrl.text = (defaultG?.toString() ?? '');
                                kcalCtrl.text = (meal['kcal']?.toString() ?? '');
                                carbsCtrl.text = (meal['carbs']?.toString() ?? '');
                                proteinCtrl.text = (meal['protein']?.toString() ?? '');
                                fatCtrl.text = (meal['fat']?.toString() ?? '');
                              });
                            },
                            child: Text(S.of(context).restoreDefaults),
                          ),
                          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(context).cancel)),
                          FilledButton(
                            onPressed: () {
                              int? newG = int.tryParse(gramsCtrl.text.trim());
                              int? newK = int.tryParse(kcalCtrl.text.trim());
                              int? newC = int.tryParse(carbsCtrl.text.trim());
                              int? newP = int.tryParse(proteinCtrl.text.trim());
                              int? newF = int.tryParse(fatCtrl.text.trim());
                              if (linkValues) {
                                double? factor;
                                if (oldC != null && newC != null && oldC > 0 && newC != oldC) {
                                  factor = newC / oldC;
                                } else if (oldP != null && newP != null && oldP > 0 && newP != oldP) {
                                  factor = newP / oldP;
                                } else if (oldF != null && newF != null && oldF > 0 && newF != oldF) {
                                  factor = newF / oldF;
                                } else if (oldK != null && newK != null && oldK > 0 && newK != oldK) {
                                  factor = newK / oldK;
                                } else if (newG != null && oldG != null && oldG > 0 && newG != oldG) {
                                  factor = newG / oldG;
                                }
                                if (factor != null) {
                                  if ((newG == null || newG == oldG) && oldG != null) newG = (oldG * factor).round();
                                  if (newK == null || newK == oldK) newK = oldK != null ? (oldK * factor).round() : null;
                                  if (newC == null || newC == oldC) newC = oldC != null ? (oldC * factor).round() : null;
                                  if (newP == null || newP == oldP) newP = oldP != null ? (oldP * factor).round() : null;
                                  if (newF == null || newF == oldF) newF = oldF != null ? (oldF * factor).round() : null;
                                }
                              }
                              Navigator.pop(ctx, {
                                'name': nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                                'grams': newG,
                                'kcal': newK,
                                'carbs': newC,
                                'protein': newP,
                                'fat': newF,
                              });
                            },
                            child: Text(S.of(context).save),
                          ),
                        ],
                      ),
                    );
                  },
                );
                if (updated != null) {
                  meal['name'] = updated['name'] ?? meal['name'];
                  meal['grams'] = updated['grams'] ?? meal['grams'];
                  meal['kcal'] = updated['kcal'] ?? meal['kcal'];
                  meal['carbs'] = updated['carbs'] ?? meal['carbs'];
                  meal['protein'] = updated['protein'] ?? meal['protein'];
                  meal['fat'] = updated['fat'] ?? meal['fat'];
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).mealUpdated)));
                  final state = context.findAncestorStateOfType<_MainScreenState>();
                  await state?._saveHistory();
                }
              } else if (val == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(S.of(context).deleteItem),
                    content: Text(S.of(context).deleteConfirm),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.of(context).cancel)),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(S.of(context).delete)),
                    ],
                  ),
                );
                if (ok == true) onDelete();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'edit', child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(S.of(context).edit))),
              PopupMenuItem(value: 'delete', child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(S.of(context).delete))),
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: DragTarget<Map<String, dynamic>>(
        onWillAccept: (data) => data != null && !identical(data, meal),
        onAccept: (data) => onDrop?.call(data),
        builder: (context, candidates, rejected) {
          final highlight = candidates.isNotEmpty;
          return LongPressDraggable<Map<String, dynamic>>(
            data: meal,
            feedback: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Card(child: cardContent),
              ),
            ),
            child: Card(
              color: highlight ? Theme.of(context).colorScheme.secondaryContainer : null,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: cardContent,
              ),
            ),
          );
        },
      ),
    );
  }
}

Color _carbsColor(BuildContext context) {
  // In light mode, use a distinct blue for carbs; in dark mode keep amber for legibility.
  // If daltonian mode is enabled, use high-contrast teal.
  final isLight = Theme.of(context).brightness == Brightness.light;
  if (appSettings.daltonian) return Colors.teal;
  return isLight ? Colors.blue : Colors.amber;
}

class _ProgressBar extends StatelessWidget {
  final double value; // 0.0 .. 1.5
  final Color color;
  const _ProgressBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final capped = value.clamp(0.0, 1.0);
    final overflow = (value - 1.0).clamp(0.0, 0.5);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 18,
        color: scheme.surfaceContainerHighest,
        child: Stack(
          children: [
            FractionallySizedBox(
              widthFactor: capped,
              child: Container(color: color.withOpacity(0.85)),
            ),
            if (overflow > 0)
              Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: overflow,
                  alignment: Alignment.centerRight,
                  child: Container(color: Colors.red.shade900.withOpacity(0.7)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Pill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    // Cap the pill width and ellipsize text to avoid bleeding over the card edge on low-DPI screens
    final w = MediaQuery.of(context).size.width;
    final maxW = w < 360
        ? 110.0
        : w < 420
            ? 140.0
            : 180.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: color, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Minimal localization helper (English/French)
class S {
  final Locale locale;
  S(this.locale);

  static S of(BuildContext context) {
  final loc = appSettings.locale ?? Localizations.maybeLocaleOf(context) ?? const Locale('en');
    return S(loc);
  }

  String get _code => locale.languageCode;

  String get appTitle => _code == 'fr' ? 'Gestionnaire de repas' : 'Meal Manager';
  String get healthConnect => _code == 'fr' ? 'Health Connect' : 'Health Connect';
  String get hcUnknown => _code == 'fr' ? 'Statut inconnu' : 'Status unknown';
  String get hcAuthorized => _code == 'fr' ? 'Autorisé' : 'Authorized';
  String get hcNotAuthorized => _code == 'fr' ? 'Non autorisé' : 'Not authorized';
  String get lastError => _code == 'fr' ? 'Dernière erreur' : 'Last error';
  // Flash popup and error strings
  String get flashTitle => _code == 'fr' ? 'Utiliser le modèle flash ?' : 'Use flash model?';
  String get flashExplain => _code == 'fr'
      ? 'Cela va réessayer une fois avec un modèle plus rapide et moins précis (gemini-2.5-flash).'
      : 'This will retry once with a faster, less precise model (gemini-2.5-flash).';
  String get useFlash => _code == 'fr' ? 'Utiliser flash' : 'Use flash';
  String get aiOverloaded => _code == 'fr' ? 'L’IA est surchargée (503).' : 'AI is overloaded (503).';
  String requestFailedWithCode(int code) => _code == 'fr' ? 'Échec de la requête ($code)' : 'Request failed ($code)';
  String get checkStatus => _code == 'fr' ? 'Vérifier le statut' : 'Check status';
  String get grantPermissions => _code == 'fr' ? 'Autoriser' : 'Grant permissions';
  String get hcGranted => _code == 'fr' ? 'Autorisations accordées' : 'Permissions granted';
  String get hcDenied => _code == 'fr' ? 'Autorisations refusées' : 'Permissions denied';
  String get hcWriteOk => _code == 'fr' ? 'Enregistré dans Health Connect' : 'Saved to Health Connect';
  String get hcWriteFail => _code == 'fr' ? "Échec de l’enregistrement dans Health Connect" : 'Failed to write to Health Connect';
  String get installHc => _code == 'fr' ? 'Installer Health Connect' : 'Install Health Connect';
  String get updateHc => _code == 'fr' ? 'Mettre à jour Health Connect' : 'Update Health Connect';
  String get settings => _code == 'fr' ? 'Paramètres' : 'Settings';
  String get systemLanguage => _code == 'fr' ? 'Langue du système' : 'System language';
  String get daltonianMode => _code == 'fr' ? 'Mode daltonien' : 'Colorblind-friendly mode';
  String get daltonianModeHint => _code == 'fr' ? 'Améliore les contrastes et couleurs pour les daltoniens' : 'Improves contrasts and colors for color vision deficiencies';
  String get tabHistory => _code == 'fr' ? 'Historique' : 'History';
  String get tabMain => _code == 'fr' ? 'Principal' : 'Main';
  String get tabDaily => _code == 'fr' ? 'Quotidien' : 'Daily';

  String get describeMeal => _code == 'fr' ? 'Indiquez des précisions pour aider l\'IA' : 'Provide details to help the AI';
  String get describeMealHint => _code == 'fr' ? 'ex. poulet, riz, salade…' : 'e.g. chicken, rice, salad…';
  String get takePhoto => _code == 'fr' ? 'Prendre une photo' : 'Take Photo';
  String get pickImage => _code == 'fr' ? 'Choisir une image' : 'Pick Image';
  String get sendToAI => _code == 'fr' ? 'Envoyer à l’IA' : 'Send to AI';
  String get scanBarcode => _code == 'fr' ? 'Scanner code-barres' : 'Scan barcode';
  String get sending => _code == 'fr' ? 'Envoi…' : 'Sending…';
  String get provideMsgOrImage => _code == 'fr' ? 'Veuillez fournir un message ou une image.' : 'Please provide a message or an image.';
  String get cameraNotSupported => _code == 'fr' ? 'La capture photo n’est pas prise en charge sur cette plateforme. Utilisez Choisir une image.' : 'Camera capture not supported on this platform. Use Pick Image instead.';
  String get failedOpenCamera => _code == 'fr' ? 'Impossible d’ouvrir la caméra' : 'Failed to open camera';
  String get requestFailed => _code == 'fr' ? 'Échec de la requête' : 'Request failed';
  String get error => _code == 'fr' ? 'Erreur' : 'Error';
  String get noHistory => _code == 'fr' ? 'Aucun historique' : 'No history yet';
  String get noDescription => _code == 'fr' ? 'Sans description' : 'No description';
  String get weightLabel => _code == 'fr' ? 'Poids (g)' : 'Weight (g)';
  String get linkToWeight => _code == 'fr' ? 'Lier les valeurs au poids' : 'Link values to weight';
  String get linkValues => _code == 'fr' ? 'Lier toutes les valeurs ensemble' : 'Link all values together';

  String get dailyIntake => _code == 'fr' ? 'Apport quotidien' : 'Daily Intake';
  String get dailyLimit => _code == 'fr' ? 'Limite quotidienne' : 'Daily limit';
  String get today => _code == 'fr' ? 'Aujourd’hui' : 'Today';
  String get yesterday => _code == 'fr' ? 'Hier' : 'Yesterday';

  // Burned energy + net
  String get burnedTodayTitle => _code == 'fr' ? 'Calories brûlées aujourd’hui' : 'Calories burned today';
  String get refreshBurned => _code == 'fr' ? 'Rafraîchir' : 'Refresh';
  String get burnedLabel => _code == 'fr' ? 'Brûlées' : 'Burned';
  String get burnedNotAvailable => _code == 'fr' ? 'Données non disponibles (autorisez Health Connect)' : 'Data not available (grant Health permissions)';
  String get surplusLabel => _code == 'fr' ? 'Excédent' : 'Surplus';
  String get deficitLabel => _code == 'fr' ? 'Déficit' : 'Deficit';
  String get netKcalLabel => _code == 'fr' ? 'Net' : 'Net';
  String get totalLabel => _code == 'fr' ? 'Total' : 'Total';
  String get activeLabel => _code == 'fr' ? 'Actives' : 'Active';
  String get burnedHelp => _code == 'fr' ? 'Différence Total vs Actives' : 'Total vs Active difference';
  String get burnedHelpText => _code == 'fr'
      ? 'Total = Basal (métabolisme au repos) + Actives (activité). Actives n’inclut pas le métabolisme de base.'
      : 'Total = Basal (resting metabolic) + Active (activity). Active excludes resting metabolic energy.';
  String get ok => _code == 'fr' ? 'OK' : 'OK';

  String get result => _code == 'fr' ? 'Résultat' : 'Result';
  String get copy => _code == 'fr' ? 'Copier' : 'Copy';
  String get copied => _code == 'fr' ? 'Copié dans le presse‑papiers' : 'Copied to clipboard';
  String get debugRaw => _code == 'fr' ? 'Debug brut' : 'Debug raw';
  String get debugRawTitle => _code == 'fr' ? 'Réponse brute' : 'Raw response';
  String get emptyResponse => _code == 'fr' ? 'Réponse vide' : 'Empty response';

  String get mealDetails => _code == 'fr' ? 'Détails du repas' : 'Meal details';
  String get meal => _code == 'fr' ? 'Repas' : 'Meal';
  String get edit => _code == 'fr' ? 'Modifier' : 'Edit';
  String get editMeal => _code == 'fr' ? 'Modifier' : 'Edit'; // from Edit meal to Edit
  String get name => _code == 'fr' ? 'Nom' : 'Name';
  String get kcalLabel => 'Kcal';
  String get carbsLabel => _code == 'fr' ? 'Glucides (g)' : 'Carbs (g)';
  String get proteinLabel => _code == 'fr' ? 'Protéines (g)' : 'Protein (g)';
  String get fatLabel => _code == 'fr' ? 'Lipides (g)' : 'Fat (g)';
  String get cancel => _code == 'fr' ? 'Annuler' : 'Cancel';
  String get save => _code == 'fr' ? 'Enregistrer' : 'Save';
  String get deleteItem => _code == 'fr' ? 'Supprimer l’élément' : 'Delete item';
  String get deleteConfirm => _code == 'fr' ? 'Voulez-vous vraiment supprimer cette entrée ?' : 'Are you sure you want to delete this entry?';
  String get delete => _code == 'fr' ? 'Supprimer' : 'Delete';
  String get mealUpdated => _code == 'fr' ? 'Repas mis à jour' : 'Meal updated';
  String get addManual => _code == 'fr' ? 'Ajouter manuellement' : 'Add manually';
  String get mealBuilderActive => _code == 'fr' ? 'Construction d’un repas en cours' : 'Meal builder active';
  String get finishMeal => _code == 'fr' ? 'Terminer le repas' : 'Finish meal';
  String get restoreDefaults => _code == 'fr' ? 'Restaurer les valeurs par défaut' : 'Restore defaults';
  String get addAnotherQ => _code == 'fr' ? 'Ajouter un autre aliment à ce repas ?' : 'Add another item to this meal?';
  String get addAnother => _code == 'fr' ? 'Ajouter plus' : 'Add more';
  String get notNow => _code == 'fr' ? 'Pas maintenant' : 'Not now';
  String get mealStarted => _code == 'fr' ? 'Nouveau repas en cours. Ajoutez d’autres éléments.' : 'Meal started. Add more items.';
  String itemsInMeal(int n) => _code == 'fr' ? '$n éléments' : '$n items';
  String get remove => _code == 'fr' ? 'Retirer' : 'Remove';
  String get ungroup => _code == 'fr' ? 'Dissocier' : 'Ungroup';
  String groupSummary(int k, int c, int p, int f) => _code == 'fr'
      ? 'Total: ${k} kcal • ${c} g glucides • ${p} g protéines • ${f} g lipides'
      : 'Total: ${k} kcal • ${c} g carbs • ${p} g protein • ${f} g fat';

  // Units/suffixes
  String get kcalSuffix => 'kcal';
  String get carbsSuffix => _code == 'fr' ? 'g glucides' : 'g carbs';
  String get proteinSuffix => _code == 'fr' ? 'g protéines' : 'g protein';
  String get fatSuffix => _code == 'fr' ? 'g lipides' : 'g fat';
  String get packagedFood => _code == 'fr' ? 'Produit emballé' : 'Packaged food';

  // Info menu
  String get info => _code == 'fr' ? 'Infos' : 'Info';
  String get about => _code == 'fr' ? 'À propos' : 'About';
  String versionBuild(String v, String b) => _code == 'fr' ? 'Version $v ($b)' : 'Version $v ($b)';
  String get joinDiscord => _code == 'fr'
    ? 'Pour discuter avec nous ou obtenir de l’aide, rejoignez le Discord'
    : 'To discuss with us or for support, join the discord';
  String get openGithubIssue => _code == 'fr'
    ? 'Pour un problème ou une suggestion, ouvrez un ticket GitHub'
    : 'For issues or suggestions, please open a github issue';
  String get hideForever => _code == 'fr' ? 'Masquer cette annonce' : 'Hide this announcement';
  String get disableAnnouncements => _code == 'fr' ? 'Désactiver les annonces' : 'Disable announcements';
  String get disableAnnouncementsHint => _code == 'fr'
      ? 'Ne jamais afficher les messages d\'administration au démarrage'
      : 'Never show admin messages on startup';
  
  // Queue & notifications
  String get queueAndNotifications => _code == 'fr' ? 'File d\'attente et notifications' : 'Queue & notifications';
  String get backgroundQueue => _code == 'fr' ? 'File d\'attente en arrière-plan' : 'Background queue';
  String get noPendingJobs => _code == 'fr' ? 'Aucune tâche en attente' : 'No pending jobs';
  String get notifications => _code == 'fr' ? 'Notifications' : 'Notifications';
  String get noNotificationsYet => _code == 'fr' ? 'Aucune notification pour l\'instant' : 'No notifications yet';
  String get statusPending => _code == 'fr' ? 'en attente' : 'pending';
  String get statusError => _code == 'fr' ? 'erreur' : 'error';
  String get queueInBackground => _code == 'fr' ? 'Mettre en file d\'attente' : 'Queue in background';
  String get queueInBackgroundHint => _code == 'fr' ? 'Envoyer et continuer. Vous serez notifié quand c\'est prêt.' : 'Send and continue. Get notified when ready.';
  String queuedRequest(String id) => _code == 'fr' ? 'Requête mise en file d\'attente (#$id)' : 'Queued a request (#$id)';
  String get queuedWorking => _code == 'fr' ? 'En file d\'attente : traitement en arrière‑plan' : 'Queued: working in background';
  String get resultSaved => _code == 'fr' ? 'Résultat enregistré dans l\'historique' : 'Result saved to History';
  String get serviceUnavailable => _code == 'fr' ? 'Le service est indisponible, réessayez plus tard.' : 'Service is currently unavailable, please try again later.';

  // Barcode & quantity dialogs
  String get productNotFound => _code == 'fr' ? 'Produit non trouvé' : 'Product not found';
  String get quantityTitle => _code == 'fr' ? 'Quantité (g/ml)' : 'Quantity (g/ml)';
  String quantityHelpDefaultServing(int g) => _code == 'fr'
    ? 'Laissez vide pour la quantité par défaut (${g}g), ou entrez une quantité personnalisée.'
    : 'Leave empty for default quantity (${g}g), or enter a custom amount.';
  String get quantityHelpPackage => _code == 'fr'
    ? 'Laissez vide pour la quantité totale du paquet, ou entrez une quantité personnalisée.'
    : 'Leave empty for full package quantity, or enter a custom amount.';
  String get exampleNumber => _code == 'fr' ? 'Ex: 330' : 'e.g. 330';
  String get scanBarcodeTitle => _code == 'fr' ? 'Scanner le code‑barres' : 'Scan barcode';

  // Auth & account
  String get login => _code == 'fr' ? 'Connexion' : 'Login';
  String get username => _code == 'fr' ? 'Nom d\'utilisateur' : 'Username';
  String get password => _code == 'fr' ? 'Mot de passe' : 'Password';
  String get required => _code == 'fr' ? 'Obligatoire' : 'Required';
  String loginFailedCode(int c) => _code == 'fr' ? 'Échec de connexion ($c)' : 'Login failed ($c)';
  String get loginError => _code == 'fr' ? 'Erreur de connexion' : 'Login error';
  String get noTokenReceived => _code == 'fr' ? 'Aucun jeton reçu' : 'No token received';
  String get networkError => _code == 'fr' ? 'Erreur réseau' : 'Network error';
  String get betaSignup => _code == 'fr' ? 'Pour participer à la bêta, demandez l\'accès.' : 'To sign up for this beta, please request access';
  String get joinDiscordAction => _code == 'fr' ? 'Rejoindre le Discord' : 'Join our Discord';
  String get openDiscordFailed => _code == 'fr' ? 'Impossible d\'ouvrir Discord' : 'Could not open Discord';
  String get logout => _code == 'fr' ? 'Se déconnecter' : 'Log out';

  // Set password
  String get setPasswordTitle => _code == 'fr' ? 'Définir le mot de passe' : 'Set password';
  String get newPassword => _code == 'fr' ? 'Nouveau mot de passe' : 'New password';
  String get confirmPassword => _code == 'fr' ? 'Confirmer le mot de passe' : 'Confirm password';
  String get min6 => _code == 'fr' ? '6 caractères minimum' : 'Min 6 chars';
  String failedWithCode(int c) => _code == 'fr' ? 'Échec ($c)' : 'Failed ($c)';
  String get passwordsDoNotMatch => _code == 'fr' ? 'Les mots de passe ne correspondent pas' : 'Passwords do not match';

  // Export/Import
  String get exportHistory => _code == 'fr' ? 'Exporter l\'historique' : 'Export history';
  String get importHistory => _code == 'fr' ? 'Importer l\'historique' : 'Import history';
  String get exportCanceled => _code == 'fr' ? 'Export annulé' : 'Export canceled';
  String get exportSuccess => _code == 'fr' ? 'Historique exporté' : 'History exported';
  String get exportFailed => _code == 'fr' ? 'Échec de l\'export' : 'Export failed';
  String get confirmImportReplace => _code == 'fr'
      ? 'Importer remplacera votre historique actuel. Continuer ?'
      : 'Import will replace your current history. Continue?';
  String get importSuccess => _code == 'fr' ? 'Historique importé' : 'History imported';
  String get importFailed => _code == 'fr' ? 'Échec de l\'import' : 'Import failed';
}