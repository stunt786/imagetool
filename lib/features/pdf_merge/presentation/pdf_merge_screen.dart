import 'package:flutter/material.dart';

import '../../../shared/services/file_picker_service.dart';
import '../../../shared/widgets/tool_placeholder_screen.dart';

class PdfMergeScreen extends StatelessWidget {
  const PdfMergeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ToolPlaceholderScreen(
      title: 'PDF Merger',
      description:
          'Phase 1 scaffolds the feature module. Phase 5 adds page selection, reordering, and merge export.',
      pickTarget: PickTarget.pdfs,
    );
  }
}

