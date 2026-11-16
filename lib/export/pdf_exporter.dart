import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'export_model.dart';

class PdfExporter {
  static const _fallbackNames = [
    'NotoSansSymbols2',
    'NotoSansDevanagari',
    'NotoSansBengali',
    'NotoSansTamil',
    'NotoSansTelugu',
    'NotoSansGujarati',
    'NotoSansGurmukhi',
    'NotoSansKannada',
    'NotoSansMalayalam',
    'NotoSansOriya'
  ];
  Future<Uint8List> export(ExportModel model) async {
    Future<pw.Font> font(String name) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
    final regular = await font('NotoSans-Regular');
    final bold = await font('NotoSans-Bold');
    final italic = await font('NotoSans-Italic');
    final boldItalic = await font('NotoSans-BoldItalic');
    final serif = await font('NotoSerif-Regular');
    final mono = await font('NotoSansMono-Regular');
    final fallback =
        await Future.wait(_fallbackNames.map((name) => font('$name-Regular')));
    final document = pw.Document(
        theme: pw.ThemeData.withFont(
            base: regular,
            bold: bold,
            italic: italic,
            boldItalic: boldItalic,
            fontFallback: fallback));
    final images = <String, pw.ImageProvider?>{};
    Future<void> loadImages(List<ExportBlock> blocks) async {
      for (final block in blocks) {
        if (block.type == 'image') {
          try {
            Uint8List bytes;
            if (block.image.startsWith('http')) {
              final client = HttpClient()
                ..connectionTimeout = const Duration(seconds: 5);
              try {
                final request = await client.getUrl(Uri.parse(block.image));
                final response =
                    await request.close().timeout(const Duration(seconds: 8));
                if (response.statusCode != 200) {
                  throw const HttpException('Image unavailable');
                }
                final data = BytesBuilder();
                await for (final chunk
                    in response.timeout(const Duration(seconds: 8))) {
                  data.add(chunk);
                  if (data.length > 10 * 1024 * 1024) {
                    throw const HttpException('Image too large');
                  }
                }
                bytes = data.takeBytes();
              } finally {
                client.close(force: true);
              }
            } else {
              bytes = await File(block.image.startsWith('file:')
                      ? Uri.parse(block.image).toFilePath()
                      : block.image)
                  .readAsBytes();
            }
            images[block.image] = pw.MemoryImage(bytes);
          } catch (_) {
            images[block.image] = null;
          }
        }
        await loadImages(block.children);
      }
    }

    await loadImages(model.blocks);
    pw.Widget rich(ExportBlock block,
            {double size = 10.5, pw.Font? fontOverride}) =>
        pw.RichText(
            text: pw.TextSpan(children: [
          for (final run in block.runs)
            pw.TextSpan(
                text: run.text,
                annotation:
                    run.link == null ? null : pw.AnnotationUrl(run.link!),
                style: pw.TextStyle(
                  font: run.has('code') ? mono : fontOverride,
                  fontSize: size,
                  fontWeight: run.has('bold') ? pw.FontWeight.bold : null,
                  fontStyle: run.has('italic') ? pw.FontStyle.italic : null,
                  fontFallback: fallback,
                  background: run.has('code')
                      ? const pw.BoxDecoration(color: PdfColor(.93, .93, .93))
                      : null,
                  decoration: pw.TextDecoration.combine([
                    if (run.has('underline') || run.link != null)
                      pw.TextDecoration.underline,
                    if (run.has('strikethrough')) pw.TextDecoration.lineThrough
                  ]),
                )),
        ]));
    List<pw.Widget> render(List<ExportBlock> blocks, [int depth = 0]) {
      final widgets = <pw.Widget>[];
      var number = 0;
      for (final block in blocks) {
        if (block.type == 'heading') widgets.add(pw.NewPage(freeSpace: 100));
        pw.Widget widget;
        switch (block.type) {
          case 'heading':
            widget = pw.Padding(
                padding: const pw.EdgeInsets.only(top: 12, bottom: 7),
                child: rich(block,
                    size: [23.0, 18.0, 14.0][(block.level - 1).clamp(0, 2)],
                    fontOverride: serif));
          case 'code':
            // Separate wrapped lines can flow over page boundaries.
            widgets.add(pw.Text(block.language,
                style: pw.TextStyle(
                    font: mono, fontSize: 8, color: PdfColors.grey600)));
            for (final line in block.text.split('\n')) {
              widgets.add(pw.Container(
                  width: double.infinity,
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  color: PdfColors.grey100,
                  child: pw.Text(line.isEmpty ? ' ' : line,
                      style: pw.TextStyle(
                          font: mono, fontFallback: fallback, fontSize: 9))));
            }
            widgets.add(pw.SizedBox(height: 8));
            continue;
          case 'table':
            widget = pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
                children: [
                  for (var row = 0; row < block.rows.length; row++)
                    pw.TableRow(
                        decoration: row == 0
                            ? const pw.BoxDecoration(color: PdfColors.grey100)
                            : null,
                        children: [
                          for (final cell in block.rows[row])
                            pw.Padding(
                                padding: const pw.EdgeInsets.all(6),
                                child: rich(cell, size: 9)),
                        ]),
                ]);
          case 'image':
            widget = images[block.image] == null
                ? pw.Text('[Image: ${p.basename(block.image)}]')
                : pw.SizedBox(
                    height: 200,
                    child:
                        pw.Image(images[block.image]!, fit: pw.BoxFit.contain));
          case 'divider':
            widget = pw.Divider(color: PdfColors.grey500);
          case 'quote':
            widget = pw.Container(
                padding: const pw.EdgeInsets.only(left: 12),
                decoration: const pw.BoxDecoration(
                    border: pw.Border(
                        left:
                            pw.BorderSide(color: PdfColors.grey500, width: 2))),
                child: rich(block));
          case 'bulleted_list' || 'numbered_list' || 'todo_list':
            final marker = block.type == 'numbered_list'
                ? '${++number}.'
                : block.type == 'todo_list'
                    ? (block.checked ? '[x]' : '[ ]')
                    : '•';
            widget = pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(width: 24, child: pw.Text(marker)),
                  pw.Expanded(child: rich(block))
                ]);
          default:
            widget = rich(block);
        }
        if (block.type != 'numbered_list') number = 0;
        widgets.add(pw.Padding(
            padding: pw.EdgeInsets.only(left: depth * 16, bottom: 7),
            child: widget));
        widgets.addAll(render(block.children, depth + 1));
      }
      return widgets;
    }

    document.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        maxPages: 1000,
        footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8))),
        build: (_) => render(model.blocks)));
    return document.save();
  }
}
