import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:chai_editor/export/docx_exporter.dart';
import 'package:chai_editor/export/export_model.dart';
import 'package:chai_editor/export/pdf_exporter.dart';
import 'package:chai_editor/markdown_io.dart';
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
