## Splash Screen
- update splash screen background color to light color that match device light mode and dark color to match dark mode.

## Files page
- From Files modify tools for Images, collage feature-> after collage completion, the screen is taking to collage builder instead to files page where merge operation was being processed from.
- The successful message for crop, filters, resize, convert, To pdf, compress, split: After operation is completed the message should be auto destroyed after 2-3 seconds, it is not dismissing and have to manually dismiss messages.
- For PDF files: Add additional settings for PDF related pages in files. Options for custom pages to save_>save pages as Images
- Compress PDF & Split : Additional options for split and compress as in the respected modules.
- Remove 'Ask AI' option in files->preview pages

## NAming of exported files
- All exported images, PDFs,and other formats should contain 'pixeltools' prefix name in all files.

## Compress PDF
- Replace message for PDFs that cannot be compressed further with just "Already compressed at highest level" message 

## Navigation Fix
- Fix the navigation clicks for different tools not working after back and fourth clicks in different pages or modules, find which pages is causing the issue.

## Camera Module
- Remove duplicate filter/Enhance options from camera/scan->after page is scanned. I think the options for smart fix and flatten are duplicate in multiple areas
- Improve Smart Fix & Magic clean features more smartly. Update with smartcode to detect objects and text and background and clean objects while matching background.