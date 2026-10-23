package com.smartfarm.inventory.inventory.thumbnail;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Iterator;
import java.util.zip.CRC32;
import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageReadParam;
import javax.imageio.ImageReader;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.MemoryCacheImageInputStream;
import javax.imageio.stream.MemoryCacheImageOutputStream;
import org.springframework.stereotype.Component;

/** Independent preview codec. Never changes original bytes or detection coordinate semantics. */
@Component
public class ThumbnailCodec {
    public static final int MAX_SOURCE_BYTES = 20 * 1024 * 1024;
    public static final long MAX_SOURCE_PIXELS = 40_000_000L;
    public static final int MAX_SOURCE_DIMENSION = 20_000;
    public static final int MAX_EDGE = 320;
    public static final int MAX_THUMBNAIL_BYTES = 512 * 1024;
    private static final int DECODE_EDGE = 640;

    public byte[] create(InputStream source, String contentType) throws IOException {
        if (!supported(contentType)) throw ThumbnailException.unsupported();
        byte[] bytes = readBounded(source, MAX_SOURCE_BYTES);
        if (bytes.length == 0) throw ThumbnailException.unsupported();
        if ("image/jpeg".equals(contentType) && (bytes.length < 4
                || (bytes[bytes.length - 2] & 255) != 255 || (bytes[bytes.length - 1] & 255) != 217)) {
            throw ThumbnailException.unsupported();
        }
        try (var input = new MemoryCacheImageInputStream(new ByteArrayInputStream(bytes))) {
            Iterator<ImageReader> readers = ImageIO.getImageReaders(input);
            if (!readers.hasNext()) throw ThumbnailException.unsupported();
            ImageReader reader = readers.next();
            try {
                String format = reader.getFormatName();
                if (!("image/jpeg".equals(contentType) && "JPEG".equalsIgnoreCase(format))
                        && !("image/png".equals(contentType) && "PNG".equalsIgnoreCase(format))) {
                    throw ThumbnailException.unsupported();
                }
                reader.setInput(input, true, true);
                int width = reader.getWidth(0), height = reader.getHeight(0);
                validateDimensions(width, height);
                int orientation = "image/jpeg".equals(contentType) ? jpegOrientation(bytes) : pngOrientation(bytes);
                int sampling = Math.max(1, (Math.max(width, height) + DECODE_EDGE - 1) / DECODE_EDGE);
                ImageReadParam parameters = reader.getDefaultReadParam();
                parameters.setSourceSubsampling(sampling, sampling, 0, 0);
                BufferedImage decoded = reader.read(0, parameters);
                if (decoded == null || decoded.getWidth() > DECODE_EDGE || decoded.getHeight() > DECODE_EDGE) {
                    throw ThumbnailException.unsupported();
                }
                BufferedImage oriented = orient(decoded, orientation);
                double scale = Math.min(1d, (double) MAX_EDGE / Math.max(oriented.getWidth(), oriented.getHeight()));
                int outWidth = Math.max(1, (int) Math.round(oriented.getWidth() * scale));
                int outHeight = Math.max(1, (int) Math.round(oriented.getHeight() * scale));
                BufferedImage preview = new BufferedImage(outWidth, outHeight, BufferedImage.TYPE_INT_RGB);
                Graphics2D graphics = preview.createGraphics();
                try {
                    graphics.setColor(Color.WHITE);
                    graphics.fillRect(0, 0, outWidth, outHeight);
                    graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
                    graphics.drawImage(oriented, 0, 0, outWidth, outHeight, null);
                } finally { graphics.dispose(); }
                return encode(preview);
            } catch (ThumbnailException exception) {
                throw exception;
            } catch (IOException | RuntimeException exception) {
                // The input has already been read: codec errors are unsupported/corrupt media, not storage failures.
                throw ThumbnailException.unsupported();
            } finally { reader.dispose(); }
        }
    }

    public boolean validCached(byte[] bytes) {
        if (bytes.length < 4 || bytes.length > MAX_THUMBNAIL_BYTES) return false;
        try (var input = new MemoryCacheImageInputStream(new ByteArrayInputStream(bytes))) {
            Iterator<ImageReader> readers = ImageIO.getImageReaders(input);
            if (!readers.hasNext()) return false;
            ImageReader reader = readers.next();
            try {
                if (!"JPEG".equalsIgnoreCase(reader.getFormatName())) return false;
                reader.setInput(input, true, true);
                int width = reader.getWidth(0), height = reader.getHeight(0);
                if (width < 1 || height < 1 || width > MAX_EDGE || height > MAX_EDGE) return false;
                BufferedImage decoded = reader.read(0);
                return decoded != null && (bytes[bytes.length - 2] & 255) == 255
                        && (bytes[bytes.length - 1] & 255) == 217;
            } finally { reader.dispose(); }
        } catch (IOException | RuntimeException exception) { return false; }
    }

    public static boolean supported(String contentType) {
        return "image/jpeg".equals(contentType) || "image/png".equals(contentType);
    }

    static byte[] readBounded(InputStream input, int maximum) throws IOException {
        byte[] bytes = input.readNBytes(maximum + 1);
        if (bytes.length > maximum) throw ThumbnailException.unsupported();
        return bytes;
    }

    static void validateDimensions(int width, int height) {
        if (width < 1 || height < 1 || width > MAX_SOURCE_DIMENSION || height > MAX_SOURCE_DIMENSION
                || (long) width * height > MAX_SOURCE_PIXELS) throw ThumbnailException.unsupported();
    }

    private byte[] encode(BufferedImage image) throws IOException {
        ImageWriter writer = ImageIO.getImageWritersByFormatName("JPEG").next();
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (var output = new MemoryCacheImageOutputStream(bytes)) {
            writer.setOutput(output);
            ImageWriteParam parameters = writer.getDefaultWriteParam();
            parameters.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
            parameters.setCompressionQuality(0.82f);
            writer.write(null, new IIOImage(image, null, null), parameters);
            output.flush();
        } finally { writer.dispose(); }
        if (bytes.size() > MAX_THUMBNAIL_BYTES) throw ThumbnailException.unsupported();
        return bytes.toByteArray();
    }

    /** Reads only the inline orientation SHORT in IFD0; no vendor code or metadata dependency. */
    static int jpegOrientation(byte[] bytes) {
        if (bytes.length < 4 || (bytes[0] & 255) != 255 || (bytes[1] & 255) != 216) {
            throw ThumbnailException.unsupported();
        }
        int position = 2;
        while (position + 3 < bytes.length) {
            if ((bytes[position++] & 255) != 255) throw ThumbnailException.unsupported();
            while (position < bytes.length && (bytes[position] & 255) == 255) position++;
            if (position >= bytes.length) throw ThumbnailException.unsupported();
            int marker = bytes[position++] & 255;
            if (marker == 218 || marker == 217) return 1;
            if (marker == 1 || (marker >= 208 && marker <= 215)) continue;
            if (position + 2 > bytes.length) throw ThumbnailException.unsupported();
            int length = ((bytes[position] & 255) << 8) | (bytes[position + 1] & 255);
            if (length < 2 || position + length > bytes.length) throw ThumbnailException.unsupported();
            int start = position + 2, end = position + length;
            if (marker == 225 && end - start >= 6 && bytes[start] == 'E' && bytes[start + 1] == 'x'
                    && bytes[start + 2] == 'i' && bytes[start + 3] == 'f' && bytes[start + 4] == 0 && bytes[start + 5] == 0) {
                return tiffOrientation(bytes, start + 6, end);
            }
            position = end;
        }
        throw ThumbnailException.unsupported();
    }

    /** PNG eXIf contains a TIFF header without the JPEG Exif prefix. Chunk bounds and CRC are checked. */
    static int pngOrientation(byte[] bytes) {
        byte[] signature = {(byte) 137, 80, 78, 71, 13, 10, 26, 10};
        if (bytes.length < 20) throw ThumbnailException.unsupported();
        for (int index = 0; index < signature.length; index++) {
            if (bytes[index] != signature[index]) throw ThumbnailException.unsupported();
        }
        Integer orientation = null;
        for (int position = 8; position <= bytes.length - 12;) {
            long length = u32(bytes, position, false);
            if (length > bytes.length - position - 12L) throw ThumbnailException.unsupported();
            int start = position + 8, end = start + (int) length;
            if (bytes[position + 4] == 'e' && bytes[position + 5] == 'X'
                    && bytes[position + 6] == 'I' && bytes[position + 7] == 'f') {
                if (orientation != null) throw ThumbnailException.unsupported();
                CRC32 checksum = new CRC32();
                checksum.update(bytes, position + 4, (int) length + 4);
                if (checksum.getValue() != u32(bytes, end, false)) throw ThumbnailException.unsupported();
                orientation = tiffOrientation(bytes, start, end);
            }
            if (bytes[position + 4] == 'I' && bytes[position + 5] == 'E'
                    && bytes[position + 6] == 'N' && bytes[position + 7] == 'D') {
                if (length != 0) throw ThumbnailException.unsupported();
                return orientation == null ? 1 : orientation;
            }
            position = end + 4;
        }
        throw ThumbnailException.unsupported();
    }

    private static int tiffOrientation(byte[] bytes, int start, int end) {
        if (start + 8 > end) throw ThumbnailException.unsupported();
        boolean little = bytes[start] == 'I' && bytes[start + 1] == 'I';
        if (!little && !(bytes[start] == 'M' && bytes[start + 1] == 'M')) throw ThumbnailException.unsupported();
        if (u16(bytes, start + 2, little) != 42) throw ThumbnailException.unsupported();
        long offset = u32(bytes, start + 4, little);
        if (offset < 8 || offset > end - start - 2) throw ThumbnailException.unsupported();
        int directory = start + (int) offset;
        int entries = u16(bytes, directory, little);
        if ((long) directory + 2L + entries * 12L > end) throw ThumbnailException.unsupported();
        for (int entry = directory + 2, index = 0; index < entries; index++, entry += 12) {
            if (u16(bytes, entry, little) == 0x112) {
                if (u16(bytes, entry + 2, little) != 3 || u32(bytes, entry + 4, little) != 1) {
                    throw ThumbnailException.unsupported();
                }
                int orientation = u16(bytes, entry + 8, little);
                if (orientation < 1 || orientation > 8) throw ThumbnailException.unsupported();
                return orientation;
            }
        }
        return 1;
    }

    private static int u16(byte[] bytes, int at, boolean little) {
        return little ? (bytes[at] & 255) | ((bytes[at + 1] & 255) << 8)
                : ((bytes[at] & 255) << 8) | (bytes[at + 1] & 255);
    }

    private static long u32(byte[] bytes, int at, boolean little) {
        return little ? Integer.toUnsignedLong((bytes[at] & 255) | ((bytes[at + 1] & 255) << 8)
                | ((bytes[at + 2] & 255) << 16) | ((bytes[at + 3] & 255) << 24))
                : Integer.toUnsignedLong(((bytes[at] & 255) << 24) | ((bytes[at + 1] & 255) << 16)
                | ((bytes[at + 2] & 255) << 8) | (bytes[at + 3] & 255));
    }

    static BufferedImage orient(BufferedImage source, int orientation) {
        int width = source.getWidth(), height = source.getHeight();
        boolean swap = orientation >= 5;
        BufferedImage target = new BufferedImage(swap ? height : width, swap ? width : height, BufferedImage.TYPE_INT_ARGB);
        for (int y = 0; y < target.getHeight(); y++) {
            for (int x = 0; x < target.getWidth(); x++) {
                int sx = switch (orientation) {
                    case 2, 3 -> width - 1 - x;
                    case 5, 6 -> y;
                    case 7, 8 -> width - 1 - y;
                    default -> x;
                };
                int sy = switch (orientation) {
                    case 3, 4 -> height - 1 - y;
                    case 5, 8 -> x;
                    case 6, 7 -> height - 1 - x;
                    default -> y;
                };
                target.setRGB(x, y, source.getRGB(sx, sy));
            }
        }
        return target;
    }
}
