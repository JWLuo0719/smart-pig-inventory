package com.smartfarm.inventory.inventory.application;

import static org.assertj.core.api.Assertions.assertThat;

import com.smartfarm.inventory.inventory.application.InventoryReportExportService.ExportSnapshot;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.ReportExportRow;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;
import org.apache.poi.ss.usermodel.CellType;
import org.apache.poi.ss.usermodel.DateUtil;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledOnOs;
import org.junit.jupiter.api.condition.OS;

class InventoryReportRendererTest {
    private static final Path QA_DIRECTORY = Path.of("target", "report-export-qa");

    @Test
    void createsTypedSafeAndReadableXlsx() throws Exception {
        ExportSnapshot snapshot = snapshot(List.of(
                new ReportExportRow(LocalDate.of(2026, 9, 1), "=1+1", "一号栋", "P01", "一号栏", 12),
                new ReportExportRow(LocalDate.of(2026, 9, 2), "B02", "二号栋", "P02", "二号栏", 9)));
        byte[] bytes = new XlsxInventoryReportRenderer().render(snapshot);
        Files.createDirectories(QA_DIRECTORY);
        Files.write(QA_DIRECTORY.resolve("confirmed-inventory-report.xlsx"), bytes);

        try (XSSFWorkbook workbook = new XSSFWorkbook(new java.io.ByteArrayInputStream(bytes))) {
            assertThat(workbook.getNumberOfSheets()).isEqualTo(2);
            assertThat(workbook.getSheetName(0)).isEqualTo("摘要");
            assertThat(workbook.getSheetName(1)).isEqualTo("已确认盘点");
            assertThat(workbook.getSheet("摘要").getRow(7).getCell(1).getCellType()).isEqualTo(CellType.FORMULA);
            assertThat(workbook.getSheet("摘要").getRow(7).getCell(1).getNumericCellValue()).isEqualTo(2);
            var data = workbook.getSheet("已确认盘点");
            assertThat(data.getRow(1).getCell(1).getCellType()).isEqualTo(CellType.STRING);
            assertThat(data.getRow(1).getCell(1).getStringCellValue()).isEqualTo("=1+1");
            assertThat(DateUtil.isCellDateFormatted(data.getRow(1).getCell(0))).isTrue();
            assertThat(data.getRow(1).getCell(5).getCellType()).isEqualTo(CellType.NUMERIC);
            assertThat(data.getRow(1).getCell(5).getNumericCellValue()).isEqualTo(12);
        }
    }

    @Test
    @EnabledOnOs(OS.WINDOWS)
    void createsPaginatedSearchableChinesePdf() throws Exception {
        List<ReportExportRow> rows = new ArrayList<>();
        for (int index = 0; index < 80; index++) {
            rows.add(new ReportExportRow(LocalDate.of(2026, 9, 1).plusDays(index % 2), "B%02d".formatted(index),
                    "需要换行的一号栋舍名称🐷" + index, "P%02d".formatted(index), "需要换行的一号栏舍名称" + index, index));
        }
        byte[] bytes = new PdfInventoryReportRenderer("C:/Windows/Fonts/simhei.ttf").render(snapshot(rows));
        Files.createDirectories(QA_DIRECTORY);
        Files.write(QA_DIRECTORY.resolve("confirmed-inventory-report.pdf"), bytes);

        try (PDDocument document = Loader.loadPDF(bytes)) {
            String text = new PDFTextStripper().getText(document);
            assertThat(document.getNumberOfPages()).isGreaterThan(1);
            assertThat(text).contains("智慧猪场场主", "仅包含已确认盘点", "B00", "80 条");
            assertThat(text).doesNotContain("MODEL_CHECKSUM", "minio://", "PROVIDER_TIMEOUT");
        }
    }

    private static ExportSnapshot snapshot(List<ReportExportRow> rows) {
        return new ExportSnapshot("ORG-01", "测试猪场", LocalDate.of(2026, 9, 1), LocalDate.of(2026, 9, 2),
                Instant.parse("2026-09-01T02:03:04Z"), rows);
    }
}
