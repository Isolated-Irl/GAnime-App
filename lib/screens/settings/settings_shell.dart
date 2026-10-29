// Shared website-parity widgets for the Settings sub-screens.
// Visual language (from the ganime.pages.dev settings screens):
// near-black background, dark #222222 rounded cards, green accent,
// caps section labels, white primary text, grey secondary text.
import 'package:flutter/material.dart';

const gaBg = Color(0xFF0D0D0D);
const gaCard = Color(0xFF222222);
const gaCardBorder = Color(0xFF333333);
const gaFieldFill = Color(0xFF1A1A1A);
const gaGreen = Color(0xFF22C55E);
const gaGrey = Color(0xFF9CA3AF);
const gaGreyDark = Color(0xFF6B7280);

/// Website Layout > THEME swatches: (value, label, color).
const gaThemes = <({String value, String label, Color color})>[
  (value: 'white', label: 'White', color: Color(0xFFFFFFFF)),
  (value: 'crimson', label: 'Crimson', color: Color(0xFFE11D48)),
  (value: 'ocean', label: 'Ocean', color: Color(0xFF3B82F6)),
  (value: 'violet', label: 'Violet', color: Color(0xFF8B5CF6)),
  (value: 'emerald', label: 'Emerald', color: gaGreen),
  (value: 'amber', label: 'Amber', color: Color(0xFFF59E0B)),
  (value: 'rose', label: 'Rose', color: Color(0xFFF43F5E)),
];

/// Theme name -> accent color. Unknown names fall back to emerald.
Color themeAccent(String theme) {
  for (final t in gaThemes) {
    if (t.value == theme) return t.color;
  }
  return gaGreen;
}

/// Scaffold shell for a settings sub-screen: rounded back button + title.
class GASubPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const GASubPage({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: gaBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Row(
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: gaCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: gaCardBorder),
                    ),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Small caps section label, e.g. "CONTINUE WATCHING DATA SOURCE".
Widget gaSectionLabel(String t) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        t.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: gaGrey,
        ),
      ),
    );

/// Dark rounded card container.
class GACard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Border? border;
  const GACard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: gaCard,
        borderRadius: BorderRadius.circular(16),
        border: border ?? Border.all(color: gaCardBorder),
      ),
      child: child,
    );
  }
}

/// Website-style row: label left, switch right.
Widget gaToggleRow({
  required String title,
  String? subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return GACard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: gaGrey)),
              ],
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    ),
  );
}

/// Website-style row: label left, value pill right; taps open an option dialog.
Widget gaDropdownRow({
  required BuildContext context,
  required String title,
  required String value,
  required Map<String, String> options,
  required ValueChanged<String> onChanged,
}) {
  final label = options[value] ?? value;
  return GACard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: InkWell(
      onTap: () async {
        final picked = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            backgroundColor: gaCard,
            title: Text(title,
                style:
                    const TextStyle(color: Colors.white, fontSize: 16)),
            children: [
              RadioGroup<String>(
                groupValue: value,
                onChanged: (v) => Navigator.of(ctx).pop(v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in options.entries)
                      RadioListTile<String>(
                        value: e.key,
                        title: Text(e.value,
                            style:
                                const TextStyle(color: Colors.white)),
                        activeColor:
                            Theme.of(ctx).colorScheme.primary,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
        if (picked != null && picked != value) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: gaFieldFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: gaCardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style:
                          const TextStyle(fontSize: 13, color: gaGrey)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down,
                      color: gaGrey, size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Website-style row: label left, slider middle, value text right.
Widget gaSliderRow({
  required String title,
  required double value,
  required double min,
  required double max,
  int? divisions,
  required String Function(double) label,
  required ValueChanged<double> onChanged,
}) {
  return GACard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(label(value),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, color: gaGrey)),
        ),
      ],
    ),
  );
}

/// Website-style row: label left, chevron right; opens a sub-page.
Widget gaChevronRow({
  required String title,
  String? subtitle,
  required VoidCallback onTap,
}) {
  return GACard(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style:
                            const TextStyle(fontSize: 12, color: gaGrey)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: gaGreyDark, size: 22),
          ],
        ),
      ),
    ),
  );
}

/// Full-width white button with black text (website Account screen).
Widget gaWhiteButton({
  required String label,
  required VoidCallback? onPressed,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    ),
  );
}

/// Full-width green button with white text (website Addons screen).
Widget gaGreenButton({
  required String label,
  required VoidCallback? onPressed,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: gaGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    ),
  );
}

/// Dark outlined text field (website install/config forms).
Widget gaTextField({
  required TextEditingController controller,
  required String hint,
  bool obscure = false,
  TextInputType keyboardType = TextInputType.text,
  int maxLines = 1,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: gaGreyDark),
        filled: true,
        fillColor: gaFieldFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: gaCardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: gaCardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: gaGreen),
        ),
      ),
    ),
  );
}

/// Small grey feedback line under forms.
Widget gaMsg(String msg) => msg.isEmpty
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(msg,
            style: const TextStyle(fontSize: 13, color: gaGrey)),
      );
