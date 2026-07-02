import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/student_model.dart';
import '../theme/app_theme.dart';

class GradeFieldInput extends StatefulWidget {
  final GradeField field;
  final double? value;
  final ValueChanged<double> onChanged;

  const GradeFieldInput({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
  });

  @override
  State<GradeFieldInput> createState() => _GradeFieldInputState();
}

class _GradeFieldInputState extends State<GradeFieldInput> {
  late TextEditingController _ctrl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(covariant GradeFieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newText = _format(widget.value);
    if (!_focus.hasFocus && _ctrl.text != newText) {
      _ctrl.text = newText;
    }
  }

  String _format(double? v) {
    if (v == null) return '';
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value ?? 0;
    final progress = widget.field.max > 0 ? (value / widget.field.max).clamp(0.0, 1.0) : 0.0;
    final color = progress >= 0.5 ? AppColors.success : (progress >= 0.3 ? AppColors.warning : AppColors.error);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.field.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                'من ${_format(widget.field.max)}',
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Decrement
              _SquareIconBtn(
                icon: Icons.remove,
                onTap: () {
                  final newV = (value - 1).clamp(0.0, widget.field.max);
                  widget.onChanged(newV);
                  _ctrl.text = _format(newV);
                },
              ),
              const SizedBox(width: 8),
              // Value Input
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
                    hintText: '0',
                  ),
                  onChanged: (txt) {
                    final v = double.tryParse(txt);
                    if (v != null && v.isFinite && v >= 0) {
                      // تطبيق clamp لمنع إدخال قيمة أكبر من الحد الأقصى
                      widget.onChanged(v.clamp(0.0, widget.field.max));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Increment
              _SquareIconBtn(
                icon: Icons.add,
                onTap: () {
                  final newV = (value + 1).clamp(0.0, widget.field.max);
                  widget.onChanged(newV);
                  _ctrl.text = _format(newV);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SquareIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SquareIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 48,
          child: Icon(icon, color: AppColors.primary),
        ),
      ),
    );
  }
}
