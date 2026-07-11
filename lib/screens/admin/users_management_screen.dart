import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/subscription_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';

/// شاشة إدارة المستخدمين - مخصصة للمطور والمدير
class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  List<User> _users = [];
  List<User> _filtered = [];
  bool _loading = true;
  String _searchQuery = '';
  String _filterRole = 'all';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final users = await AdminService.getAllUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _applyFilters();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('خطأ في تحميل المستخدمين');
    }
  }

  void _applyFilters() {
    var list = List<User>.from(_users);
    if (_filterRole != 'all') {
      list = list.where((u) => u.role == _filterRole).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((u) {
        return u.username.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            u.fullName.toLowerCase().contains(q);
      }).toList();
    }
    setState(() => _filtered = list);
  }

  void _showError(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: AppColors.error,
      textColor: Colors.white,
    );
  }

  void _showSuccess(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: AppColors.success,
      textColor: Colors.white,
    );
  }

  List<String> _assignableRolesFor(User user) {
    final actorLevel = UserRole.level(user.role);
    return UserRole.all
        .where((role) => UserRole.level(role) < actorLevel)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentUser = auth.user;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchAndFilters(),
            _buildStatsBar(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _loadUsers,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) =>
                            _buildUserCard(_filtered[i], currentUser),
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUserDialog(null),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: Text(
          'إضافة مستخدم',
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'إدارة المستخدمين',
                  style: GoogleFonts.cairo(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${_users.length} حساب مسجل',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadUsers,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            onChanged: (v) {
              _searchQuery = v;
              _applyFilters();
            },
            style: GoogleFonts.cairo(),
            decoration: InputDecoration(
              hintText: 'بحث عن مستخدم...',
              hintStyle: GoogleFonts.cairo(color: AppColors.textHint),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.primary,
              ),
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('الكل', 'all', Icons.people_rounded),
                _filterChip('المطورون', UserRole.developer, Icons.code_rounded),
                _filterChip('المديرون', UserRole.admin, Icons.shield_rounded),
                _filterChip('المشرفون', UserRole.manager, Icons.school_rounded),
                _filterChip('المعلمون', UserRole.teacher, Icons.book_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value, IconData icon) {
    final selected = _filterRole == value;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: FilterChip(
        selected: selected,
        onSelected: (_) {
          setState(() => _filterRole = value);
          _applyFilters();
        },
        avatar: Icon(
          icon,
          size: 16,
          color: selected ? Colors.white : AppColors.primary,
        ),
        label: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 12,
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.background,
        selectedColor: AppColors.primary,
        showCheckmark: false,
        side: BorderSide(
          color: selected ? AppColors.primary : Colors.grey.shade300,
        ),
      ),
    );
  }

  Widget _buildStatsBar() {
    final total = _filtered.length;
    final active = _filtered.where((u) => u.isActive).length;
    final inactive = total - active;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          _statChip(Icons.people, '$total', 'الكل', AppColors.primary),
          _divider(),
          _statChip(Icons.check_circle, '$active', 'نشط', AppColors.success),
          _divider(),
          _statChip(Icons.block, '$inactive', 'موقوف', AppColors.error),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 28,
    color: Colors.grey.withValues(alpha: 0.2),
  );

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 76,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'لا يوجد مستخدمون',
            style: GoogleFonts.cairo(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(User user, User? currentUser) {
    final color = _roleColor(user.role);
    final canModify = currentUser?.canModifyUser(user) ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: user.isActive
              ? Colors.grey.withValues(alpha: 0.15)
              : AppColors.error.withValues(alpha: 0.3),
          width: user.isActive ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: 0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        UserRole.icon(user.role),
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                  if (!user.isActive)
                    Positioned(
                      top: -2,
                      left: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.block,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            UserRole.label(user.role),
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            user.displayName,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${user.username}',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (user.email.isNotEmpty)
                      Text(
                        user.email,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _subscriptionChip(user),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (canModify) ...[
                _actionBtn(
                  icon: user.isActive
                      ? Icons.block_rounded
                      : Icons.check_circle_rounded,
                  label: user.isActive ? 'إيقاف' : 'تفعيل',
                  color: user.isActive ? AppColors.warning : AppColors.success,
                  onTap: () => _toggleActive(user),
                ),
                const SizedBox(width: 6),
                _actionBtn(
                  icon: Icons.lock_reset_rounded,
                  label: 'كلمة السر',
                  color: AppColors.info,
                  onTap: () => _resetPasswordDialog(user),
                ),
                const SizedBox(width: 6),
                _actionBtn(
                  icon: Icons.edit_rounded,
                  label: 'تعديل',
                  color: AppColors.primary,
                  onTap: () => _showUserDialog(user),
                ),
                const SizedBox(width: 6),
                _actionBtn(
                  icon: Icons.delete_rounded,
                  label: 'حذف',
                  color: AppColors.error,
                  onTap: () => _confirmDelete(user),
                ),
              ] else ...[
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      currentUser?.id == user.id
                          ? 'هذا حسابك الشخصي'
                          : 'لا تملك صلاحية تعديل هذا الحساب',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case UserRole.developer:
        return const Color(0xFF6A1B9A);
      case UserRole.admin:
        return AppColors.error;
      case UserRole.manager:
        return AppColors.warning;
      case UserRole.teacher:
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _subscriptionChip(User user) {
    final subscription = user.subscription;
    final active = subscription.isUsable;
    final color = active ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            '${subscription.planLabel} • ${subscription.statusLabel}',
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────── Dialogs ───────────

  Future<void> _showUserDialog(User? existing) async {
    final currentUser = context.read<AuthProvider>().user;
    if (currentUser == null || !currentUser.canManageUsers) {
      _showError('لا تملك صلاحية إدارة المستخدمين');
      return;
    }
    if (existing != null && !currentUser.canModifyUser(existing)) {
      _showError('لا تملك صلاحية تعديل هذا المستخدم');
      return;
    }
    final assignableRoles = _assignableRolesFor(currentUser);
    if (assignableRoles.isEmpty) {
      _showError('لا توجد أدوار مسموح لك بإسنادها');
      return;
    }
    final usernameCtrl = TextEditingController(text: existing?.username ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final fullNameCtrl = TextEditingController(text: existing?.fullName ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final passwordCtrl = TextEditingController();
    final expiresCtrl = TextEditingController(
      text: existing?.subscription.expiresAt == null
          ? ''
          : _dateInput(existing!.subscription.expiresAt!),
    );
    String selectedRole = existing?.role ?? UserRole.teacher;
    if (!assignableRoles.contains(selectedRole)) {
      selectedRole = assignableRoles.last;
    }
    String selectedPlan =
        existing?.subscription.plan ?? SubscriptionPlan.professional;
    if (!SubscriptionPlan.commercial.contains(selectedPlan)) {
      selectedPlan = SubscriptionPlan.professional;
    }
    String selectedStatus =
        existing?.subscription.status ?? SubscriptionStatus.active;
    if (!SubscriptionStatus.all.contains(selectedStatus)) {
      selectedStatus = SubscriptionStatus.active;
    }
    final formKey = GlobalKey<FormState>();
    final isEdit = existing != null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                isEdit ? Icons.edit_rounded : Icons.person_add_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isEdit ? 'تعديل المستخدم' : 'مستخدم جديد',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dlgField(
                      ctrl: fullNameCtrl,
                      label: 'الاسم الكامل',
                      icon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: 10),
                    _dlgField(
                      ctrl: usernameCtrl,
                      label: 'اسم المستخدم *',
                      icon: Icons.person_outline,
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 10),
                    _dlgField(
                      ctrl: emailCtrl,
                      label: 'البريد الإلكتروني',
                      icon: Icons.email_outlined,
                    ),
                    const SizedBox(height: 10),
                    _dlgField(
                      ctrl: phoneCtrl,
                      label: 'رقم الهاتف',
                      icon: Icons.phone_outlined,
                    ),
                    const SizedBox(height: 10),
                    if (!isEdit)
                      _dlgField(
                        ctrl: passwordCtrl,
                        label: 'كلمة المرور *',
                        icon: Icons.lock_outline,
                        obscure: true,
                        validator: (v) => (v == null || v.length < 4)
                            ? 'كلمة المرور 4 أحرف على الأقل'
                            : null,
                      ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: InputDecoration(
                        labelText: 'الدور',
                        labelStyle: GoogleFonts.cairo(),
                        prefixIcon: const Icon(Icons.shield_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: assignableRoles
                          .map(
                            (r) => DropdownMenuItem(
                              value: r,
                              child: Row(
                                children: [
                                  Text(UserRole.icon(r)),
                                  const SizedBox(width: 8),
                                  Text(
                                    UserRole.label(r),
                                    style: GoogleFonts.cairo(),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      validator: (v) =>
                          v == null || !assignableRoles.contains(v)
                          ? 'هذا الدور غير مسموح'
                          : null,
                      onChanged: (v) =>
                          setSt(() => selectedRole = v ?? selectedRole),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedPlan,
                      decoration: InputDecoration(
                        labelText: 'خطة الاشتراك',
                        labelStyle: GoogleFonts.cairo(),
                        prefixIcon: const Icon(
                          Icons.workspace_premium_outlined,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: SubscriptionPlan.commercial
                          .map(
                            (plan) => DropdownMenuItem(
                              value: plan,
                              child: Text(
                                SubscriptionPlan.label(plan),
                                style: GoogleFonts.cairo(),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setSt(() => selectedPlan = v ?? selectedPlan),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedStatus,
                      decoration: InputDecoration(
                        labelText: 'حالة الاشتراك',
                        labelStyle: GoogleFonts.cairo(),
                        prefixIcon: const Icon(Icons.verified_user_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: SubscriptionStatus.all
                          .map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(
                                SubscriptionStatus.label(status),
                                style: GoogleFonts.cairo(),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setSt(() => selectedStatus = v ?? selectedStatus),
                    ),
                    const SizedBox(height: 10),
                    _dlgField(
                      ctrl: expiresCtrl,
                      label: 'تاريخ انتهاء الاشتراك (YYYY-MM-DD)',
                      icon: Icons.event_outlined,
                      validator: (v) {
                        final text = v?.trim() ?? '';
                        if (text.isEmpty) return null;
                        return DateTime.tryParse(text) == null
                            ? 'استخدم الصيغة YYYY-MM-DD'
                            : null;
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (!assignableRoles.contains(selectedRole)) {
                  _showError('هذا الدور غير مسموح لك');
                  return;
                }
                try {
                  final subscription = Subscription(
                    plan: selectedPlan,
                    status: selectedStatus,
                    expiresAt: _parseExpiry(expiresCtrl.text),
                  );
                  if (isEdit) {
                    final updated = existing.copyWith(
                      username: usernameCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      fullName: fullNameCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      role: selectedRole,
                      subscription: subscription,
                    );
                    await AdminService.updateUser(updated, actor: currentUser);
                  } else {
                    await AdminService.createUser(
                      username: usernameCtrl.text.trim(),
                      password: passwordCtrl.text,
                      email: emailCtrl.text.trim(),
                      role: selectedRole,
                      fullName: fullNameCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      subscription: subscription,
                      actor: currentUser,
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _showSuccess(isEdit ? 'تم التحديث' : 'تم إنشاء الحساب');
                  _loadUsers();
                } catch (e) {
                  _showError(e.toString().replaceAll('Exception: ', ''));
                }
              },
              child: Text(
                isEdit ? 'حفظ' : 'إنشاء',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dlgField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    bool obscure = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      style: GoogleFonts.cairo(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(),
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: validator,
    );
  }

  String _dateInput(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  DateTime? _parseExpiry(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  Future<void> _toggleActive(User user) async {
    final currentUser = context.read<AuthProvider>().user;
    if (currentUser == null || !currentUser.canModifyUser(user)) {
      _showError('لا تملك صلاحية تعديل هذا المستخدم');
      return;
    }
    try {
      await AdminService.toggleUserActive(user.id, actor: currentUser);
      _showSuccess(user.isActive ? 'تم إيقاف الحساب' : 'تم تفعيل الحساب');
      _loadUsers();
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _resetPasswordDialog(User user) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'تعيين كلمة مرور جديدة',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'للمستخدم: ${user.displayName}',
              style: GoogleFonts.cairo(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              style: GoogleFonts.cairo(),
              decoration: InputDecoration(
                labelText: 'كلمة المرور الجديدة',
                labelStyle: GoogleFonts.cairo(),
                prefixIcon: const Icon(Icons.lock_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.length < 4) {
                _showError('كلمة المرور 4 أحرف على الأقل');
                return;
              }
              final currentUser = context.read<AuthProvider>().user;
              if (currentUser == null || !currentUser.canModifyUser(user)) {
                _showError('لا تملك صلاحية تعديل هذا المستخدم');
                return;
              }
              try {
                await AdminService.resetPassword(
                  user.id,
                  ctrl.text,
                  actor: currentUser,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _showSuccess('تم تغيير كلمة المرور');
              } catch (e) {
                _showError(e.toString().replaceAll('Exception: ', ''));
              }
            },
            child: Text(
              'تأكيد',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(User user) async {
    // ============ Critical-action protection ============
    // Prevent accidental deletion of protected accounts.
    if (user.role == 'developer' || user.username == 'developer') {
      _showError('لا يمكن حذف حساب المطور (محمي)');
      return;
    }

    final TextEditingController confirmCtrl = TextEditingController();
    bool agreed = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.error,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                'تأكيد الحذف النهائي',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'سيتم حذف الحساب: ${user.displayName}\n'
                'هذه عملية نهائية لا يمكن التراجع عنها وقد تؤثر على البيانات والتقارير المرتبطة.',
                style: GoogleFonts.cairo(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text(
                'اكتب كلمة "حذف" للتأكيد:',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: confirmCtrl,
                onChanged: (v) => setStateDialog(() {
                  agreed = v.trim() == 'حذف';
                }),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'حذف',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: GoogleFonts.cairo(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: agreed ? () => Navigator.pop(ctx, true) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: Text(
                'حذف نهائياً',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );

    confirmCtrl.dispose();
    if (result != true) return;
    if (!mounted) return;
    final currentUser = context.read<AuthProvider>().user;
    if (currentUser == null || !currentUser.canModifyUser(user)) {
      _showError('لا تملك صلاحية حذف هذا المستخدم');
      return;
    }

    // Show progress so user can't double-trigger
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await AdminService.deleteUser(user.id, actor: currentUser);
      if (!mounted) return;
      Navigator.pop(context); // close progress
      _showSuccess('تم حذف الحساب');
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close progress
      _showError('تعذر حذف الحساب: $e');
    }
  }
}
