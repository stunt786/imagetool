import 'package:flutter/material.dart';

import '../../../shared/services/file_picker_service.dart';
import '../../../shared/widgets/tool_placeholder_screen.dart';

class PdfSplitScreen extends StatelessWidget {
  const PdfSplitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ToolPlaceholderScreen(
      title: 'PDF Splitter',
      description:
          'Phase 1 scaffolds the feature module. Phase 5 adds split modes, naming tokens, and ZIP export.',
      pickTarget: PickTarget.pdfs,
    );
  }
}

