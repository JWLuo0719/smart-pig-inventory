package com.smartfarm.inventory.inventory.thumbnail;

import static org.junit.jupiter.api.Assertions.*;

import java.awt.Color;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.zip.CRC32;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;

class ThumbnailCodecTest {
    private final ThumbnailCodec codec = new ThumbnailCodec();

    @Test
    void scalesLandscapeAndPortraitWithoutUpscalingAndPreservesOriginalBytes() throws Exception {
        for (int[] shape : new int[][] {{1800, 900, 320, 160}, {900, 1800, 160, 320}, {120, 80, 120, 80}}) {
            byte[] original = image("png", shape[0], shape[1]);
            byte[] copy = original.clone();
            byte[] jpeg = codec.create(new ByteArrayInputStream(original), "image/png");
            BufferedImage preview = ImageIO.read(new ByteArrayInputStream(jpeg));
            assertEquals(shape[2], preview.getWidth());
            assertEquals(shape[3], preview.getHeight());
            assertArrayEquals(copy, original);
            assertTrue(codec.validCached(jpeg));
        }
    }

    @Test
    void allEightEmbeddedJpegOrientationsPlaceTheFourCornersCorrectlyAndStripPrivateMetadata() throws Exception {
        Color red = Color.RED, green = Color.GREEN, blue = Color.BLUE, yellow = Color.YELLOW;
        Color[][] expected = {{red, green, blue, yellow}, {green, red, yellow, blue},
                {yellow, blue, green, red}, {blue, yellow, red, green}, {red, blue, green, yellow},
                {blue, red, yellow, green}, {yellow, green, blue, red}, {green, yellow, red, blue}};
        byte[] original = image("jpeg", 120, 80);
        for (int orientation = 1; orientation <= 8; orientation++) {
            for (boolean little : new boolean[] {true, false}) {
                byte[] withExif = exif(original, orientation, little);
                assertEquals(orientation, ThumbnailCodec.jpegOrientation(withExif));
                byte[] jpeg = codec.create(new ByteArrayInputStream(withExif), "image/jpeg");
                BufferedImage result = ImageIO.read(new ByteArrayInputStream(jpeg));
                assertEquals(orientation >= 5 ? 80 : 120, result.getWidth());
                assertEquals(orientation >= 5 ? 120 : 80, result.getHeight());
                int[][] samples = {{result.getWidth() / 4, result.getHeight() / 4},
                        {result.getWidth() * 3 / 4, result.getHeight() / 4},
                        {result.getWidth() / 4, result.getHeight() * 3 / 4},
                        {result.getWidth() * 3 / 4, result.getHeight() * 3 / 4}};
                for (int corner = 0; corner < samples.length; corner++) {
                    Color actual = new Color(result.getRGB(samples[corner][0], samples[corner][1]));
                    Color target = expected[orientation - 1][corner];
                    assertTrue(Math.abs(actual.getRed() - target.getRed()) < 25
                            && Math.abs(actual.getGreen() - target.getGreen()) < 25
                            && Math.abs(actual.getBlue() - target.getBlue()) < 25,
                            "orientation=" + orientation + " corner=" + corner);
                }
                String output = new String(jpeg, StandardCharsets.ISO_8859_1);
                assertFalse(output.contains("Exif"));
                assertFalse(output.contains("SYNTHETIC_GPS_SECRET"));
            }
        }
    }

    @Test
    void alphaIsCompositedOnWhiteAndMalformedOrUnsupportedMediaNeverBecomesAThumbnail() throws Exception {
        BufferedImage transparent = new BufferedImage(20, 12, BufferedImage.TYPE_INT_ARGB);
        ByteArrayOutputStream png = new ByteArrayOutputStream();
        ImageIO.write(transparent, "png", png);
        BufferedImage preview = ImageIO.read(new ByteArrayInputStream(codec.create(
                new ByteArrayInputStream(png.toByteArray()), "image/png")));
        assertEquals(Color.WHITE.getRGB(), preview.getRGB(10, 6));
        for (String type : new String[] {"image/heic", "video/mp4", "image/gif"}) {
            assertEquals(422, assertThrows(ThumbnailException.class,
                    () -> codec.create(new ByteArrayInputStream(png.toByteArray()), type)).status());
        }
        assertThrows(ThumbnailException.class, () -> codec.create(new ByteArrayInputStream(new byte[] {1, 2, 3}), "image/png"));
        assertThrows(ThumbnailException.class, () -> codec.create(new ByteArrayInputStream(png.toByteArray()), "image/jpeg"));
        byte[] jpeg = image("jpeg", 120, 80);
        assertThrows(ThumbnailException.class, () -> codec.create(
                new ByteArrayInputStream(Arrays.copyOf(jpeg, jpeg.length - 2)), "image/jpeg"));
        assertFalse(codec.validCached(new byte[] {1, 2, 3}));
        assertFalse(codec.validCached(new byte[ThumbnailCodec.MAX_THUMBNAIL_BYTES + 1]));
        assertFalse(codec.validCached(image("jpeg", 400, 200)));
    }

    @Test
    void rejectsPixelAndDimensionBombsFromHeadersBeforeAllocatingTheirRaster() throws Exception {
        for (int[] dimensions : new int[][] {{8000, 8000}, {20001, 1}, {1, 20001}}) {
            byte[] png = image("png", 1, 1);
            ByteBuffer.wrap(png, 16, 8).putInt(dimensions[0]).putInt(dimensions[1]);
            CRC32 checksum = new CRC32();
            checksum.update(png, 12, 17);
            ByteBuffer.wrap(png, 29, 4).putInt((int) checksum.getValue());
            assertThrows(ThumbnailException.class, () -> codec.create(new ByteArrayInputStream(png), "image/png"));
        }
        assertDoesNotThrow(() -> ThumbnailCodec.validateDimensions(8000, 5000));
        assertThrows(ThumbnailException.class, () -> ThumbnailCodec.validateDimensions(8000, 5001));
    }

    @Test
    void boundsTheActualCompressedStreamAndPropagatesStorageReadFailure() {
        InputStream oversized = new InputStream() {
            @Override public int read() { return 0; }
        };
        assertThrows(ThumbnailException.class, () -> codec.create(oversized, "image/jpeg"));
        InputStream broken = new InputStream() {
            @Override public int read() throws IOException { throw new IOException("private object detail"); }
        };
        assertThrows(IOException.class, () -> codec.create(broken, "image/jpeg"));
    }

    @Test
    void rejectsMalformedExifOffsetsAndUndefinedOrientationsInsteadOfGuessing() throws Exception {
        byte[] malformed = exif(image("jpeg", 120, 80), 6, true);
        // JPEG SOI + APP1 marker/length + Exif signature + TIFF offset field.
        ByteBuffer.wrap(malformed, 16, 4).order(ByteOrder.LITTLE_ENDIAN).putInt(Integer.MAX_VALUE);
        assertThrows(ThumbnailException.class, () -> codec.create(new ByteArrayInputStream(malformed), "image/jpeg"));
        assertThrows(ThumbnailException.class, () -> codec.create(
                new ByteArrayInputStream(exif(image("jpeg", 120, 80), 9, false)), "image/jpeg"));
    }

    @Test
    void standardPngExifAppliesEveryOrientationAndRejectsBadChunkBoundsCrcAndTiff() throws Exception {
        int[][] expectedCorners = {{0, 1, 2, 3}, {1, 0, 3, 2}, {3, 2, 1, 0}, {2, 3, 0, 1},
                {0, 2, 1, 3}, {2, 0, 3, 1}, {3, 1, 2, 0}, {1, 3, 0, 2}};
        Color[] colors = {Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW};
        for (int orientation = 1; orientation <= 8; orientation++) {
            for (boolean little : new boolean[] {true, false}) {
                byte[] png = pngExif(image("png", 120, 80), tiff(orientation, little));
                assertEquals(orientation, ThumbnailCodec.pngOrientation(png));
                byte[] jpeg = codec.create(new ByteArrayInputStream(png), "image/png");
                BufferedImage result = ImageIO.read(new ByteArrayInputStream(jpeg));
                assertEquals(orientation >= 5 ? 80 : 120, result.getWidth());
                assertEquals(orientation >= 5 ? 120 : 80, result.getHeight());
                for (int corner = 0; corner < 4; corner++) {
                    Color actual = new Color(result.getRGB(result.getWidth() * (corner % 2 == 0 ? 1 : 3) / 4,
                            result.getHeight() * (corner < 2 ? 1 : 3) / 4));
                    Color target = colors[expectedCorners[orientation - 1][corner]];
                    assertTrue(Math.abs(actual.getRed() - target.getRed()) < 25
                            && Math.abs(actual.getGreen() - target.getGreen()) < 25
                            && Math.abs(actual.getBlue() - target.getBlue()) < 25);
                }
                assertFalse(new String(jpeg, StandardCharsets.ISO_8859_1).contains("eXIf"));
            }
        }
        byte[] valid = pngExif(image("png", 120, 80), tiff(6, true));
        byte[] badLength = valid.clone();
        ByteBuffer.wrap(badLength, 33, 4).putInt(Integer.MAX_VALUE);
        assertThrows(ThumbnailException.class, () -> codec.create(new ByteArrayInputStream(badLength), "image/png"));
        byte[] badCrc = valid.clone();
        badCrc[41 + 26] ^= 1;
        assertThrows(ThumbnailException.class, () -> codec.create(new ByteArrayInputStream(badCrc), "image/png"));
        assertThrows(ThumbnailException.class, () -> codec.create(
                new ByteArrayInputStream(pngExif(image("png", 120, 80), new byte[] {1, 2, 3})), "image/png"));
    }

    static byte[] image(String format, int width, int height) throws IOException {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        var graphics = image.createGraphics();
        graphics.setColor(Color.RED); graphics.fillRect(0, 0, width / 2, height / 2);
        graphics.setColor(Color.GREEN); graphics.fillRect(width / 2, 0, width - width / 2, height / 2);
        graphics.setColor(Color.BLUE); graphics.fillRect(0, height / 2, width / 2, height - height / 2);
        graphics.setColor(Color.YELLOW); graphics.fillRect(width / 2, height / 2, width - width / 2, height - height / 2);
        graphics.dispose();
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        ImageIO.write(image, format, bytes);
        return bytes.toByteArray();
    }

    static byte[] exif(byte[] jpeg, int orientation, boolean little) throws IOException {
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        body.write(new byte[] {'E', 'x', 'i', 'f', 0, 0});
        body.write(tiff(orientation, little));
        body.write("SYNTHETIC_GPS_SECRET".getBytes(StandardCharsets.US_ASCII));
        ByteArrayOutputStream result = new ByteArrayOutputStream();
        result.write(jpeg, 0, 2);
        result.write(255); result.write(225);
        result.write((body.size() + 2) >> 8); result.write((body.size() + 2) & 255);
        result.write(body.toByteArray()); result.write(jpeg, 2, jpeg.length - 2);
        return result.toByteArray();
    }

    static byte[] tiff(int orientation, boolean little) {
        ByteBuffer tiff = ByteBuffer.allocate(26).order(little ? ByteOrder.LITTLE_ENDIAN : ByteOrder.BIG_ENDIAN);
        tiff.put((byte) (little ? 'I' : 'M')).put((byte) (little ? 'I' : 'M')).putShort((short) 42).putInt(8);
        tiff.putShort((short) 1).putShort((short) 0x112).putShort((short) 3).putInt(1).putShort((short) orientation);
        tiff.putShort((short) 0).putInt(0);
        return tiff.array();
    }

    static byte[] pngExif(byte[] png, byte[] tiff) throws IOException {
        ByteArrayOutputStream result = new ByteArrayOutputStream();
        result.write(png, 0, 33);
        result.write(ByteBuffer.allocate(4).putInt(tiff.length).array());
        byte[] type = {'e', 'X', 'I', 'f'};
        result.write(type); result.write(tiff);
        CRC32 checksum = new CRC32(); checksum.update(type); checksum.update(tiff);
        result.write(ByteBuffer.allocate(4).putInt((int) checksum.getValue()).array());
        result.write(png, 33, png.length - 33);
        return result.toByteArray();
    }
}
