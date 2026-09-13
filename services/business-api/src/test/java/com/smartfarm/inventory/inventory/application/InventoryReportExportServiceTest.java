package com.smartfarm.inventory.inventory.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.OrganizationRow;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.ReportExportRow;
import com.smartfarm.inventory.inventory.infrastructure.SecurityReviewActor;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class InventoryReportExportServiceTest {
    @Mock private JdbcInventoryReviewRepository repository;
    @Mock private SecurityReviewActor actor;
    @Mock private PdfInventoryReportRenderer pdfRenderer;
    @Mock private XlsxInventoryReportRenderer xlsxRenderer;
    private InventoryReportExportService service;
    private UUID organizationId;

    @BeforeEach
    void setUp() {
        service = new InventoryReportExportService(repository, actor, pdfRenderer, xlsxRenderer, 366, 2,
                Clock.fixed(Instant.parse("2026-09-01T02:03:04Z"), ZoneOffset.UTC));
        organizationId = UUID.randomUUID();
    }

    @Test
    void rendersTheRequestedFormatFromOneOrganizationScopedConfirmedProjection() {
        LocalDate date = LocalDate.of(2026, 9, 1);
        List<ReportExportRow> rows = List.of(new ReportExportRow(date, "B01", "一号栋", "P01", "一号栏", 12));
        when(actor.activeOrganizationId()).thenReturn(organizationId);
        when(repository.findOrganization(organizationId)).thenReturn(Optional.of(new OrganizationRow("ORG-01", "测试猪场")));
        when(repository.listConfirmedForExport(organizationId, date, date, 3)).thenReturn(rows);
        when(pdfRenderer.render(org.mockito.ArgumentMatchers.any())).thenReturn(new byte[] {1, 2, 3});

        var document = service.export("pdf", date, date);

        assertThat(document.contentType()).isEqualTo("application/pdf");
        assertThat(document.filename()).isEqualTo("pig-inventory-20260901-20260901.pdf");
        assertThat(document.bytes()).containsExactly(1, 2, 3);
        verify(actor).assertCanView(organizationId);
        verify(repository).listConfirmedForExport(organizationId, date, date, 3);
    }

    @Test
    void rejectsUnsafeRangeFormatAndRecordCount() {
        LocalDate from = LocalDate.of(2025, 8, 31);
        LocalDate to = LocalDate.of(2026, 9, 1);
        assertThatThrownBy(() -> service.export("csv", to, to)).isInstanceOf(InventoryException.class)
                .hasMessageContaining("pdf or xlsx");
        assertThatThrownBy(() -> service.export("pdf", to, from)).isInstanceOf(InventoryException.class)
                .hasMessageContaining("must not be after");
        assertThatThrownBy(() -> service.export("pdf", from, to)).isInstanceOf(InventoryException.class)
                .hasMessageContaining("366 days");

        when(actor.activeOrganizationId()).thenReturn(organizationId);
        when(repository.findOrganization(organizationId)).thenReturn(Optional.of(new OrganizationRow("ORG", "组织")));
        when(repository.listConfirmedForExport(organizationId, to, to, 3)).thenReturn(List.of(
                new ReportExportRow(to, "B1", "栋1", "P1", "栏1", 1),
                new ReportExportRow(to, "B2", "栋2", "P2", "栏2", 2),
                new ReportExportRow(to, "B3", "栋3", "P3", "栏3", 3)));
        assertThatThrownBy(() -> service.export("xlsx", to, to)).isInstanceOf(InventoryException.class)
                .hasMessageContaining("more than 2");
    }
}
