import 'package:chai_editor/markdown_io.dart';
import 'package:flutter_test/flutter_test.dart';

// Run with: flutter test
void main() {
  test('paragraphs keep a blank line between them', () {
    const input = 'First paragraph.\n\nSecond paragraph.\n';
    final doc = markdownToEditorDocument(input);
    expect(editorDocumentToMarkdown(doc), input);
  });

  test('headings, lists and code blocks survive a round trip', () {
    const input = '# Title\n'
        '\n'
        'Intro text.\n'
        '\n'
        '- one\n'
        '- two\n'
        '\n'
        '1. first\n'
        '2. second\n'
        '\n'
        '```bash\n'
        'docker run -d --name kafka -p 9092:9092 apache/kafka:4.4.0\n'
        '```\n';
    final doc = markdownToEditorDocument(input);
    expect(editorDocumentToMarkdown(doc), input);
  });
}
