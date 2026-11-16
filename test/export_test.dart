import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:chai_editor/export/docx_exporter.dart';
import 'package:chai_editor/export/export_model.dart';
import 'package:chai_editor/export/pdf_exporter.dart';
import 'package:chai_editor/markdown_io.dart';
import 'package:chai_editor/theme.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'Kafka sample exports a PDF and a DOCX with valid XML and real styles/lists/tables',
      () async {
    final input = File('samples/kafka-minimum-setup.md').readAsStringSync();
    final model = ExportModel.fromDocument(markdownToEditorDocument(input));
    final pdf = await PdfExporter().export(model);
    expect(ascii.decode(pdf.take(4).toList()), '%PDF');
    expect(pdf.length, greaterThan(10000));
    final docx = DocxExporter().export(model);
    final zip = ZipDecoder().decodeBytes(docx);
    final names = zip.files.map((f) => f.name).toSet();
    expect(
        names,
        containsAll([
          '[Content_Types].xml',
          '_rels/.rels',
          'word/document.xml',
          'word/styles.xml',
          'word/numbering.xml',
          'word/_rels/document.xml.rels'
        ]));
    for (final file in zip.files
        .where((f) => f.name.endsWith('.xml') || f.name.endsWith('.rels'))) {
      final xml = XmlDocument.parse(utf8.decode(file.content));
      expect(xml.rootElement.name.local, isNotEmpty);
    }
    final document = utf8.decode(zip.findFile('word/document.xml')!.content);
    expect(document, contains('w:tbl'));
    expect(document, contains('w:val="Heading1"'));
    expect(document, contains('w:val="Code"'));
    if (const bool.fromEnvironment('CHAI_EXPORT_SAMPLE')) {
      Directory('output/exports').createSync(recursive: true);
      File('output/exports/kafka-minimum-setup.pdf').writeAsBytesSync(pdf);
      File('output/exports/kafka-minimum-setup.docx').writeAsBytesSync(docx);
    }
  });
  test('PDF and Word reuse light token colours and italic multiline comments',
      () async {
    final model = ExportModel.fromDocument(markdownToEditorDocument(
        '```dart\nconst x = 42; /* first\nsecond */\nprint("hi");\n```'));
    final code = model.blocks.single;
    final spans = PdfExporter.codeSpans(code.codeLines.first);
    expect(spans.map((s) => s.text).join(), 'const x = 42; /* first');
    expect(spans.map((s) => s.style?.color),
        contains(PdfColor.fromInt(CodeSyntaxColors.light.keyword.toARGB32())));
    expect(PdfExporter.codeSpans(code.codeLines[1]).first.style?.fontStyle,
        pw.FontStyle.italic);
    final zip = ZipDecoder().decodeBytes(DocxExporter().export(model));
    final xml = XmlDocument.parse(
        utf8.decode(zip.findFile('word/document.xml')!.content));
    final colors =
        xml.findAllElements('w:color').map((e) => e.getAttribute('w:val'));
    expect(colors, containsAll(['CF222E', '0550AE', '6E7781', '0A3069']));
    final comments = xml.findAllElements('w:r').where((r) =>
        r.findAllElements('w:t').any((t) => t.innerText.contains('second */')));
    expect(comments.single.findAllElements('w:i'), isNotEmpty);
    final codeParagraphs = xml.findAllElements('w:p').where((p) => p
        .findAllElements('w:pStyle')
        .any((style) => style.getAttribute('w:val') == 'Code'));
    expect(
        codeParagraphs
            .map((p) => p.findAllElements('w:t').map((t) => t.innerText).join())
            .join('\n'),
        code.text);
    final pdf = await PdfExporter().export(model);
    expect(ascii.decode(pdf.take(4).toList()), '%PDF');
  });
  test('extreme code lines wrap over PDF pages and retain Word text', () async {
    final text = 'x' * 6000;
    final model = ExportModel([
      ExportBlock(
          type: 'code', language: 'dart', runs: [ExportRun(text, const {})])
    ]);
    final pdf = await PdfExporter().export(model);
    expect(pdf.length, greaterThan(1000));
    final zip = ZipDecoder().decodeBytes(DocxExporter().export(model));
    final xml = XmlDocument.parse(
        utf8.decode(zip.findFile('word/document.xml')!.content));
    expect(
        xml.findAllElements('w:t').map((t) => t.innerText).join(), 'dart$text');
  });
  test('DOCX preserves nested formatting, links, XML escapes and Unicode', () {
    final model = ExportModel([
      const ExportBlock(type: 'paragraph', runs: [
        ExportRun('<& " arrows → हिन्दी', {
          'bold': true,
          'italic': true,
          'underline': true,
          'strikethrough': true,
          'href': 'https://example.com/?x=1&y="2"'
        })
      ]),
      const ExportBlock(type: 'bulleted_list', runs: [
        ExportRun('item', {})
      ], children: [
        ExportBlock(type: 'numbered_list', runs: [ExportRun('child', {})])
      ]),
    ]);
    final zip = ZipDecoder().decodeBytes(DocxExporter().export(model));
    for (final file in zip.files) {
      XmlDocument.parse(utf8.decode(file.content));
    }
    final document = XmlDocument.parse(
        utf8.decode(zip.findFile('word/document.xml')!.content));
    expect(document.innerText, contains('<& " arrows → हिन्दी'));
    expect(
        document.findAllElements('w:ilvl').map((e) => e.getAttribute('w:val')),
        contains('1'));
    expect(document.findAllElements('w:hyperlink'), isNotEmpty);
  });
}
