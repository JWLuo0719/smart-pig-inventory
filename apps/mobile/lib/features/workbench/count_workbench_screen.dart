import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/field_header.dart';

class CountWorkbenchScreen extends StatelessWidget {
  const CountWorkbenchScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(
        padding: AppSpacing.page,
        children: [
          const FieldHeader(title: '现场采集', subtitle: '选择栏舍后拍照或导入'),
          const SizedBox(height: 16),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(children: [
                        Icon(Icons.camera_alt_outlined,
                            color: AppColors.barnBlue),
                        SizedBox(width: 10),
                        Expanded(
                            child: Text('开始一栏盘点',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800))),
                      ]),
                      const SizedBox(height: 12),
                      const Text('确认栏舍 → 拍摄或导入 → 保存并上传',
                          style: TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                          onPressed: () => context.push('/pens'),
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: const Text('选择栏舍并开始')),
                    ],
                  ))),
          const SizedBox(height: 12),
          ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('已保存与待上传'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/outbox')),
          const Divider(),
          const ExpansionTile(
              title: Text('拍摄提示'),
              leading: Icon(Icons.help_outline),
              children: [
                Text('拍全本栏，尽量排除邻栏。料槽遮挡时换角度补拍。断网先保存，联网后上传；左中右照片不会直接相加。'),
              ]),
        ],
      );
}
