import 'package:flutter/material.dart';

import '../../../shared/services/file_picker_service.dart';
import '../../../shared/widgets/tool_placeholder_screen.dart';

class FormatConverterScreen extends StatelessWidget {
  const FormatConverterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ToolPlaceholderScreen(
      title: 'Format Converter',
      description:
          'Phase 1 scaffolds the feature module. Phase 3 adds format detection and conversion.',
      pickTarget: PickTarget.images,
    );
  }
}

