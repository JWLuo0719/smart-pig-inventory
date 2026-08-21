import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/network_status_banner.dart';
import '../../shared/widgets/pen_plate.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          sliver: SliverList.list(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('智慧猪场场主 · F001 示范猪场',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 3),
                        Text('今天先完成现场采集',
                            style: Theme.of(context).textTheme.headlineSmall),
                      ],
                    ),
                  ),
                  Semantics(
                    image: true,
                    label: '智慧猪场场主初版标志',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/branding/smart-pig-farm-owner-logo-v1.png',
                        width: 42,
                        height: 42,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4D8),
                  border: Border.all(color: const Color(0xFFEAD39A)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '页面框架预览 · 当前栏舍、数量和时间均为演示数据',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF684600)),
                ),
              ),
              const SizedBox(height: 16),
              const NetworkStatusBanner(),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: AppColors.barnBlue,
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('继续上次作业',
                        style: TextStyle(
                            color: Color(0xFFB9CFDC),
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    const Text('B01 育肥一栋 · 03栏',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('已保存左、中两张；还需拍摄右侧',
                        style:
                            TextStyle(color: Color(0xFFD9E5EB), fontSize: 12)),
                    const SizedBox(height: 15),
                    FilledButton.icon(
                      onPressed: () => context.push('/pens'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.straw,
                          foregroundColor: AppColors.ink),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('继续拍摄右侧'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _SectionTitle(
                  title: '最近栏舍',
                  action: '选择栏舍',
                  onTap: () => context.push('/pens')),
              const SizedBox(height: 10),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: .92,
            children: <Widget>[
              PenPlate(
                  building: 'B02 育肥二栋',
                  pen: '08栏',
                  state: PenWorkState.confirmed,
                  detail: '08:42 已确认',
                  count: 126,
                  onTap: () {}),
              PenPlate(
                  building: 'B01 育肥一栋',
                  pen: '03栏',
                  state: PenWorkState.queued,
                  detail: '2/3 张已保存',
                  onTap: () => context.push('/pens')),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
          sliver: SliverList.list(
            children: <Widget>[
              const _SectionTitle(title: '今日进度', action: '18 / 42栏'),
              const SizedBox(height: 10),
              const _ProgressCard(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.action, this.onTap});
  final String title;
  final String action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(
                  value: .43,
                  minHeight: 9,
                  color: AppColors.herdTeal,
                  backgroundColor: Color(0xFFE4ECEF)),
            ),
            const SizedBox(height: 15),
            const _ProgressRow(
                label: 'B01 育肥一栋', value: '8 / 16', note: '1 个包待上传'),
            const Divider(height: 22),
            const _ProgressRow(
                label: 'B02 育肥二栋', value: '7 / 14', note: '2 个结果待复核'),
            const Divider(height: 22),
            const _ProgressRow(
                label: 'B03 保育栋', value: '3 / 12', note: '推理已降级'),
          ],
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow(
      {required this.label, required this.value, required this.note});
  final String label;
  final String value;
  final String note;
  @override
  Widget build(BuildContext context) {
    return Row(children: <Widget>[
      Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(note, style: Theme.of(context).textTheme.bodySmall),
          ])),
      Text(value,
          style: const TextStyle(
              fontWeight: FontWeight.w800, color: AppColors.barnBlue)),
    ]);
  }
}
