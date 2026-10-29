// Boot flow screens, website parity (ganime.pages.dev):
// splash -> auth gate (Welcome back) -> profile picker -> add profile.
// Avatar catalog mirrors the website's Config.AVATAR_CATALOG exactly
// (same names/emoji/backgrounds) so avatars match across web and app.
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../models.dart';
import '../services/firebase_sync.dart';
import '../store.dart';
import '../widgets/logo.dart';
import '../widgets/ga_image.dart';

/// Website's built-in avatar catalog: (name, emoji, background color).
const gaAvatars = <({String name, String emoji, int bg})>[
  (name: 'Bram', emoji: '🐻', bg: 0xFFF48FB1),
  (name: 'Moo', emoji: '🐮', bg: 0xFFB39DDB),
  (name: 'Pig', emoji: '🐷', bg: 0xFF64B5F6),
  (name: 'Owl', emoji: '🦉', bg: 0xFF4DB6AC),
  (name: 'Leo', emoji: '🦁', bg: 0xFFDCE775),
  (name: 'Cat', emoji: '🐱', bg: 0xFFBA68C8),
  (name: 'Fox', emoji: '🦊', bg: 0xFFFFB74D),
  (name: 'Bunny', emoji: '🐰', bg: 0xFFE57373),
  (name: 'Panda', emoji: '🐼', bg: 0xFFFFA726),
  (name: 'Ghost', emoji: '👻', bg: 0xFF4DD0E1),
  (name: 'Bot', emoji: '🤖', bg: 0xFF90A4AE),
  (name: 'Frog', emoji: '🐸', bg: 0xFF81C784),
  (name: 'Monk', emoji: '🐵', bg: 0xFFA1887F),
  (name: 'Uni', emoji: '🦄', bg: 0xFFF06292),
  (name: 'Drago', emoji: '🐲', bg: 0xFF7986CB),
  (name: 'Alien', emoji: '👽', bg: 0xFFAED581),
];

/// Max profiles, like the website (Config.PROFILE_LIMIT).
const gaProfileLimit = 3;

({String name, String emoji, int bg}) gaAvatarFor(Profile p) {
  for (final a in gaAvatars) {
    if (a.name == p.avatarName) {
      return (name: a.name, emoji: a.emoji, bg: a.bg);
    }
  }
  final f = gaAvatars.first;
  return (name: f.name, emoji: f.emoji, bg: f.bg);
}

/// Profile avatar circle: custom URL image, else catalog emoji on its bg.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, this.size = 72});
  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final av = gaAvatarFor(profile);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color(av.bg),
      ),
      clipBehavior: Clip.antiAlias,
      child: profile.avatarUrl.isNotEmpty
          ? GaImage(
              url: profile.avatarUrl,
              fit: BoxFit.cover,
              errorFallback: Center(
                  child: Text(av.emoji,
                      style: TextStyle(fontSize: size * 0.5))),
            )
          : Center(
              child:
                  Text(av.emoji, style: TextStyle(fontSize: size * 0.5))),
    );
  }
}

// ---------------------------------------------------------------------------
// Splash: the website's full intro animation, ported to Flutter —
// the mark DRAWS itself while folding -90°→0° (1s, 0.05–1.05s), slides
// left (0.55s, 0.85–1.4s), and the "nime" letters rise in staggered;
// an accent glow pulses behind throughout. ~1.75s total, then the boot
// flow advances past it (main.dart's splash timer).
// ---------------------------------------------------------------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _totalMs = 1750;
  static const _logoSize = 72.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _totalMs),
  )..forward();
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  late final Animation<double> _draw;
  late final Animation<double> _fold;
  late final Animation<double> _slide;
  late final List<Animation<double>> _letters;

  /// Horizontal shift that keeps the logo visually centered while the
  /// (initially invisible) letters reserve their layout space.
  double _shift = 0;

  @override
  void initState() {
    super.initState();
    // cubic-bezier(0.4, 0, 0.2, 1) == Curves.fastOutSlowIn.
    const siteCurve = Curves.fastOutSlowIn;
    _draw = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _c,
          curve: const Interval(0.03, 0.60, curve: siteCurve)),
    );
    _fold = Tween(begin: -math.pi / 2, end: 0.0).animate(
      CurvedAnimation(
          parent: _c,
          curve: const Interval(0.03, 0.60, curve: siteCurve)),
    );
    _slide = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _c,
          curve: const Interval(0.486, 0.80, curve: siteCurve)),
    );
    // "nime" letters rise staggered: 0.35s each, ~80ms stagger, easeOut.
    _letters = [
      for (int i = 0; i < 4; i++)
        Tween(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _c,
            curve: Interval(
              (0.80 + i * 0.046).clamp(0.0, 1.0),
              (0.80 + i * 0.046 + 0.20).clamp(0.0, 1.0),
              curve: Curves.easeOut,
            ),
          ),
        ),
    ];
    // Measure "nime" so the logo starts perfectly centered.
    final tp = TextPainter(
      text: const TextSpan(
          text: 'nime',
          style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    _shift = (tp.width + 8) / 2;
  }

  @override
  void dispose() {
    _c.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.1,
            colors: [Color(0xFF1E1E1E), Color(0xFF0A0A0A)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pulsing accent glow behind the logo (site's splashGlow).
                AnimatedBuilder(
                  animation: _glow,
                  builder: (_, _) => Opacity(
                    opacity: 0.65 + 0.35 * _glow.value,
                    child: ImageFiltered(
                      imageFilter:
                          ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: Container(
                        width: 340,
                        height: 340,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Color(0x4710B981),
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.65],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Logo lockup: draw + fold, then slide left as the
                // letters rise in staggered to its right.
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(_shift * _slide.value, 0),
                        child: Transform.rotate(
                          angle: _fold.value,
                          alignment: Alignment.center,
                          child: CustomPaint(
                            size: const Size(_logoSize, _logoSize),
                            painter: _SplashLogoPainter(_draw.value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < 4; i++)
                            Opacity(
                              opacity: _letters[i].value,
                              child: Transform.translate(
                                offset: Offset(
                                    0, 16 * (1 - _letters[i].value)),
                                child: Text(
                                  'nime'[i],
                                  style: const TextStyle(
                                      fontSize: 44,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the GAnime mark progressively (website's splashDraw): the folded-G
/// path from widgets/logo.dart, revealed 0→100% via PathMetrics, with the
/// diamond popping in near the end of the draw. Same gradient as the logo.
class _SplashLogoPainter extends CustomPainter {
  final double progress;
  _SplashLogoPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 512;
    final shader = const LinearGradient(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      colors: [
        Color(0xFF064E3B),
        Color(0xFF059669),
        Color(0xFF10B981),
        Color(0xFFA3E635),
      ],
      stops: [0.0, 0.45, 0.75, 1.0],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 50 * s
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter
      ..shader = shader;
    final path = Path()
      ..moveTo(300 * s, 300 * s)
      ..lineTo(105 * s, 430 * s)
      ..lineTo(265 * s, 95 * s)
      ..lineTo(415 * s, 415 * s);
    final p = progress.clamp(0.0, 1.0);
    for (final m in path.computeMetrics()) {
      final len = m.length * p;
      if (len > 0.5) canvas.drawPath(m.extractPath(0, len), paint);
    }
    // Diamond appears as the draw completes.
    if (p > 0.72) {
      final diamond = Path()
        ..moveTo(448 * s, 398 * s)
        ..lineTo(465 * s, 415 * s)
        ..moveTo(448 * s, 432 * s)
        ..lineTo(431 * s, 415 * s)
        ..close();
      canvas.drawPath(
          diamond, Paint()..style = PaintingStyle.fill..shader = shader);
    }
  }

  @override
  bool shouldRepaint(covariant _SplashLogoPainter old) =>
      old.progress != progress;
}

// ---------------------------------------------------------------------------
// Welcome back (auth gate): sign in / create account / forgot password /
// continue as guest. Wired to the existing Firebase REST auth.
// ---------------------------------------------------------------------------
class WelcomeBackScreen extends StatefulWidget {
  const WelcomeBackScreen(
      {super.key,
      required this.firebase,
      required this.onSignedIn,
      required this.onGuest});
  final FirebaseSync firebase;
  final VoidCallback onSignedIn;
  final VoidCallback onGuest;

  @override
  State<WelcomeBackScreen> createState() => _WelcomeBackScreenState();
}

class _WelcomeBackScreenState extends State<WelcomeBackScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String _msg = '';
  bool _msgOk = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _say(String m, {bool ok = false}) {
    if (!mounted) return;
    setState(() {
      _msg = m;
      _msgOk = ok;
    });
  }

  Future<void> _run(Future<void> Function() fn, String okMsg) async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _say('Enter your email address first.');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      await fn();
      _say(okMsg, ok: true);
    } catch (e) {
      _say('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
        await widget.firebase
            .signIn(_email.text.trim(), _password.text);
        await Store.setGuest(false);
        widget.onSignedIn();
      }, 'Signed in.');

  Future<void> _createAccount() => _run(() async {
        if (_password.text.isEmpty) {
          throw Exception('Choose a password first.');
        }
        await widget.firebase
            .signUp(_email.text.trim(), _password.text);
        await Store.setGuest(false);
        widget.onSignedIn();
      }, 'Account created.');

  Future<void> _forgot() => _run(() async {
        await widget.firebase.sendPasswordReset(_email.text.trim());
      }, 'Password-reset email sent. Check your inbox.');

  Widget _field(TextEditingController c, String hint,
      {bool obscure = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: GaColors.of(context).field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType:
            obscure ? TextInputType.visiblePassword : TextInputType.emailAddress,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF6B7280)),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _whiteBtn(String label, VoidCallback? onTap) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        onPressed: _busy ? null : onTap,
        child: Text(label),
      ),
    );
  }

  Widget _darkBtn(String label, VoidCallback? onTap) {
    return Container(
      width: double.infinity,
      height: 52,
      margin: const EdgeInsets.only(top: 12),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF333333)),
          backgroundColor: GaColors.of(context).field,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        onPressed: _busy ? null : onTap,
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LogoMark(size: 44),
                  SizedBox(width: 4),
                  Text('nime',
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Welcome back',
                  style:
                      TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Sign in with your existing account',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
              const SizedBox(height: 28),
              _field(_email, 'Email address'),
              _field(_password, 'Password', obscure: true),
              if (_msg.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_msg,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _msgOk
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFFF87171),
                          fontSize: 13)),
                ),
              _whiteBtn('Sign In', _signIn),
              _darkBtn('Create Account', _createAccount),
              TextButton(
                onPressed: _busy ? null : _forgot,
                child: const Text('Forgot password?',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              _darkBtn('Continue without an account', () async {
                await Store.setGuest(true);
                widget.onGuest();
              }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Who's watching? — profile picker from the real profile store.
// ---------------------------------------------------------------------------
class ProfilePickerScreen extends StatelessWidget {
  const ProfilePickerScreen({
    super.key,
    required this.account,
    required this.profiles,
    required this.activeId,
    required this.onSelect,
    required this.onAddProfile,
    required this.onManage,
    required this.onBack,
  });
  final String account;
  final List<Profile> profiles;
  final String? activeId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAddProfile;
  final VoidCallback onManage;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LogoMark(size: 30),
                    SizedBox(width: 4),
                    Text('nime',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.primary)),
                  ],
                ),
                const SizedBox(height: 36),
                const Text("Who's watching?",
                    style:
                        TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Select a profile to continue',
                    style:
                        TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
                const SizedBox(height: 36),
                // While profiles load, the parent shows skeleton circles.
                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  alignment: WrapAlignment.center,
                  children: [
                    for (int i = 0; i < profiles.length; i++)
                      _profileCircle(context, profiles[i], i == 0),
                    _addCircle(context),
                  ],
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF333333)),
                      backgroundColor: GaColors.of(context).field,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    onPressed: onManage,
                    child: const Text('Manage Profiles'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileCircle(
      BuildContext context, Profile p, bool isPrimary) {
    return GestureDetector(
      onTap: () => onSelect(p.id),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProfileAvatar(profile: p, size: 84),
          const SizedBox(height: 10),
          Text(p.name,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600)),
          if (isPrimary) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Theme.of(context).colorScheme.primary),
              ),
              child: Text('PRIMARY',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Theme.of(context).colorScheme.primary))
            ),
          ],
        ],
      ),
    );
  }

  Widget _addCircle(BuildContext context) {
    return GestureDetector(
      onTap: onAddProfile,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: GaColors.of(context).card,
              ),
              child: Icon(Icons.add, size: 36, color: Colors.white70),
            ),
          ),
          SizedBox(height: 10),
          Text('Add Profile',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Profile — full website layout: live preview card, name field,
// custom avatar URL, avatar catalog grid, Create Profile.
// ---------------------------------------------------------------------------
class AddProfileScreen extends StatefulWidget {
  const AddProfileScreen(
      {super.key,
      required this.account,
      required this.isFirst,
      this.showBack = true,
      required this.onCreated});
  final String account;
  final bool isFirst;

  /// Website parity: the create-first Add Profile (no profiles yet) has
  /// no back button — the web hides it too in that state.
  final bool showBack;
  final VoidCallback onCreated;

  @override
  State<AddProfileScreen> createState() => _AddProfileScreenState();
}

class _AddProfileScreenState extends State<AddProfileScreen> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String _avatarName = 'Bram';
  bool _busy = false;
  String _msg = '';

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  String _nextProfileName(List<Profile> ps) {
    var n = ps.length + 1;
    while (ps.any((p) => p.name == 'Profile $n')) {
      n++;
    }
    return 'Profile $n';
  }

  Future<void> _create() async {
    if (_busy) return;
    final ps = await Store.profiles(widget.account);
    if (ps.length >= gaProfileLimit) {
      setState(() => _msg =
          'Profile limit reached ($gaProfileLimit). Delete one from Manage Profiles to add another.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final name = _name.text.trim().isNotEmpty
          ? _name.text.trim()
          : _nextProfileName(ps);
      final url = _url.text.trim();
      final p = Profile(
        id: 'p${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        avatarName: _avatarName,
        avatarUrl: url,
      );
      ps.add(p);
      await Store.saveProfiles(widget.account, ps);
      await Store.setActiveProfile(widget.account, p.id);
      widget.onCreated();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = Profile(
        id: 'preview',
        name: _name.text.trim().isNotEmpty
            ? _name.text.trim()
            : 'New profile',
        avatarName: _avatarName,
        avatarUrl: _url.text.trim());
    final av = gaAvatarFor(preview);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: widget.showBack,
        leading: widget.showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text('Add Profile',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isFirst)
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Text(
                    'Create your first profile to start using GAnime.',
                    style:
                        TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
              ),
            // Live preview card.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: GaColors.of(context).field,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF333333)),
              ),
              child: Row(
                children: [
                  ProfileAvatar(profile: preview, size: 64),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(preview.name,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                            widget.isFirst
                                ? 'Primary profile'
                                : 'New profile',
                            style: const TextStyle(
                                color: Color(0xFF9CA3AF), fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                            'Avatar: ${preview.avatarUrl.isNotEmpty ? 'Custom URL' : av.name}',
                            style: const TextStyle(
                                color: Color(0xFF9CA3AF), fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _input(_name, 'Profile name', onChanged: (_) => setState(() {})),
            const SizedBox(height: 16),
            const Text('Custom avatar URL',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
                'Paste an image link, or leave this empty to use the built-in avatar catalog.',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
            const SizedBox(height: 8),
            _input(_url, 'https://example.com/avatar.png',
                onChanged: (_) => setState(() {}),
                keyboard: TextInputType.url),
            const SizedBox(height: 16),
            const Text('Choose an avatar',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_avatarName,
                style: const TextStyle(
                    color: Color(0xFF9CA3AF), fontSize: 13)),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: gaAvatars.length,
              itemBuilder: (_, i) {
                final a = gaAvatars[i];
                final selected =
                    _avatarName == a.name && _url.text.trim().isEmpty;
                return GestureDetector(
                  onTap: () => setState(() => _avatarName = a.name),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(a.bg),
                      border: Border.all(
                        color: selected
                            ? Colors.white
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: Center(
                        child: Text(a.emoji,
                            style: const TextStyle(fontSize: 30))),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            if (_msg.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_msg,
                    style: const TextStyle(
                        color: Color(0xFFF87171), fontSize: 13)),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _busy ? null : _create,
                child: const Text('Create Profile'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _input(TextEditingController c, String hint,
      {ValueChanged<String>? onChanged, TextInputType? keyboard}) {
    return Container(
      decoration: BoxDecoration(
        color: GaColors.of(context).field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: TextField(
        controller: c,
        onChanged: onChanged,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF6B7280)),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
