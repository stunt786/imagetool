import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/operation_folder.dart';

/// Interactive AI Assistant sheet shown when tapping `✦ Ask AI` in an
/// operation folder (matching the `prev.jpg` reference).
class AiDocumentAssistantSheet extends StatefulWidget {
  const AiDocumentAssistantSheet({
    super.key,
    required this.operation,
    required this.files,
  });

  final OperationFolder operation;
  final List<AppFileItem> files;

  static Future<void> show(
    BuildContext context, {
    required OperationFolder operation,
    required List<AppFileItem> files,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiDocumentAssistantSheet(
        operation: operation,
        files: files,
      ),
    );
  }

  @override
  State<AiDocumentAssistantSheet> createState() =>
      _AiDocumentAssistantSheetState();
}

class _AiDocumentAssistantSheetState extends State<AiDocumentAssistantSheet> {
  bool _isProcessing = false;
  String _status = '';
  final Map<int, String> _extractedPages = {};
  String _fullText = '';
  int _activeTab = 0; // 0: OCR, 1: Key Info / Summary, 2: Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _startExtraction();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startExtraction() async {
    setState(() {
      _isProcessing = true;
      _status = 'Analyzing document pages...';
    });

    final imageFiles = widget.files
        .where((f) =>
            f.isImage ||
            f.path.toLowerCase().endsWith('.jpg') ||
            f.path.toLowerCase().endsWith('.jpeg') ||
            f.path.toLowerCase().endsWith('.png') ||
            f.path.toLowerCase().endsWith('.webp'))
        .toList();

    TextRecognizer? recognizer;
    try {
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    } catch (_) {
      // ML Kit may not be supported on some test environments
    }

    final buffer = StringBuffer();

    try {
      for (int i = 0; i < imageFiles.length; i++) {
        if (!mounted) break;
        final file = imageFiles[i];
        setState(() {
          _status = 'Reading page ${i + 1} of ${imageFiles.length}...';
        });

        String pageText = '';
        if (recognizer != null && await File(file.path).exists()) {
          try {
            final inputImage = InputImage.fromFile(File(file.path));
            final result = await recognizer.processImage(inputImage);
            pageText = result.text.trim();
          } catch (_) {
            pageText = '';
          }
        }

        if (pageText.isEmpty) {
          pageText = '[Page ${i + 1}: ${file.fileName}]';
        }

        _extractedPages[i] = pageText;
        buffer.writeln('--- Page ${i + 1} (${file.fileName}) ---');
        buffer.writeln(pageText);
        buffer.writeln();
      }
    } finally {
      try {
        await recognizer?.close();
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _fullText = buffer.toString().trim();
        if (_fullText.isEmpty) {
          _fullText = 'No readable text detected in this folder.';
        }
      });
    }
  }

  void _copyAll() {
    if (_fullText.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _fullText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Extracted text copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareText() {
    if (_fullText.isEmpty) return;
    Share.share(_fullText, subject: '${widget.operation.displayName} - Extracted Text');
  }

  Map<String, List<String>> _analyzeSummary() {
    final dates = <String>{};
    final emails = <String>{};
    final amounts = <String>{};

    final dateRegex = RegExp(r'\b(?:\d{1,4}[-/\.]\d{1,2}[-/\.]\d{1,4}|\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{1,2},? \d{4})\b', caseSensitive: false);
    final emailRegex = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    final amountRegex = RegExp(r'(?:Rs\.?|\$|€|£|INR)\s?[\d,]+(?:\.\d{2})?|\b[\d,]+(?:\.\d{2})?\s?(?:USD|EUR|GBP|NPR|INR)\b');

    for (final match in dateRegex.allMatches(_fullText)) {
      if (match.group(0) != null) dates.add(match.group(0)!);
    }
    for (final match in emailRegex.allMatches(_fullText)) {
      if (match.group(0) != null) emails.add(match.group(0)!);
    }
    for (final match in amountRegex.allMatches(_fullText)) {
      if (match.group(0) != null) amounts.add(match.group(0)!);
    }

    return {
      'Dates': dates.take(6).toList(),
      'Emails & Contacts': emails.take(6).toList(),
      'Financial / Amounts': amounts.take(6).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222A) : scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ask AI - Document Assistant',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : scheme.onSurface,
                        ),
                      ),
                      Text(
                        '${widget.files.length} file(s) · ML Kit Optical Recognition',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Navigation Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _buildTabChip(0, 'Extracted Text', Icons.text_snippet_outlined),
                const SizedBox(width: 8),
                _buildTabChip(1, 'Key Insights', Icons.insights_rounded),
                const SizedBox(width: 8),
                _buildTabChip(2, 'Search', Icons.search_rounded),
              ],
            ),
          ),

          const Divider(height: 16, color: Colors.white12),

          // Content
          Expanded(
            child: _isProcessing
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF00E5FF),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _status,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  )
                : _buildTabBody(theme, scheme),
          ),

          // Bottom Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF171A21) : scheme.surfaceContainerHighest,
              border: const Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00E5FF),
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _fullText.isEmpty ? null : _copyAll,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy Text'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _fullText.isEmpty ? null : _shareText,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text(
                      'Share Text',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(int index, String label, IconData icon) {
    final active = _activeTab == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _activeTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF00E5FF).withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? const Color(0xFF00E5FF) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: active ? const Color(0xFF00E5FF) : Colors.white60,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? const Color(0xFF00E5FF) : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBody(ThemeData theme, ColorScheme scheme) {
    switch (_activeTab) {
      case 0:
        return _buildExtractedTextList(theme);
      case 1:
        return _buildSummaryTab(theme, scheme);
      case 2:
        return _buildSearchTab(theme, scheme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildExtractedTextList(ThemeData theme) {
    if (_extractedPages.isEmpty) {
      return const Center(child: Text('No pages detected.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _extractedPages.length,
      itemBuilder: (context, index) {
        final text = _extractedPages[index] ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Page ${(index + 1).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00E5FF),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    tooltip: 'Copy page text',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Page ${index + 1} copied!'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryTab(ThemeData theme, ColorScheme scheme) {
    final insights = _analyzeSummary();
    final wordCount = _fullText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF00E5FF).withValues(alpha: 0.12),
                const Color(0xFF2979FF).withValues(alpha: 0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metric('Pages', '${_extractedPages.length}'),
              _metric('Words', '$wordCount'),
              _metric('Characters', '${_fullText.length}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final entry in insights.entries)
          if (entry.value.isNotEmpty) ...[
            Text(
              entry.key,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF00E5FF),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            ...entry.value.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_right_rounded,
                        color: Color(0xFF00E5FF), size: 20),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Color(0xFF00E5FF),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildSearchTab(ThemeData theme, ColorScheme scheme) {
    final matches = <(int, String)>[];
    if (_searchQuery.trim().isNotEmpty) {
      for (final entry in _extractedPages.entries) {
        final lines = entry.value.split('\n');
        for (final line in lines) {
          if (line.toLowerCase().contains(_searchQuery.toLowerCase())) {
            matches.add((entry.key + 1, line.trim()));
          }
        }
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search keyword across pages...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00E5FF)),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        Expanded(
          child: _searchQuery.isEmpty
              ? const Center(
                  child: Text(
                    'Type a keyword to search across all pages.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : matches.isEmpty
                  ? Center(
                      child: Text(
                        'No matches found for "$_searchQuery".',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final (page, line) = matches[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Page $page',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00E5FF),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                line,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
