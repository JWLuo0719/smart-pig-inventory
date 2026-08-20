# 测试数据资产

此目录只保存测试数据的**规则、脚本和说明**，不保存猪场原图、标注、权重或用户上传媒体。

## 当前来源

开发环境可从外部 `agent-base/dataset` 目录生成一份本地清单。该数据集是 YOLO 检测研究数据，包含 `train`、`val`、`test` 三个划分；它不是现场盘点的业务金标，也不能被视为已获得产品分发授权。

运行：

```powershell
$datasetRoot = Get-ChildItem -LiteralPath D:\Project -Directory | ForEach-Object {
  $candidate = Join-Path $_.FullName 'agent-base\dataset'
  if (Test-Path -LiteralPath $candidate) { $candidate }
} | Select-Object -First 1
python scripts/build_test_dataset_manifest.py --source $datasetRoot
```

脚本只读取来源文件，生成 `test-assets/generated/yolo-source-manifest.json`。该输出被 Git 忽略，包含文件 SHA-256、YOLO 标注推导的猪只数量、配对完整性问题和候选夹具索引。

## 使用边界

- 产品单元测试优先使用合成图、模拟响应和手写元数据。
- 只有得到数据权利人书面授权后，才能在本地把候选图用于开发演示或端到端手工验证。
- 不得把原图、标签、绝对路径、缩略图或模型权重加入 Git、Docker 镜像或 CI 工件。
- 真正的推理金标集必须单独版本化，记录来源、授权、标注审查、ROI 规则和模型基准；不得直接复用训练/验证划分作为上线结论。
