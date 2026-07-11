import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/student_model.dart';
import '../theme/app_theme.dart';

class GradeFieldCard extends StatefulWidget {
  final GradeField field;
  final double? value;
  final bool isHighlighted;
  final ValueChanged<double?> onChanged;

  const GradeFieldCard({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
    this.isHighlighted = false,
  });

  @override
  State<GradeFieldCard> createState() => _GradeFieldCardState();
}

class _GradeFieldCardState extends State<GradeFieldCard> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _format(widget.value));
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant GradeFieldCard old) {
    super.didUpdateWidget(old);
    final fieldChanged =
        old.field.name != widget.field.name ||
        old.field.max != widget.field.max;
    final shouldSync =
        old.value != widget.value &&
        (!_focus.hasFocus || widget.value == null || fieldChanged);
    if (shouldSync) {
      _ctrl.text = _format(widget.value);
    }
  }

  String _format(double? v) {
    if (v == null) return '';
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  String _normalizeNumericInput(String value) {
    const digits = {
      '\u0660': '0',
      '\u0661': '1',
      '\u0662': '2',
      '\u0663': '3',
      '\u0664': '4',
      '\u0665': '5',
      '\u0666': '6',
      '\u0667': '7',
      '\u0668': '8',
      '\u0669': '9',
      '\u06F0': '0',
      '\u06F1': '1',
      '\u06F2': '2',
      '\u06F3': '3',
      '\u06F4': '4',
      '\u06F5': '5',
      '\u06F6': '6',
      '\u06F7': '7',
      '\u06F8': '8',
      '\u06F9': '9',
    };
    var normalized = value.trim();
    digits.forEach((from, to) {
      normalized = normalized.replaceAll(from, to);
    });
    return normalized
        .replaceAll('\u066B', '.')
        .replaceAll('\u066C', '')
        .replaceAll(',', '.')
        .replaceAll('\u060C', '.');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.value != null;
    final percent = hasValue && widget.field.max > 0
        ? (widget.value! / widget.field.max).clamp(0.0, 1.0)
        : 0.0;
    final color = !hasValue
        ? AppColors.textHint
        : percent >= 0.7
        ? AppColors.success
        : percent >= 0.5
        ? AppColors.warning
        : AppColors.error;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isHighlighted
            ? AppColors.primaryLight.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isHighlighted
              ? AppColors.primary
              : Colors.grey.shade200,
          width: widget.isHighlighted ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              hasValue ? Icons.check_circle_rounded : Icons.edit_outlined,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.field.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'الحد الأقصى: ${_format(widget.field.max)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(
                    r'[0-9\u0660-\u0669\u06F0-\u06F9\.,\u060C\u066B\u066C]',
                  ),
                ),
                // Prevent multiple decimal separators and overflow lengths.
                TextInputFormatter.withFunction((oldVal, newVal) {
                  final t = _normalizeNumericInput(newVal.text);
                  if (t.isEmpty) return newVal;
                  if ('.'.allMatches(t).length > 1) return oldVal;
                  if (t.length > 6) return oldVal;
                  return newVal;
                }),
              ],
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                hintText: '0',
                suffixText: '/${_format(widget.field.max)}',
                suffixStyle: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textHint,
                ),
                filled: true,
                fillColor: color.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: color, width: 2),
                ),
              ),
              onChanged: (v) {
                if (v.isEmpty) {
                  widget.onChanged(null);
                  return;
                }
                final parsed = double.tryParse(_normalizeNumericInput(v));
                if (parsed == null || !parsed.isFinite || parsed < 0) {
                  // Invalid input — silently keep old value, do not propagate.
                  return;
                }
                final clamped = parsed.clamp(0, widget.field.max).toDouble();
                widget.onChanged(clamped);
                if (clamped != parsed) {
                  final normalizedText = _format(clamped);
                  _ctrl.value = TextEditingValue(
                    text: normalizedText,
                    selection: TextSelection.collapsed(
                      offset: normalizedText.length,
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
