import 'package:flutter/material.dart';

import '../../../shared/services/file_picker_service.dart';
import '../../../shared/widgets/tool_placeholder_screen.dart';

class PdfCompressScreen extends StatelessWidget {
  const PdfCompressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ToolPlaceholderScreen(
      title: 'PDF Compressor',
      description:
          'Phase 1 scaffolds the feature module. Phase 4 adds compression presets and offline PDF processing.',
      pickTarget: PickTarget.pdfs,
    );
  }
}

