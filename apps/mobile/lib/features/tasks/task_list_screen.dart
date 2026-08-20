import 'package:flutter/material.dart';

import '../../shared/widgets/network_status_banner.dart';
import '../../shared/widgets/pen_plate.dart';

class TaskListScreen extends StatelessWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: const <Widget>[
        Text('盘点任务',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('按任务推进栋舍和栏舍，不用在现场记住上传状态。'),
        SizedBox(height: 10),
        Text('页面框架预览 · 以下均为演示数据',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF805800))),
        SizedBox(height: 16),
        NetworkStatusBanner(),
        SizedBox(height: 18),
        PenPlate(
            building: 'B01 育肥一栋',
            pen: '03栏',
            state: PenWorkState.queued,
            detail: '右侧照片待补拍'),
        SizedBox(height: 10),
        PenPlate(
            building: 'B02 育肥二栋',
            pen: '12栏',
            state: PenWorkState.review,
            detail: '疑似跨图重复，等待复核',
            count: 118),
        SizedBox(height: 10),
        PenPlate(
            building: 'B03 保育栋',
            pen: '05栏',
            state: PenWorkState.failed,
            detail: '没有生成数量，原图已保存'),
      ],
    );
  }
}
