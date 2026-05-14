import 'package:flutter/material.dart';

import '../../../shared/services/file_picker_service.dart';
import '../../../shared/widgets/tool_placeholder_screen.dart';

class CollageBuilderScreen extends StatelessWidget {
  const CollageBuilderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ToolPlaceholderScreen(
      title: 'Collage Builder',
      description:
          'Phase 1 scaffolds the feature module. Phase 6 adds grid templates, live preview, and isolate rendering.',
      pickTarget: PickTarget.images,
    );
  }
}

