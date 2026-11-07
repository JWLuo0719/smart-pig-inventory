import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/auth/auth_controller.dart';
import 'package:smart_pig_inventory/core/network/assistant_api.dart';
import 'package:smart_pig_inventory/core/theme/app_theme.dart';
import 'package:smart_pig_inventory/features/assistant/assistant_screen.dart';

import 'support/competition_auth.dart';

class _Api extends AssistantApi {
  _Api({this.available = true, this.reply})
      : super(baseUrl: 'https://synthetic.invalid');
  final bool available;
  final Future<AssistantReply>? reply;
  var calls = 0;
  String? requestedPen;

  @override
  Future<bool> enabled(String token, CancelToken cancel) async => available;
  @override
  Future<AssistantReply> ask(
      {required String token,
      required String message,
      required DateTime date,
      required CancelToken cancel,
      String? penId,
      String? sessionId}) {
    calls++;
    requestedPen = penId;
    return reply ??
        Future.value(const AssistantReply(
            status: 'ok', answer: '合成解释', facts: [], evidence: []));
  }
}

void main() {
  test('reply parser rejects malformed facts and hides rejected explanations',
      () {
    expect(
        () => AssistantReply.fromJson({
              'status': 'ok',
              'answer': 'synthetic',
              'facts': [
                {
                  'tool': 'get_pen_history',
                  'status': 'ok',
                  'data': {'points': 'bad'}
                }
              ],
              'evidence': [],
            }),
        throwsFormatException);
    final reply = AssistantReply.fromJson({
      'status': 'answer_rejected',
      'answer': 'do not display',
      'facts': [],
      'evidence': [],
    });
    expect(reply.answer, isNull);
    final zero = AssistantReply.fromJson({
      'status': 'ok',
      'answer': 'synthetic',
      'facts': [
        {
          'tool': 'inspect_session',
          'status': 'ok',
          'data': {'candidateCount': 0, 'confirmedCount': null}
        }
      ],
      'evidence': [],
    });
    expect(zero.facts.single['data']['candidateCount'], 0);
  });

  Future<ProviderContainer> pumpAssistant(WidgetTester tester, _Api api) async {
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(CompetitionAuthController.new),
      assistantApiProvider.overrideWithValue(api),
    ]);
    await tester.runAsync(() => container.read(authControllerProvider.future));
    await tester.binding.setSurfaceSize(const Size(360, 1200));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const AssistantScreen(penId: 'pen-a'))));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('disabled language model never submits a chat request',
      (tester) async {
    final api = _Api(available: false);
    await pumpAssistant(tester, api);
    expect(find.text('智能问答尚未启用'), findsOneWidget);
    final send = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '查询并查看依据'));
    expect(send.onPressed, isNull);
    expect(api.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching identity discards delayed answer and its old scope',
      (tester) async {
    final delayed = Completer<AssistantReply>();
    final api = _Api(reply: delayed.future);
    final container = await pumpAssistant(tester, api);
    await tester.enterText(find.byType(TextField), '查询所选栏舍');
    await tester.tap(find.text('查询并查看依据'));
    await tester.pump();
    expect(api.requestedPen, 'pen-a');
    (container.read(authControllerProvider.notifier)
            as CompetitionAuthController)
        .switchTo(competitionAuth(org: 'org-b', offline: true));
    await tester.pump();
    delayed.complete(const AssistantReply(
        status: 'ok', answer: '甲组织旧回答', facts: [], evidence: []));
    await tester.pumpAndSettle();
    expect(find.text('甲组织旧回答'), findsNothing);
    expect(find.textContaining('账号或组织已切换'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
