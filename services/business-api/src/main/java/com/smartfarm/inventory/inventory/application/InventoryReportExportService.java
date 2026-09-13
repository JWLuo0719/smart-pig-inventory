package com.smartfarm.inventory.inventory.application;

import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.OrganizationRow;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.ReportExportRow;
import com.smartfarm.inventory.inventory.infrastructure.SecurityReviewActor;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class InventoryReportExportService {
    private final JdbcInventoryReviewRepository repository;
    private final SecurityReviewActor actor;
    private final PdfInventoryReportRenderer pdfRenderer;
    private final XlsxInventoryReportRenderer xlsxRenderer;
    private final int maxRangeDays;
    private final int maxRecords;
    private final Clock clock;

    @Autowired
    public InventoryReportExportService(JdbcInventoryReviewRepository repository, SecurityReviewActor actor,
            PdfInventoryReportRenderer pdfRenderer, XlsxInventoryReportRenderer xlsxRenderer,
            @Value("${app.reports.max-range-days:366}") int maxRangeDays,
            @Value("${app.reports.max-records:10000}") int maxRecords) {
        this(repository, actor, pdfRenderer, xlsxRenderer, maxRangeDays, maxRecords, Clock.systemUTC());
    }

    InventoryReportExportService(JdbcInventoryReviewRepository repository, SecurityReviewActor actor,
            PdfInventoryReportRenderer pdfRenderer, XlsxInventoryReportRenderer xlsxRenderer,
            int maxRangeDays, int maxRecords, Clock clock) {
        if (maxRangeDays < 1 || maxRecords < 1) {
            throw new IllegalArgumentException("Report export limits must be positive");
        }
        this.repository = repository;
        this.actor = actor;
        this.pdfRenderer = pdfRenderer;
        this.xlsxRenderer = xlsxRenderer;
        this.maxRangeDays = maxRangeDays;
        this.maxRecords = maxRecords;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public ExportDocument export(String requestedFormat, LocalDate from, LocalDate to) {
        ExportFormat format = ExportFormat.parse(requestedFormat);
        validateRange(from, to);
        UUID organizationId = actor.activeOrganizationId();
        actor.assertCanView(organizationId);
        OrganizationRow organization = repository.findOrganization(organizationId).orElseThrow(InventoryException::notFound);
        List<ReportExportRow> rows = repository.listConfirmedForExport(organizationId, from, to, maxRecords + 1);
        if (rows.size() > maxRecords) {
            throw InventoryException.invalid("The report contains more than " + maxRecords
                    + " confirmed records; shorten the export date range");
        }
        ExportSnapshot snapshot = new ExportSnapshot(organization.code(), organization.name(), from, to,
                Instant.now(clock), List.copyOf(rows));
        byte[] bytes = switch (format) {
            case PDF -> pdfRenderer.render(snapshot);
            case XLSX -> xlsxRenderer.render(snapshot);
        };
        String baseName = "pig-inventory-" + compactDate(from) + "-" + compactDate(to);
        return new ExportDocument(bytes, format.contentType, baseName + "." + format.extension);
    }

    private void validateRange(LocalDate from, LocalDate to) {
        if (from == null || to == null || from.isAfter(to)) {
            throw InventoryException.invalid("The report export start date must not be after its end date");
        }
        long inclusiveDays = ChronoUnit.DAYS.between(from, to) + 1;
        if (inclusiveDays > maxRangeDays) {
            throw InventoryException.invalid("The report export range must not exceed " + maxRangeDays + " days");
        }
    }

    private static String compactDate(LocalDate date) {
        return date.toString().replace("-", "");
    }

    enum ExportFormat {
        PDF("application/pdf", "pdf"),
        XLSX("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx");

        private final String contentType;
        private final String extension;

        ExportFormat(String contentType, String extension) {
            this.contentType = contentType;
            this.extension = extension;
        }

        static ExportFormat parse(String value) {
            try {
                return ExportFormat.valueOf(value == null ? "" : value.toUpperCase(Locale.ROOT));
            } catch (IllegalArgumentException exception) {
                throw InventoryException.invalid("The report export format must be pdf or xlsx");
            }
        }
    }

    public record ExportSnapshot(String organizationCode, String organizationName, LocalDate from, LocalDate to,
            Instant generatedAt, List<ReportExportRow> rows) {
    }

    public record ExportDocument(byte[] bytes, String contentType, String filename) {
    }
}
