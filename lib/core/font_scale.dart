/// 字号档位（放在 core 里，界面和状态层都要用，别让它俩互相依赖）
library;

const List<({String id, String name, double scale})> kFontScales = [
  (id: 'small', name: '小', scale: 0.95),
  (id: 'normal', name: '标准', scale: 1.08),
  (id: 'large', name: '大', scale: 1.22),
  (id: 'huge', name: '特大', scale: 1.38),
];

double fontScaleOf(String id) {
  for (final s in kFontScales) {
    if (s.id == id) return s.scale;
  }
  return 1.08;
}

String fontScaleName(String id) {
  for (final s in kFontScales) {
    if (s.id == id) return s.name;
  }
  return '标准';
}
