import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.error});
  final Object? error;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isLoading = ref.watch(authControllerProvider).isLoading;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Icon(Icons.agriculture_outlined, size: 58),
                    const SizedBox(height: 20),
                    Text('智慧猪场场主',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text('使用已授权的科研组账号登录',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _username,
                      enabled: !isLoading,
                      autofillHints: const <String>[AutofillHints.username],
                      decoration: const InputDecoration(labelText: '账号'),
                      validator: (String? value) =>
                          value == null || value.trim().isEmpty
                              ? '请输入账号'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      enabled: !isLoading,
                      obscureText: _obscurePassword,
                      autofillHints: const <String>[AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: '密码',
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                        ),
                      ),
                      validator: (String? value) =>
                          value == null || value.length < 8
                              ? '密码至少为 8 个字符'
                              : null,
                      onFieldSubmitted: (_) => _login(),
                    ),
                    if (widget.error != null) ...<Widget>[
                      const SizedBox(height: 16),
                      const Text('无法恢复登录状态。请检查网络后重新登录。',
                          style: TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: isLoading ? null : _login,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: isLoading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator())
                            : const Text('登录'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('离线时可在最近验证后的 7 天内继续处理本机草稿，但不能同步。',
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authControllerProvider.notifier).login(
          username: _username.text.trim(),
          password: _password.text,
        );
  }
}
