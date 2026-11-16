import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/properties.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/markdown.dart';

import 'theme.dart';

const codeHighlightLimit = 20000;
const commonCodeLanguages = [
  'dart',
  'java',
  'kotlin',
  'swift',
  'javascript',
  'typescript',
  'python',
  'bash',
  'json',
  'yaml',
  'xml',
  'html',
  'css',
  'sql',
  'properties',
  'go',
  'rust',
  'c',
  'cpp',
  'markdown',
];

String normalizeCodeLanguage(String language) {
  var value = language
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^`{3,}'), '')
      .replaceFirst(RegExp(r'^(language|lang)-'), '')
      .trim();
  value = value.split(RegExp(r'\s+')).first;
  return const {
        'auto': '',
        'sh': 'bash',
        'zsh': 'bash',
        'shell': 'bash',
        'js': 'javascript',
        'jsx': 'javascript',
        'ts': 'typescript',
        'tsx': 'typescript',
        'yml': 'yaml',
        'py': 'python',
        'kt': 'kotlin',
        'golang': 'go',
        'rs': 'rust',
        'c++': 'cpp',
        'h': 'c',
        'hpp': 'cpp',
        'md': 'markdown',
        'htm': 'html',
        'text': 'plaintext',
        'txt': 'plaintext',
      }[value] ??
      value;
}

class CodeToken {
  const CodeToken(this.text, [this.scope = '']);
  final String text;
  final String scope;
  bool get italic => scope.split(RegExp(r'[. ]')).contains('comment');
}

class HighlightedCode {
  const HighlightedCode(this.text, this.tokens, {this.detectedLanguage});
  final String text;
  final List<CodeToken> tokens;

  /// Only exposed when detection has a meaningful lead over the runner-up.
  final String? detectedLanguage;

  TextSpan toTextSpan(TextStyle base,
          {CodeSyntaxColors palette = CodeSyntaxColors.dark}) =>
      TextSpan(
        style: base.copyWith(color: palette.plain),
        children: [
          for (final token in tokens)
            TextSpan(
                text: token.text,
                style: TextStyle(
                    color: palette.forScope(token.scope),
                    fontStyle:
                        token.italic ? FontStyle.italic : FontStyle.normal))
        ],
      );

  /// Split after tokenization, preserving multiline comment/string context.
  List<List<CodeToken>> get lines {
    final result = <List<CodeToken>>[[]];
    for (final token in tokens) {
      final parts = token.text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) result.add([]);
        if (parts[i].isNotEmpty) {
          result.last.add(CodeToken(parts[i], token.scope));
        }
      }
    }
    return result;
  }
}

/// Layout-only wrapping keeps an extreme single line from exceeding a PDF page.
/// Joined output equals the input exactly, including graphemes and tabs.
List<List<CodeToken>> wrapCodeLine(List<CodeToken> tokens, {int columns = 80}) {
  assert(columns > 0);
  final lines = <List<CodeToken>>[[]];
  var width = 0;
  for (final token in tokens) {
    var part = StringBuffer();
    for (final character in token.text.characters) {
      final advance = character == '\t' ? 4 : 1;
      if (width + advance > columns && width > 0) {
        if (part.isNotEmpty) {
          lines.last.add(CodeToken(part.toString(), token.scope));
        }
        part = StringBuffer();
        lines.add([]);
        width = 0;
      }
      part.write(character);
      width += advance;
    }
    if (part.isNotEmpty) {
      lines.last.add(CodeToken(part.toString(), token.scope));
    }
  }
  return lines;
}

/// One tokenizer for the editor, pasteboard and both export formats. The bounded
/// LRU stores text and scopes, never theme-specific spans or document nodes.
class CodeHighlighter {
  CodeHighlighter() {
    _engine.registerLanguages({
      'dart': langDart,
      'java': langJava,
      'kotlin': langKotlin,
      'swift': langSwift,
      'javascript': langJavascript,
      'typescript': langTypescript,
      'python': langPython,
      'bash': langBash,
      'json': langJson,
      'yaml': langYaml,
      'xml': langXml,
      'css': langCss,
      'sql': langSql,
      'properties': langProperties,
      'go': langGo,
      'rust': langRust,
      'c': langC,
      'cpp': langCpp,
      'markdown': langMarkdown,
    });
  }
  static final shared = CodeHighlighter();
  final _engine = Highlight();
  final _cache = <(String, String), HighlightedCode>{};

  HighlightedCode highlight(String text, [String language = '']) {
    final normalized = normalizeCodeLanguage(language);
    if (text.isEmpty || text.length > codeHighlightLimit) {
      return HighlightedCode(text, [CodeToken(text)]);
    }
    final key = (text, normalized);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    var value = HighlightedCode(text, [CodeToken(text)]);
    final grammar = normalized == 'html' ? 'xml' : normalized;
    if (grammar.isEmpty || _engine.getLanguage(grammar) != null) {
      try {
        final HighlightResult result = grammar.isEmpty
            ? _engine.highlightAuto(
                text, commonCodeLanguages.where((e) => e != 'html').toList())
            : _engine.highlight(code: text, language: grammar);
        final renderer = _TokenRenderer();
        result.render(renderer);
        // Cursor offsets depend on exact UTF-16 text preservation. Fail closed.
        if (renderer.tokens.map((e) => e.text).join() == text) {
          String? detected;
          if (result is AutoHighlightResult && result.language != null) {
            final second = result.secondBest?.relevance ?? 0;
            if (result.relevance >= 5 &&
                result.relevance >= second + 2 &&
                result.relevance > second * 1.15) {
              detected = result.language;
            }
          }
          value = HighlightedCode(text, List.unmodifiable(renderer.tokens),
              detectedLanguage: detected);
        }
      } catch (_) {
        // A grammar failure must never interfere with editing or exporting.
      }
    }
    _cache[key] = value;
    if (_cache.length > 64) _cache.remove(_cache.keys.first);
    return value;
  }
}

class _TokenRenderer implements HighlightRenderer {
  final tokens = <CodeToken>[];
  final _scopes = <String>[];
  @override
  void openNode(DataNode node) {
    final parent = _scopes.lastOrNull ?? '';
    final scope = node.scope;
    if (parent.split(RegExp(r'[. ]')).contains('comment')) {
      // Nested doc tags still belong to their italic comment.
      _scopes.add('comment ${scope ?? ''}');
    } else {
      _scopes
          .add(scope == null || scope.startsWith('language:') ? parent : scope);
    }
  }

  @override
  void closeNode(DataNode node) => _scopes.removeLast();
  @override
  void addText(String text) {
    if (text.isNotEmpty) tokens.add(CodeToken(text, _scopes.lastOrNull ?? ''));
  }
}
