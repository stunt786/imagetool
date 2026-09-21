#Resize module
** For Resize image module when selecting options (smart, Dimensions, Percent, Presets, Best Fit) , draw a rectangular colored border around the text for active selection.
** Also highlight with colored border for other image size options like presets,Recent, etc for active selection
** Display Estemated size after the tool options are selected for each options and image sizes
**Fix the crop handle bars to properly and smoothly able to crop fro all corners and sides, implement roboust method for it
** Fix the Resize processing speed, it is taking longer for processing. Make it fast using latest updated code
** Image Resize gets already gets while Applying Compression and only Asks for save options(save as new, replace original) on save button, merge this into single functionality as 'Apply compression/Save-> Save ->with the save options dialogue. Remove duplicate save buttons.
** Replace original not functional.
** Smart compression with selected size outputs is compressing slightly higher file sizes for e.g 100kb size-> outputs 102kb, it should be always be smaller 98/99kb not higher.



#PDF Compress
** Enhance PDF Compress using latest and best technology methods. Currently PDF compress with any settings not functional and higher size output as imported PDF. Also provide message if compression is at outmost condition and cannot be further compressed
** Watermark is not implemented for PDF compress feature. Apply watermark functionality to output file for PDF compress
** Output filename should start with pixeltools after original_name

#Merge PDF
** Output filename should start with pixeltools after original_name
** Watermark is not implemented for PDF Merge feature. Apply watermark functionality to output file for PDF compress

#Split PDF
** Watermark is not implemented for PDF Split feature. Apply watermark functionality to output file for PDF Split
** Output filename should start with pixeltools after original_name
**Fix buttom overflow in Split PDF settings and make dynamic for all device sizes

#Convert PDF
** Output filename should start with pixeltools after original_name
** Watermark is not implemented for PDF Split feature. Apply watermark functionality to output file for PDF Split
** Convert PDF ->settings for Resolution is not properly rendered
**PDF to Document convert: Implement feature for complex document preserving tables and other formattings using best and latest approach & also make conversion smooth and faster for non latin documents specially
** PDF conversion for Devagnari fonts is not working as intented, fix it

#Camera Scan Feature
** After Finishing scanning and editing->save as image/save as PDF screen, Also implement option for Done so that the scanned files remain in Files section and later can be exported 
** Enhance Document brightness/contrast, magic delete, flatten,smart fix features. They are not working as intended. 
**Flatten: it is making clean as weavy instead of auto cropping and auto adjusting angles and straightining the page
**Smart Fix: not working as intended and wired results
**Magic remove: it should auto detect extra objects from scanned image like pen, fingers while scanning, etc and try to remove them keeping document look professional
**Filters: Filters are not poorly functional and not as professional as the filters, Use best and updated libraries for it.
**Add Undo/Redo action buttons after changing any on the scanned images

#Files screen
** Implement to display preview of converted PDFs (that used images for image to pdf, scan to pdf). Show image thumbnails in files
** For each files thumbnail scrolling displaying next item of different file, Only show images of respective files only. And display in left/right swap in full screen mode after clicking on the particular file/folder structure.
** For Files via camera scan->display all the image pages in the file preview


