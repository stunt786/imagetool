import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Encodes [image] into standard baseline TIFF 6.0 (uncompressed RGB, little-endian).
///
/// This avoids package:image's TiffEncoder defect where TileWidth/TileLength
/// are written into strip-based IFD and BitsPerSample count is incorrectly set to 1 for RGB.
Uint8List encodeStandardTiff(img.Image image) {
  final rgb = image.numChannels == 3 && !image.hasAlpha
      ? image
      : image.convert(numChannels: 3);

  final width = rgb.width;
  final height = rgb.height;
  const numChannels = 3;
  const bytesPerPixel = 3;
  final imageByteCount = width * height * bytesPerPixel;

  final pixelBytes = Uint8List(imageByteCount);
  int offset = 0;
  for (final pixel in rgb) {
    pixelBytes[offset++] = pixel.r.toInt().clamp(0, 255);
    pixelBytes[offset++] = pixel.g.toInt().clamp(0, 255);
    pixelBytes[offset++] = pixel.b.toInt().clamp(0, 255);
  }

  final bdata = BytesBuilder();

  // Header: 'II' (0x4949), 42 (0x002A), offset to IFD = 8
  final header = ByteData(8);
  header.setUint16(0, 0x4949, Endian.little);
  header.setUint16(2, 42, Endian.little);
  header.setUint32(4, 8, Endian.little);
  bdata.add(header.buffer.asUint8List());

  // IFD entries count: 12 entries
  const numEntries = 12;
  const ifdStart = 8;
  const extraStart = ifdStart + 2 + numEntries * 12 + 4; // 158
  const bitsPerSampleOffset = extraStart; // 158
  const xResOffset = bitsPerSampleOffset + 6; // 164
  const yResOffset = xResOffset + 8; // 172
  const pixelDataOffset = yResOffset + 8; // 180

  final ifd = ByteData(2 + numEntries * 12 + 4);
  int ifdPos = 0;
  ifd.setUint16(ifdPos, numEntries, Endian.little);
  ifdPos += 2;

  void writeEntry(int tag, int type, int count, int valOrOffset) {
    ifd.setUint16(ifdPos, tag, Endian.little);
    ifd.setUint16(ifdPos + 2, type, Endian.little);
    ifd.setUint32(ifdPos + 4, count, Endian.little);
    ifd.setUint32(ifdPos + 8, valOrOffset, Endian.little);
    ifdPos += 12;
  }

  // Tags sorted in ascending order (TIFF 6.0 standard)
  writeEntry(0x0100, 4, 1, width); // ImageWidth
  writeEntry(0x0101, 4, 1, height); // ImageLength
  writeEntry(0x0102, 3, 3, bitsPerSampleOffset); // BitsPerSample [8, 8, 8]
  writeEntry(0x0103, 3, 1, 1); // Compression (1 = uncompressed)
  writeEntry(0x0106, 3, 1, 2); // PhotometricInterpretation (2 = RGB)
  writeEntry(0x0111, 4, 1, pixelDataOffset); // StripOffsets
  writeEntry(0x0115, 3, 1, numChannels); // SamplesPerPixel
  writeEntry(0x0116, 4, 1, height); // RowsPerStrip
  writeEntry(0x0117, 4, 1, imageByteCount); // StripByteCounts
  writeEntry(0x011A, 5, 1, xResOffset); // XResolution
  writeEntry(0x011B, 5, 1, yResOffset); // YResolution
  writeEntry(0x0128, 3, 1, 2); // ResolutionUnit (2 = inch)

  ifd.setUint32(ifdPos, 0, Endian.little); // Next IFD = 0
  bdata.add(ifd.buffer.asUint8List());

  final extra = ByteData(22);
  extra.setUint16(0, 8, Endian.little);
  extra.setUint16(2, 8, Endian.little);
  extra.setUint16(4, 8, Endian.little);
  extra.setUint32(6, 72, Endian.little);
  extra.setUint32(10, 1, Endian.little);
  extra.setUint32(14, 72, Endian.little);
  extra.setUint32(18, 1, Endian.little);
  bdata.add(extra.buffer.asUint8List());

  bdata.add(pixelBytes);

  return bdata.toBytes();
}
