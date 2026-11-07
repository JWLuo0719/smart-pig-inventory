import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_failure_code.dart';
import '../../core/network/socket_failure.dart';
import '../../core/theme/app_theme.dart';

String _loginErrorMessage(Object error) {
  if (error is PlatformException) {
    return '手机未能读取或保存登录信息。请先解锁手机，再重试恢复已有登录；不要清除应用数据。';
  }
  if (error is DioException) {
    if (error.type == DioExceptionType.badCertificate) {
      return '服务器安全证书校验失败，请联系管理员。';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return '连接服务器超时，请检查网络后重试。';
    }
    if (error.type == DioExceptionType.connectionError ||
        (error.type == DioExceptionType.unknown &&
            isSocketFailure(error.error))) {
      return '无法连接服务器，请检查网络及服务是否可用。';
    }
    final int? status = error.response?.statusCode;
    if (status == 401) {
      return error.requestOptions.path.endsWith('/auth/login')
          ? '账号或密码不正确，请重新输入。'
          : '登录状态已失效，请重新登录。';
    }
    if (status == 403) return '当前账号没有访问权限，请联系管理员。';
    if (status == 429) return '登录请求过于频繁，请稍后重试。';
    if (status != null && status >= 500) return '服务器暂时不可用，请稍后重试。';
  }
  return '登录未完成，请重试；若持续失败，请联系管理员。';
}

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
            padding: AppSpacing.page,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.barnBlue,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: const Icon(Icons.agriculture_outlined,
                          size: 28, color: Colors.white),
                    ),
                    const SizedBox(height: 14),
                    Text('智慧猪场场主',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text('使用已授权的科研组账号登录',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _username,
                              enabled: !isLoading,
                              autofillHints: const <String>[
                                AutofillHints.username
                              ],
                              decoration:
                                  const InputDecoration(labelText: '账号'),
                              validator: (String? value) =>
                                  value == null || value.trim().isEmpty
                                      ? '请输入账号'
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _password,
                              enabled: !isLoading,
                              obscureText: _obscurePassword,
                              autofillHints: const <String>[
                                AutofillHints.password
                              ],
                              decoration: InputDecoration(
                                labelText: '密码',
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
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
                          ],
                        ),
                      ),
                    ),
                    if (widget.error != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(_loginErrorMessage(widget.error!),
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                      Text('问题编号：${authFailureCode(widget.error!)}',
                          style: Theme.of(context).textTheme.bodySmall),
                      TextButton.icon(
                        onPressed: isLoading
                            ? null
                            : () => ref.invalidate(authControllerProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试恢复已有登录'),
                      ),
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
