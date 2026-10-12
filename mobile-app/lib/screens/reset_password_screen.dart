import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../core/validators.dart';
import '../providers/providers.dart';
import '../services/api_service.dart';
import '../widgets/app_background.dart';
import '../widgets/app_logo.dart';
import '../widgets/inline_error.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String? initialEmail;
  final String? initialToken;
  const ResetPasswordScreen({super.key, this.initialEmail, this.initialToken});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl;
  late final TextEditingController _tokenCtrl;
  final _pwdCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
    _tokenCtrl = TextEditingController(text: widget.initialToken ?? '');
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _tokenCtrl.dispose();
    _pwdCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      await ref.read(apiProvider).resetPassword(
            email: _emailCtrl.text.trim(),
            token: _tokenCtrl.text.trim(),
            newPassword: _pwdCtrl.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated. Please log in.')),
      );
      context.go('/login');
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiException ? e.message : 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasEmail = (widget.initialEmail ?? '').isNotEmpty;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo(size: 72)),
                  const SizedBox(height: 14),
                  Text('Create New Password',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text('Choose a new password for your account.',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                  if (hasEmail) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.mark_email_read_outlined, size: 20, color: AppColors.primaryDark),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'If ${widget.initialEmail} has an account, we\'ve sent reset instructions. '
                              'Enter the code from the email below.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                    validator: Validators.email,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _tokenCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reset code',
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the reset code' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _pwdCtrl,
                    obscureText: _obscure,
                    maxLength: 16,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      counterText: '',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: Validators.newPassword,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmCtrl,
                    obscureText: _obscure,
                    maxLength: 16,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      counterText: '',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (v) => v != _pwdCtrl.text ? "Passwords don't match" : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    InlineError(_error!),
                  ],
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: _loading ? null : _reset,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Reset Password'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Back to Login'),
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