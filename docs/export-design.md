# Export design and verification

Both exporters read a neutral snapshot from ExportModel. Existing Markdown,
code-block and paste implementations are unchanged.

PDF uses A4, 48 pt margins, 10.5 pt Noto Sans, 23/18/14 pt Noto Serif headings,
9 pt Noto Sans Mono code, grey shading/borders and page numbers. Code wraps and
spans pages. Missing local/HTTP images use file names. Fallback fonts carry OFL
notices.

DOCX uses the compact-reference-guide preset with named A4/48 pt/monochrome
and portable-font overrides: Arial 11 pt, line spacing 1.15, 6 pt after; Georgia
headings 21/16/13 pt with 14/11/8 pt before and 8/6/5 pt after; shaded Courier New
9 pt code and 10 pt inline code. Fixed table widths total 9986 DXA; borders are
thin and horizontal cell padding is 5 pt. Styles, nested numbering, links,
whitespace and XML escaping are real OOXML. Images are filename placeholders.

Generate the sample with:

```bash
flutter test test/export_test.dart --dart-define=CHAI_EXPORT_SAMPLE=true
```

Output is in `output/exports/` (gitignored). Tests unzip DOCX and parse all XML and
relationship parts. The sample was opened in Preview and Pages, rasterized with
PDFKit, and all five PDF and four Pages-rendered DOCX pages inspected.
LibreOffice is unavailable; Pages supplied rendering instead of render_docx.py.
