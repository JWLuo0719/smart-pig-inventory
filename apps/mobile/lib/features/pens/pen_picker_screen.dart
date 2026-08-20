import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

class PenPickerScreen extends StatelessWidget {
  const PenPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('选择栏舍')),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: <Widget>[
            TextField(
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: '输入栋舍或栏舍编码',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.line)))),
            const SizedBox(height: 14),
            Text('最近使用', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _PenChoice(
                building: 'B01 育肥一栋',
                pen: '03栏',
                note: '有未完成三图草稿',
                onTap: () => context.go('/capture')),
            const SizedBox(height: 10),
            _PenChoice(
                building: 'B02 育肥二栋',
                pen: '08栏',
                note: '今日已确认 126头',
                onTap: () => context.go('/capture')),
            const SizedBox(height: 20),
            Text('全部栏舍', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _PenChoice(
                building: 'B03 保育栋',
                pen: '05栏',
                note: '今天未开始',
                onTap: () => context.go('/capture')),
          ]),
    );
  }
}

class _PenChoice extends StatelessWidget {
  const _PenChoice(
      {required this.building,
      required this.pen,
      required this.note,
      required this.onTap});
  final String building;
  final String pen;
  final String note;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Card(
        child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
            onTap: onTap,
            leading: Container(
                width: 42,
                height: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: AppColors.barnBlue,
                    borderRadius: BorderRadius.only(
                        topRight: Radius.circular(10),
                        bottomLeft: Radius.circular(10))),
                child: Text(pen.replaceAll('栏', ''),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800))),
            title: Text('$building · $pen',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(note),
            trailing: const Icon(Icons.chevron_right)));
  }
}
