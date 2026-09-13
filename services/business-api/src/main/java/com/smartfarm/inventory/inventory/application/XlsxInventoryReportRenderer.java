package com.smartfarm.inventory.inventory.application;

import com.smartfarm.inventory.inventory.application.InventoryReportExportService.ExportSnapshot;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.ReportExportRow;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.ZoneOffset;
import org.apache.poi.ss.usermodel.BorderStyle;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.FillPatternType;
import org.apache.poi.ss.usermodel.Font;
import org.apache.poi.ss.usermodel.HorizontalAlignment;
import org.apache.poi.ss.usermodel.IndexedColors;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.VerticalAlignment;
import org.apache.poi.ss.util.CellRangeAddress;
import org.apache.poi.xssf.usermodel.XSSFSheet;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.stereotype.Component;

@Component
public class XlsxInventoryReportRenderer {
    private static final String SUMMARY_SHEET = "摘要";
    private static final String DATA_SHEET = "已确认盘点";
    private static final String[] HEADERS = {"业务日期", "栋舍编码", "栋舍名称", "栏舍编码", "栏舍名称", "确认数量（头）"};

    public byte[] render(ExportSnapshot snapshot) {
        try (XSSFWorkbook workbook = new XSSFWorkbook(); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            Styles styles = new Styles(workbook);
            XSSFSheet summary = workbook.createSheet(SUMMARY_SHEET);
            XSSFSheet data = workbook.createSheet(DATA_SHEET);
            writeSummary(summary, snapshot, styles);
            writeData(data, snapshot, styles);
            workbook.getCreationHelper().createFormulaEvaluator().evaluateAll();
            workbook.setActiveSheet(0);
            workbook.write(output);
            return output.toByteArray();
        } catch (IOException exception) {
            throw new IllegalStateException("Cannot generate the XLSX inventory report", exception);
        }
    }

    private void writeSummary(XSSFSheet sheet, ExportSnapshot snapshot, Styles styles) {
        sheet.setColumnWidth(0, 22 * 256);
        sheet.setColumnWidth(1, 52 * 256);
        Row title = sheet.createRow(0);
        title.setHeightInPoints(30);
        Cell titleCell = title.createCell(0);
        titleCell.setCellValue("智慧猪场场主 · 已确认盘点报表");
        titleCell.setCellStyle(styles.title);
        sheet.addMergedRegion(new CellRangeAddress(0, 0, 0, 1));

        writeSummaryRow(sheet, 2, "组织编码", snapshot.organizationCode(), styles);
        writeSummaryRow(sheet, 3, "组织名称", snapshot.organizationName(), styles);
        writeSummaryRow(sheet, 4, "日期范围", snapshot.from() + " 至 " + snapshot.to(), styles);
        writeSummaryRow(sheet, 5, "生成时间（UTC）", snapshot.generatedAt().atOffset(ZoneOffset.UTC).toString(), styles);
        writeSummaryRow(sheet, 6, "数据口径", "仅包含已确认盘点；不包含候选、失败、未确认、模型或媒体内部信息。", styles);
        Row count = sheet.createRow(7);
        Cell label = count.createCell(0);
        label.setCellValue("确认记录数");
        label.setCellStyle(styles.label);
        Cell value = count.createCell(1);
        int lastDataRow = Math.max(2, snapshot.rows().size() + 1);
        value.setCellFormula("COUNTA('" + DATA_SHEET + "'!A2:A" + lastDataRow + ")");
        value.setCellStyle(styles.integer);
        sheet.createFreezePane(0, 2);
        sheet.getPrintSetup().setLandscape(false);
        sheet.setFitToPage(true);
        sheet.getPrintSetup().setFitWidth((short) 1);
    }

    private void writeSummaryRow(XSSFSheet sheet, int rowIndex, String labelValue, String text, Styles styles) {
        Row row = sheet.createRow(rowIndex);
        row.setHeightInPoints(rowIndex == 6 ? 36 : 24);
        Cell label = row.createCell(0);
        label.setCellValue(labelValue);
        label.setCellStyle(styles.label);
        Cell value = row.createCell(1);
        value.setCellValue(text);
        value.setCellStyle(rowIndex == 6 ? styles.note : styles.text);
    }

    private void writeData(XSSFSheet sheet, ExportSnapshot snapshot, Styles styles) {
        Row header = sheet.createRow(0);
        header.setHeightInPoints(26);
        for (int column = 0; column < HEADERS.length; column++) {
            Cell cell = header.createCell(column);
            cell.setCellValue(HEADERS[column]);
            cell.setCellStyle(styles.header);
        }
        for (int index = 0; index < snapshot.rows().size(); index++) {
            ReportExportRow source = snapshot.rows().get(index);
            Row row = sheet.createRow(index + 1);
            row.setHeightInPoints(22);
            CellStyle textStyle = index % 2 == 0 ? styles.text : styles.alternateText;
            CellStyle dateStyle = index % 2 == 0 ? styles.date : styles.alternateDate;
            CellStyle integerStyle = index % 2 == 0 ? styles.integer : styles.alternateInteger;
            Cell date = row.createCell(0);
            date.setCellValue(source.businessDate());
            date.setCellStyle(dateStyle);
            writeText(row, 1, source.buildingCode(), textStyle);
            writeText(row, 2, source.buildingName(), textStyle);
            writeText(row, 3, source.penCode(), textStyle);
            writeText(row, 4, source.penName(), textStyle);
            Cell count = row.createCell(5);
            count.setCellValue(source.confirmedCount());
            count.setCellStyle(integerStyle);
        }
        sheet.setColumnWidth(0, 14 * 256);
        sheet.setColumnWidth(1, 16 * 256);
        sheet.setColumnWidth(2, 28 * 256);
        sheet.setColumnWidth(3, 16 * 256);
        sheet.setColumnWidth(4, 28 * 256);
        sheet.setColumnWidth(5, 16 * 256);
        sheet.createFreezePane(0, 1);
        sheet.setAutoFilter(new CellRangeAddress(0, Math.max(0, snapshot.rows().size()), 0, HEADERS.length - 1));
        sheet.setAutobreaks(true);
        sheet.setFitToPage(true);
        sheet.getPrintSetup().setLandscape(true);
        sheet.getPrintSetup().setFitWidth((short) 1);
        sheet.setRepeatingRows(new CellRangeAddress(0, 0, -1, -1));
    }

    private void writeText(Row row, int column, String value, CellStyle style) {
        Cell cell = row.createCell(column);
        cell.setCellValue(value == null ? "" : value);
        cell.setCellStyle(style);
    }

    private static final class Styles {
        private final CellStyle title;
        private final CellStyle header;
        private final CellStyle label;
        private final CellStyle text;
        private final CellStyle note;
        private final CellStyle integer;
        private final CellStyle date;
        private final CellStyle alternateText;
        private final CellStyle alternateInteger;
        private final CellStyle alternateDate;

        private Styles(XSSFWorkbook workbook) {
            Font titleFont = workbook.createFont();
            titleFont.setBold(true);
            titleFont.setFontHeightInPoints((short) 16);
            titleFont.setColor(IndexedColors.DARK_TEAL.getIndex());
            title = workbook.createCellStyle();
            title.setFont(titleFont);
            title.setVerticalAlignment(VerticalAlignment.CENTER);

            Font whiteBold = workbook.createFont();
            whiteBold.setBold(true);
            whiteBold.setColor(IndexedColors.WHITE.getIndex());
            header = base(workbook, whiteBold, IndexedColors.TEAL, false);
            header.setAlignment(HorizontalAlignment.CENTER);

            Font bold = workbook.createFont();
            bold.setBold(true);
            label = base(workbook, bold, IndexedColors.GREY_25_PERCENT, false);
            text = base(workbook, workbook.createFont(), null, false);
            note = base(workbook, workbook.createFont(), IndexedColors.LIGHT_YELLOW, true);
            integer = base(workbook, workbook.createFont(), null, false);
            integer.setAlignment(HorizontalAlignment.RIGHT);
            integer.setDataFormat(workbook.createDataFormat().getFormat("0"));
            date = base(workbook, workbook.createFont(), null, false);
            date.setDataFormat(workbook.createDataFormat().getFormat("yyyy-mm-dd"));
            alternateText = base(workbook, workbook.createFont(), IndexedColors.LIGHT_CORNFLOWER_BLUE, false);
            alternateInteger = base(workbook, workbook.createFont(), IndexedColors.LIGHT_CORNFLOWER_BLUE, false);
            alternateInteger.setAlignment(HorizontalAlignment.RIGHT);
            alternateInteger.setDataFormat(workbook.createDataFormat().getFormat("0"));
            alternateDate = base(workbook, workbook.createFont(), IndexedColors.LIGHT_CORNFLOWER_BLUE, false);
            alternateDate.setDataFormat(workbook.createDataFormat().getFormat("yyyy-mm-dd"));
        }

        private static CellStyle base(XSSFWorkbook workbook, Font font, IndexedColors fill, boolean wrap) {
            CellStyle style = workbook.createCellStyle();
            style.setFont(font);
            style.setVerticalAlignment(VerticalAlignment.CENTER);
            style.setWrapText(wrap);
            style.setBorderBottom(BorderStyle.THIN);
            style.setBorderTop(BorderStyle.THIN);
            style.setBorderLeft(BorderStyle.THIN);
            style.setBorderRight(BorderStyle.THIN);
            style.setBottomBorderColor(IndexedColors.GREY_25_PERCENT.getIndex());
            style.setTopBorderColor(IndexedColors.GREY_25_PERCENT.getIndex());
            style.setLeftBorderColor(IndexedColors.GREY_25_PERCENT.getIndex());
            style.setRightBorderColor(IndexedColors.GREY_25_PERCENT.getIndex());
            if (fill != null) {
                style.setFillForegroundColor(fill.getIndex());
                style.setFillPattern(FillPatternType.SOLID_FOREGROUND);
            }
            return style;
        }
    }
}
