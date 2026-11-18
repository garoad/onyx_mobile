import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../onyx_controller.dart';
import 'theme.dart';

Future<void> runAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error)),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: OnyxColors.danger)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class PageIntro extends StatelessWidget {
  final String eyebrow, title, description;
  const PageIntro({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: OnyxColors.accent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(
            color: OnyxColors.muted,
            height: 1.55,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
}

class Panel extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;
  final Color? borderColor;
  const Panel({
    super.key,
    this.title,
    this.icon,
    this.trailing,
    required this.children,
    this.borderColor,
  });
  @override
  Widget build(BuildContext context) => Card(
    shape: borderColor == null
        ? null
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: borderColor!),
          ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: OnyxColors.accent),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
          ],
          ...children,
        ],
      ),
    ),
  );
}

class HelpNote extends StatelessWidget {
  final String text;
  final IconData icon;
  const HelpNote(this.text, {super.key, this.icon = Icons.info_outline});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: OnyxColors.muted),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: OnyxColors.muted,
              height: 1.6,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}

class ParameterSlider extends StatelessWidget {
  final String label;
  final int value, min, max;
  final String Function(int)? format;
  final ValueChanged<int>? onChanged;
  const ParameterSlider({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 100,
    this.format,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final bounded = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: onChanged == null
                        ? OnyxColors.muted
                        : OnyxColors.text,
                  ),
                ),
              ),
              Text(
                format?.call(bounded) ?? '$bounded',
                style: const TextStyle(
                  color: OnyxColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SizedBox(
            height: 42,
            child: Slider(
              key: ValueKey('slider-$label'),
              value: bounded.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              semanticFormatterCallback: (value) =>
                  '$label ${format?.call(value.round()) ?? value.round().toString()}',
              onChanged: onChanged == null
                  ? null
                  : (next) => onChanged!(next.round()),
            ),
          ),
        ],
      ),
    );
  }
}

class ChoiceField extends StatelessWidget {
  final String label;
  final int value;
  final Map<int, String> choices;
  final ValueChanged<int>? onChanged;
  const ChoiceField({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final options = {...choices};
    if (!options.containsKey(value)) options[value] = '모델 $value (기기 값)';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<int>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        dropdownColor: OnyxColors.elevated,
        menuMaxHeight: 400,
        items: options.entries
            .map(
              (entry) => DropdownMenuItem(
                value: entry.key,
                child: Text(
                  entry.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            )
            .toList(),
        onChanged: onChanged == null
            ? null
            : (next) {
                if (next != null) onChanged!(next);
              },
      ),
    );
  }
}

class ToggleRow extends StatelessWidget {
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const ToggleRow({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              if (description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    description!,
                    style: const TextStyle(
                      color: OnyxColors.muted,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch.adaptive(
          key: ValueKey('toggle-$label'),
          value: value,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class ResponsivePanels extends StatelessWidget {
  final List<Widget> children;
  const ResponsivePanels({super.key, required this.children});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 720 ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(),
      );
    },
  );
}

class PageScroll extends StatelessWidget {
  final List<Widget> children;
  final String id;
  const PageScroll({super.key, required this.id, required this.children});
  @override
  Widget build(BuildContext context) => ListView(
    key: PageStorageKey(id),
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
    children: children,
  );
}

class OnyxMark extends StatelessWidget {
  final double size;
  const OnyxMark({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Onyx',
    image: true,
    child: CustomPaint(size: Size.square(size), painter: _MarkPainter()),
  );
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.width * .44;
    final hex = Path();
    for (var index = 0; index < 6; index++) {
      final angle = math.pi / 3 * index - math.pi / 2;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (index == 0) {
        hex.moveTo(point.dx, point.dy);
      } else {
        hex.lineTo(point.dx, point.dy);
      }
    }
    hex.close();
    canvas.drawPath(
      hex,
      Paint()..color = OnyxColors.accent.withValues(alpha: .12),
    );
    canvas.drawPath(
      hex,
      Paint()
        ..color = OnyxColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .04,
    );
    final wave = Path()..moveTo(size.width * .23, size.height * .52);
    for (var index = 0; index <= 60; index++) {
      final x = index / 60;
      final y = math.sin(x * math.pi * 4) * math.sin(x * math.pi) * .13;
      wave.lineTo(size.width * (.23 + x * .54), size.height * (.52 + y));
    }
    canvas.drawPath(
      wave,
      Paint()
        ..color = OnyxColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .035
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
