import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/validators.dart';
import '../providers/providers.dart';
import '../services/api_service.dart';
import '../widgets/app_background.dart';
import '../widgets/app_logo.dart';
import '../widgets/inline_error.dart';
import '../widgets/app_back_button.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final email = _emailCtrl.text.trim();

    String? code;
    try {
      code = await ref.read(apiProvider).forgotPassword(email);
    } on ApiException catch (e) {
      if (e.code != 'AUTH_ERROR') {
        if (mounted) setState(() { _error = e.message; _loading = false; });
        return;
      }
      // An "auth" answer (e.g. unknown email) looks exactly like success,
      // so we never reveal which emails have an account.
    } catch (_) {
      if (mounted) setState(() { _error = 'Something went wrong. Please try again.'; _loading = false; });
      return;
    }

    if (!mounted) return;
    setState(() => _loading = false);
    context.push('/reset-password', extra: {'email': email, 'token': code});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 48, 28, 24),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppBackButton(fallback: '/login'),
                  const SizedBox(height: 12),
                  const Center(child: AppLogo(size: 76)),
                  const SizedBox(height: 16),
                  Text('Forgot Password?',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text('Enter your email and we\'ll send you instructions to reset your password.',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                    validator: Validators.email,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    InlineError(_error!),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loading ? null : _send,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Send Reset Instructions'),
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