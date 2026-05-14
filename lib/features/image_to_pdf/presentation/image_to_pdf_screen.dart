import 'package:flutter/material.dart';

import '../../../shared/services/file_picker_service.dart';
import '../../../shared/widgets/tool_placeholder_screen.dart';

class ImageToPdfScreen extends StatelessWidget {
  const ImageToPdfScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ToolPlaceholderScreen(
      title: 'Image to PDF',
      description:
          'Phase 1 scaffolds the feature module. Phase 4 adds PDF creation with page sizing and orientation.',
      pickTarget: PickTarget.images,
    );
  }
}

