import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'export_model.dart';

/// Compact reference layout; A4/48pt and monochrome override the document preset.
class DocxExporter {
  Uint8List export(ExportModel model) {
    String text(String value) =>
        XmlText(value.replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), ''))
            .toXmlString();
    String attr(String value) =>
        const HtmlEscape(HtmlEscapeMode.attribute).convert(value);
    final relationships = <String>[];
    var relation = 0;
    var nextNumber = 2;
    final numberIds = <int>[];
    String runs(List<ExportRun> input) => input.map((run) {
          final props =
              '<w:rPr>${run.has('bold') ? '<w:b/>' : ''}${run.has('italic') ? '<w:i/>' : ''}${run.has('underline') ? '<w:u w:val="single"/>' : ''}${run.has('strikethrough') ? '<w:strike/>' : ''}${run.has('code') ? '<w:rStyle w:val="InlineCode"/>' : ''}${run.link != null ? '<w:rStyle w:val="Hyperlink"/>' : ''}</w:rPr>';
          final content = run.text
              .split('\n')
              .map((line) => '<w:t xml:space="preserve">${text(line)}</w:t>')
              .join('<w:br/>');
          final value = '<w:r>$props$content</w:r>';
          if (run.link == null) return value;
          final id = 'link${++relation}';
          relationships.add(
              '<Relationship Id="$id" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="${attr(run.link!)}" TargetMode="External"/>');
          return '<w:hyperlink r:id="$id">$value</w:hyperlink>';
        }).join();
    String paragraph(String content,
            {String style = 'Normal',
            int? num,
            int depth = 0,
            bool divider = false}) =>
        '<w:p><w:pPr><w:pStyle w:val="$style"/>${num == null ? '' : '<w:numPr><w:ilvl w:val="${depth.clamp(0, 8)}"/><w:numId w:val="$num"/></w:numPr>'}${divider ? '<w:pBdr><w:bottom w:val="single" w:sz="4" w:color="999999"/></w:pBdr>' : ''}</w:pPr>$content</w:p>';
    String render(List<ExportBlock> blocks, [int depth = 0]) {
      final out = StringBuffer();
      int? numberId;
      for (final block in blocks) {
        if (block.type != 'numbered_list') numberId = null;
        if (block.type == 'table') {
          final cols = block.rows.isEmpty ? 1 : block.rows.first.length;
          final width = 9986 ~/ cols;
          out.write(
              '<w:tbl><w:tblPr><w:tblW w:w="${width * cols}" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders>${[
            'top',
            'left',
            'bottom',
            'right',
            'insideH',
            'insideV'
          ].map((side) => '<w:$side w:val="single" w:sz="4" w:color="AAAAAA"/>').join()}</w:tblBorders><w:tblCellMar><w:top w:w="80" w:type="dxa"/><w:left w:w="100" w:type="dxa"/><w:bottom w:w="80" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>${List.filled(cols, '<w:gridCol w:w="$width"/>').join()}</w:tblGrid>');
          for (var row = 0; row < block.rows.length; row++) {
            out.write(
                '<w:tr>${row == 0 ? '<w:trPr><w:tblHeader/></w:trPr>' : ''}');
            for (final cell in block.rows[row]) {
              out.write(
                  '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/>${row == 0 ? '<w:shd w:fill="F1F1F1"/>' : ''}</w:tcPr>${paragraph(runs(cell.runs))}</w:tc>');
            }
            out.write('</w:tr>');
          }
          out.write('</w:tbl>');
        } else if (block.type == 'code') {
          if (block.language.isNotEmpty) {
            out.write(paragraph('<w:r><w:t>${text(block.language)}</w:t></w:r>',
                style: 'CodeLabel'));
          }
          for (final line in block.text.split('\n')) {
            out.write(paragraph(
                '<w:r><w:t xml:space="preserve">${text(line.isEmpty ? ' ' : line)}</w:t></w:r>',
                style: 'Code'));
          }
        } else if (block.type == 'image') {
          out.write(paragraph(
              '<w:r><w:t>${text('[Image: ${block.image.split('/').last}]')}</w:t></w:r>'));
        } else {
          int? num;
          if (block.type == 'numbered_list') {
            if (numberId == null) {
              numberId = nextNumber++;
              numberIds.add(numberId);
            }
            num = numberId;
          } else if (block.type == 'bulleted_list' ||
              block.type == 'todo_list') {
            num = 1;
          }
          final prefix = block.type == 'todo_list'
              ? '<w:r><w:t xml:space="preserve">${block.checked ? '[x] ' : '[ ] '}</w:t></w:r>'
              : '';
          out.write(paragraph('$prefix${runs(block.runs)}',
              style: block.type == 'heading'
                  ? 'Heading${block.level.clamp(1, 3)}'
                  : block.type == 'quote'
                      ? 'Quote'
                      : 'Normal',
              num: num,
              depth: depth,
              divider: block.type == 'divider'));
        }
        out.write(render(block.children, depth + 1));
      }
      return out.toString();
    }

    final body = render(model.blocks);
    const header = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    final parts = <String, String>{
      '[Content_Types].xml':
          '$header<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>${{
        'document': 'document.main',
        'styles': 'styles',
        'numbering': 'numbering'
      }.entries.map((e) => '<Override PartName="/word/${e.key}.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.${e.value}+xml"/>').join()}</Types>',
      '_rels/.rels':
          '$header<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="document" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      'word/document.xml':
          '$header<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="960" w:right="960" w:bottom="960" w:left="960" w:header="480" w:footer="480"/></w:sectPr></w:body></w:document>',
      'word/_rels/document.xml.rels':
          '$header<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="styles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="numbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>${relationships.join()}</Relationships>',
      'word/styles.xml':
          '$header<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">${_styles()}</w:styles>',
      'word/numbering.xml':
          '$header<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">${_abstract(0, false)}${_abstract(1, true)}<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>${numberIds.map((id) => '<w:num w:numId="$id"><w:abstractNumId w:val="1"/><w:lvlOverride w:ilvl="0"><w:startOverride w:val="1"/></w:lvlOverride></w:num>').join()}</w:numbering>',
    };
    final archive = Archive();
    for (final entry in parts.entries) {
      archive.addFile(ArchiveFile.string(entry.key, entry.value));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  String _abstract(int id, bool numbered) =>
      '<w:abstractNum w:abstractNumId="$id"><w:multiLevelType w:val="multilevel"/>${List.generate(9, (level) => '<w:lvl w:ilvl="$level"><w:start w:val="1"/><w:numFmt w:val="${numbered ? 'decimal' : 'bullet'}"/><w:lvlText w:val="${numbered ? '%${level + 1}.' : '•'}"/><w:lvlJc w:val="left"/><w:pPr><w:tabs><w:tab w:val="num" w:pos="${360 * (level + 1)}"/></w:tabs><w:ind w:left="${360 * (level + 1)}" w:hanging="240"/></w:pPr></w:lvl>').join()}</w:abstractNum>';
  String _styles() {
    String style(String id, String name, String font, int size,
            {int before = 0,
            int after = 120,
            bool italic = false,
            bool code = false}) =>
        '<w:style w:type="paragraph" w:styleId="$id"${id == 'Normal' ? ' w:default="1"' : ''}><w:name w:val="$name"/>${id == 'Normal' ? '' : '<w:basedOn w:val="Normal"/>'}<w:pPr><w:spacing w:before="$before" w:after="$after" w:line="276" w:lineRule="auto"/>${id.startsWith('Heading') ? '<w:keepNext/><w:outlineLvl w:val="${int.parse(id.substring(7)) - 1}"/>' : ''}${code ? '<w:shd w:fill="F1F1F1"/><w:ind w:left="120" w:right="120"/>' : ''}${id == 'Quote' ? '<w:ind w:left="300"/><w:pBdr><w:left w:val="single" w:sz="12" w:space="8" w:color="999999"/></w:pBdr>' : ''}</w:pPr><w:rPr><w:rFonts w:ascii="$font" w:hAnsi="$font" w:cs="Noto Sans Devanagari"/><w:sz w:val="$size"/><w:color w:val="111111"/>${italic ? '<w:i/>' : ''}</w:rPr></w:style>';
    return '${style('Normal', 'Normal', 'Arial', 22)}${style('Heading1', 'heading 1', 'Georgia', 42, before: 280, after: 160)}${style('Heading2', 'heading 2', 'Georgia', 32, before: 220, after: 120)}${style('Heading3', 'heading 3', 'Georgia', 26, before: 160, after: 100)}${style('Quote', 'Quote', 'Arial', 22, italic: true)}${style('Code', 'Code', 'Courier New', 18, after: 0, code: true)}${style('CodeLabel', 'Code Label', 'Courier New', 16, before: 140, after: 40)}<w:style w:type="character" w:styleId="InlineCode"><w:name w:val="Inline Code"/><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/><w:shd w:fill="EEEEEE"/><w:sz w:val="20"/></w:rPr></w:style><w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="111111"/><w:u w:val="single"/></w:rPr></w:style>';
  }
}
