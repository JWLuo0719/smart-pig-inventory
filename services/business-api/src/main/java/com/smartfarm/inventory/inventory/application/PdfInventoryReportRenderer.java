package com.smartfarm.inventory.inventory.application;

import com.smartfarm.inventory.inventory.application.InventoryReportExportService.ExportSnapshot;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.ReportExportRow;
import java.awt.Color;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.font.PDFont;
import org.apache.pdfbox.pdmodel.font.PDType0Font;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class PdfInventoryReportRenderer {
    private static final float MARGIN = 36;
    private static final float BODY_FONT_SIZE = 8;
    private static final float LINE_HEIGHT = 10;
    private static final float[] WIDTHS = {58, 58, 120, 58, 120, 50};
    private static final String[] HEADERS = {"业务日期", "栋舍编码", "栋舍名称", "栏舍编码", "栏舍名称", "确认数量"};
    private final String configuredFontPath;

    public PdfInventoryReportRenderer(@Value("${app.reports.pdf-font-path:}") String configuredFontPath) {
        this.configuredFontPath = configuredFontPath == null ? "" : configuredFontPath.trim();
    }

    public byte[] render(ExportSnapshot snapshot) {
        try (PDDocument document = new PDDocument(); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            ReportFonts fonts = new ReportFonts(loadFont(document), loadLatinFont(document));
            TableWriter writer = new TableWriter(document, fonts);
            writer.start(snapshot);
            for (ReportExportRow row : snapshot.rows()) {
                writer.writeRow(List.of(row.businessDate().toString(), value(row.buildingCode()), value(row.buildingName()),
                        value(row.penCode()), value(row.penName()), Integer.toString(row.confirmedCount())));
            }
            writer.finish();
            addPageNumbers(document, fonts);
            document.save(output);
            return output.toByteArray();
        } catch (IOException exception) {
            throw new IllegalStateException("Cannot generate the PDF inventory report", exception);
        }
    }

    private PDFont loadFont(PDDocument document) throws IOException {
        for (Path candidate : fontCandidates()) {
            if (Files.isRegularFile(candidate) && Files.isReadable(candidate)) {
                try (InputStream input = Files.newInputStream(candidate)) {
                    return PDType0Font.load(document, input, true);
                }
            }
        }
        throw new IllegalStateException("No readable Chinese PDF font is configured; set REPORT_PDF_FONT_PATH");
    }

    private PDFont loadLatinFont(PDDocument document) throws IOException {
        for (Path candidate : List.of(
                Path.of("C:/Windows/Fonts/arial.ttf"),
                Path.of("C:/Windows/Fonts/segoeui.ttf"),
                Path.of("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"))) {
            if (Files.isRegularFile(candidate) && Files.isReadable(candidate)) {
                try (InputStream input = Files.newInputStream(candidate)) {
                    return PDType0Font.load(document, input, true);
                }
            }
        }
        throw new IllegalStateException("No readable Latin PDF font is available");
    }

    private List<Path> fontCandidates() {
        List<Path> candidates = new ArrayList<>();
        if (!configuredFontPath.isBlank()) candidates.add(Path.of(configuredFontPath));
        candidates.add(Path.of("C:/Windows/Fonts/simhei.ttf"));
        candidates.add(Path.of("C:/Windows/Fonts/msyh.ttc"));
        candidates.add(Path.of("/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf"));
        return candidates;
    }

    private void addPageNumbers(PDDocument document, ReportFonts fonts) throws IOException {
        int total = document.getNumberOfPages();
        for (int index = 0; index < total; index++) {
            PDPage page = document.getPage(index);
            try (PDPageContentStream content = new PDPageContentStream(document, page,
                    PDPageContentStream.AppendMode.APPEND, true, true)) {
                String text = "第 " + (index + 1) + " / " + total + " 页";
                float width = fonts.width(text, 8);
                drawText(content, fonts, 8, text, (PDRectangle.A4.getWidth() - width) / 2, 20, Color.DARK_GRAY);
            }
        }
    }

    private static String value(String value) {
        return value == null ? "" : value;
    }

    private static void drawText(PDPageContentStream content, ReportFonts fonts, float size, String text,
            float x, float y, Color color) throws IOException {
        content.beginText();
        content.setNonStrokingColor(color);
        content.newLineAtOffset(x, y);
        for (TextRun run : fonts.runs(text)) {
            content.setFont(run.font(), size);
            content.showText(run.text());
        }
        content.endText();
    }

    private record TextRun(PDFont font, String text) {}

    private record ReportFonts(PDFont cjk, PDFont latin) {
        private List<TextRun> runs(String text) throws IOException {
            List<TextRun> runs = new ArrayList<>();
            StringBuilder current = new StringBuilder();
            PDFont currentFont = null;
            for (int codePoint : text.codePoints().toArray()) {
                String glyph = new String(Character.toChars(codePoint));
                PDFont glyphFont = codePoint < 0x2E80 && canEncode(latin, glyph) ? latin : cjk;
                if (!canEncode(glyphFont, glyph)) {
                    glyph = "?";
                    glyphFont = latin;
                }
                if (currentFont != null && currentFont != glyphFont) {
                    runs.add(new TextRun(currentFont, current.toString()));
                    current.setLength(0);
                }
                currentFont = glyphFont;
                current.append(glyph);
            }
            if (!current.isEmpty()) runs.add(new TextRun(currentFont, current.toString()));
            return runs;
        }

        private float width(String text, float size) throws IOException {
            float width = 0;
            for (TextRun run : runs(text)) {
                width += run.font().getStringWidth(run.text()) / 1000 * size;
            }
            return width;
        }

        private static boolean canEncode(PDFont font, String text) throws IOException {
            try {
                font.encode(text);
                return true;
            } catch (IllegalArgumentException exception) {
                return false;
            }
        }
    }

    private static final class TableWriter {
        private final PDDocument document;
        private final ReportFonts fonts;
        private PDPageContentStream content;
        private float y;

        private TableWriter(PDDocument document, ReportFonts fonts) {
            this.document = document;
            this.fonts = fonts;
        }

        private void start(ExportSnapshot snapshot) throws IOException {
            newPage();
            drawText(content, fonts, 16, "智慧猪场场主 - 已确认盘点报表", MARGIN, y, new Color(15, 118, 110));
            y -= 24;
            drawText(content, fonts, 9, "组织：" + snapshot.organizationCode() + " / " + snapshot.organizationName(),
                    MARGIN, y, Color.DARK_GRAY);
            y -= 15;
            drawText(content, fonts, 9, "日期：" + snapshot.from() + " 至 " + snapshot.to()
                    + "    生成时间（UTC）：" + snapshot.generatedAt().atOffset(ZoneOffset.UTC), MARGIN, y, Color.DARK_GRAY);
            y -= 15;
            drawText(content, fonts, 9, "数据口径：仅包含已确认盘点；共 " + snapshot.rows().size()
                    + " 条。候选、失败、未确认、模型及媒体内部信息均未导出。", MARGIN, y, new Color(146, 64, 14));
            y -= 22;
            writeHeader();
        }

        private void writeRow(List<String> values) throws IOException {
            List<List<String>> wrapped = new ArrayList<>();
            int lineCount = 1;
            for (int column = 0; column < values.size(); column++) {
                List<String> lines = wrap(values.get(column), WIDTHS[column] - 8, 2);
                wrapped.add(lines);
                lineCount = Math.max(lineCount, lines.size());
            }
            float height = Math.max(20, lineCount * LINE_HEIGHT + 8);
            if (y - height < 44) {
                content.close();
                newPage();
                writeHeader();
            }
            drawCells(wrapped, height, false);
        }

        private void writeHeader() throws IOException {
            List<List<String>> cells = new ArrayList<>();
            for (String header : HEADERS) cells.add(List.of(header));
            drawCells(cells, 22, true);
        }

        private void drawCells(List<List<String>> cells, float height, boolean header) throws IOException {
            float x = MARGIN;
            for (int column = 0; column < cells.size(); column++) {
                if (header) {
                    content.setNonStrokingColor(new Color(15, 118, 110));
                    content.addRect(x, y - height, WIDTHS[column], height);
                    content.fill();
                }
                content.setStrokingColor(new Color(148, 163, 184));
                content.addRect(x, y - height, WIDTHS[column], height);
                content.stroke();
                float textY = y - (height - cells.get(column).size() * LINE_HEIGHT) / 2 - BODY_FONT_SIZE;
                for (String line : cells.get(column)) {
                    drawText(content, fonts, BODY_FONT_SIZE, line, x + 4, textY,
                            header ? Color.WHITE : new Color(30, 41, 59));
                    textY -= LINE_HEIGHT;
                }
                x += WIDTHS[column];
            }
            y -= height;
        }

        private List<String> wrap(String text, float maxWidth, int maxLines) throws IOException {
            List<String> lines = new ArrayList<>();
            StringBuilder current = new StringBuilder();
            int[] points = text.codePoints().toArray();
            int index = 0;
            while (index < points.length && lines.size() < maxLines) {
                String next = new String(Character.toChars(points[index]));
                String candidate = current + next;
                if (!current.isEmpty() && width(candidate) > maxWidth) {
                    lines.add(current.toString());
                    current.setLength(0);
                    continue;
                }
                current.append(next);
                index++;
            }
            if (!current.isEmpty() && lines.size() < maxLines) lines.add(current.toString());
            if (index < points.length) {
                int last = lines.size() - 1;
                String truncated = lines.get(last);
                while (!truncated.isEmpty() && width(truncated + "…") > maxWidth) {
                    truncated = truncated.substring(0, truncated.offsetByCodePoints(0, truncated.codePointCount(0, truncated.length()) - 1));
                }
                lines.set(last, truncated + "…");
            }
            return lines.isEmpty() ? List.of("") : lines;
        }

        private float width(String text) throws IOException {
            return fonts.width(text, BODY_FONT_SIZE);
        }

        private void newPage() throws IOException {
            PDPage page = new PDPage(PDRectangle.A4);
            document.addPage(page);
            content = new PDPageContentStream(document, page);
            y = PDRectangle.A4.getHeight() - MARGIN;
        }

        private void finish() throws IOException {
            if (content != null) content.close();
        }
    }
}
