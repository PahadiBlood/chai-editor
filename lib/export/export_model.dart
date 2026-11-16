import 'package:appflowy_editor/appflowy_editor.dart';

class ExportRun {
  const ExportRun(this.text, this.attributes);
  final String text;
  final Map<String, dynamic> attributes;
  bool has(String name) => attributes[name] == true;
  String? get link => attributes['href'] as String?;
}

class ExportBlock {
  const ExportBlock(
      {required this.type,
      this.runs = const [],
      this.children = const [],
      this.rows = const [],
      this.level = 1,
      this.checked = false,
      this.language = '',
      this.image = ''});
  final String type;
  final List<ExportRun> runs;
  final List<ExportBlock> children;
  final List<List<ExportBlock>> rows;
  final int level;
  final bool checked;
  final String language;
  final String image;
  String get text => runs.map((run) => run.text).join();
}

class ExportModel {
  ExportModel(this.blocks);
  final List<ExportBlock> blocks;
  factory ExportModel.fromDocument(Document document) =>
      ExportModel(document.root.children.map(_block).toList());
  static ExportBlock _block(Node node) {
    final runs = node.delta
            ?.toJson()
            .where((op) => op['insert'] is String)
            .map((op) => ExportRun(op['insert'] as String,
                Map<String, dynamic>.from(op['attributes'] as Map? ?? {})))
            .toList() ??
        <ExportRun>[];
    final rows = <List<ExportBlock>>[];
    if (node.type == 'table') {
      final table = TableNode(node: node);
      final cols = node.attributes[TableBlockKeys.colsLen] as int? ?? 0;
      final height = node.attributes[TableBlockKeys.rowsLen] as int? ?? 0;
      for (var row = 0; row < height; row++) {
        rows.add([
          for (var col = 0; col < cols; col++)
            _block(table.getCell(col, row).children.first)
        ]);
      }
    }
    return ExportBlock(
        type: node.type,
        runs: runs,
        children:
            node.type == 'table' ? [] : node.children.map(_block).toList(),
        rows: rows,
        level: node.attributes['level'] as int? ?? 1,
        checked: node.attributes['checked'] == true,
        language: node.attributes['language'] as String? ?? '',
        image: node.attributes['url'] as String? ?? '');
  }
}
