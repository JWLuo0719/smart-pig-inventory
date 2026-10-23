/// User-facing names only; persisted and HTTP direction identifiers stay intact.
String evidencePositionLabel(String position) => switch (position) {
      'left' => '左图',
      'center' => '中图',
      'right' => '右图',
      'single' => '单图',
      'video' => '视频',
      _ => '原图',
    };
