import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/student_model.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';

class GradeFieldCard extends StatefulWidget {
  final GradeField field;
  final double? value;
  final bool isHighlighted;
  final ValueChanged<double> onChanged;

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
    if (old.value != widget.value && !_focus.hasFocus) {
      _ctrl.text = _format(widget.value);
    }
  }

  String _format(double? v) {
    if (v == null) return '';
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<
        ThemeProvider>(); // يضمن إعادة البناء فوراً عند تبديل الوضع الليلي/الفاتح
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
            : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              widget.isHighlighted ? AppColors.primary : Colors.grey.shade200,
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
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'الحد الأقصى: ${_format(widget.field.max)}',
                  style: TextStyle(
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                // Allow only digits, single decimal point, no negatives.
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                // Prevent multiple dots and overflow lengths.
                TextInputFormatter.withFunction((oldVal, newVal) {
                  final t = newVal.text;
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
                suffixStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.textHint,
                ),
                filled: true,
                fillColor: color.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: color.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: color.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: color, width: 2),
                ),
              ),
              onChanged: (v) {
                if (v.isEmpty) {
                  widget.onChanged(0);
                  return;
                }
                final parsed = double.tryParse(v);
                if (parsed == null || !parsed.isFinite || parsed < 0) {
                  // Invalid input — silently keep old value, do not propagate.
                  return;
                }
                widget.onChanged(
                  parsed.clamp(0, widget.field.max).toDouble(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
