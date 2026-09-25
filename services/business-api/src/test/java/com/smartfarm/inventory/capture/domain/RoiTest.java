package com.smartfarm.inventory.capture.domain;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * ROI 排除区（邻栏不计入本栏）的领域校验与线上序列化行为。
 *
 * <p>这些用例不需要 Docker 或数据库，因此可以在任意工作站上复现。
 */
class RoiTest {
    private static final BigDecimal ZERO = BigDecimal.ZERO;
    private static final BigDecimal ONE = BigDecimal.ONE;

    @Test
    void legacyFourArgumentRoiKeepsTheCenterPointBehaviour() {
        Roi roi = new Roi(ZERO, ZERO, ONE, ONE);

        assertEquals(List.of(), roi.exclusions());
        assertEquals(0, roi.minContainment().compareTo(ZERO));
    }

    @Test
    void acceptsExclusionRegionsAndAContainmentThreshold() {
        Roi roi = assertDoesNotThrow(() -> new Roi(
                ZERO,
                ZERO,
                ONE,
                ONE,
                List.of(new RoiRegion(new BigDecimal("0.75"), ZERO, new BigDecimal("0.25"), ONE)),
                new BigDecimal("0.6")));

        assertEquals(1, roi.exclusions().size());
        assertEquals(0, roi.minContainment().compareTo(new BigDecimal("0.6")));
    }

    @Test
    void rejectsOutOfBoundsExclusionRegion() {
        assertThrows(IllegalArgumentException.class, () -> new RoiRegion(
                new BigDecimal("0.9"), ZERO, new BigDecimal("0.2"), ONE));
        assertThrows(IllegalArgumentException.class, () -> new RoiRegion(
                new BigDecimal("-0.1"), ZERO, new BigDecimal("0.2"), ONE));
        assertThrows(IllegalArgumentException.class, () -> new RoiRegion(
                ZERO, ZERO, ZERO, ONE));
        assertThrows(IllegalArgumentException.class, () -> new RoiRegion(null, ZERO, ONE, ONE));
    }

    @Test
    void rejectsTooManyOrNullExclusionRegions() {
        List<RoiRegion> tooMany = new ArrayList<>();
        for (int index = 0; index <= Roi.MAX_EXCLUSIONS; index++) {
            tooMany.add(new RoiRegion(ZERO, ZERO, new BigDecimal("0.1"), new BigDecimal("0.1")));
        }
        List<RoiRegion> withNull = new ArrayList<>();
        withNull.add(null);

        assertThrows(IllegalArgumentException.class, () -> new Roi(ZERO, ZERO, ONE, ONE, tooMany, ZERO));
        assertThrows(IllegalArgumentException.class, () -> new Roi(ZERO, ZERO, ONE, ONE, withNull, ZERO));
    }

    @Test
    void rejectsContainmentThresholdOutsideTheUnitRange() {
        assertThrows(IllegalArgumentException.class,
                () -> new Roi(ZERO, ZERO, ONE, ONE, List.of(), new BigDecimal("1.5")));
        assertThrows(IllegalArgumentException.class,
                () -> new Roi(ZERO, ZERO, ONE, ONE, List.of(), new BigDecimal("-0.1")));
    }

    @Test
    void serializesAndDeserializesExclusionRegionsOverTheWire() throws Exception {
        ObjectMapper mapper = new ObjectMapper();
        Roi roi = new Roi(
                ZERO,
                ZERO,
                ONE,
                ONE,
                List.of(new RoiRegion(new BigDecimal("0.75"), ZERO, new BigDecimal("0.25"), ONE)),
                new BigDecimal("0.6"));

        Roi parsed = mapper.readValue(mapper.writeValueAsString(roi), Roi.class);

        assertEquals(1, parsed.exclusions().size());
        assertEquals(0, parsed.exclusions().get(0).x().compareTo(new BigDecimal("0.75")));
        assertEquals(0, parsed.exclusions().get(0).width().compareTo(new BigDecimal("0.25")));
        assertEquals(0, parsed.minContainment().compareTo(new BigDecimal("0.6")));
    }

    @Test
    void acceptsLegacyRoiPayloadsWithoutTheNewFields() throws Exception {
        ObjectMapper mapper = new ObjectMapper();

        Roi parsed = mapper.readValue("{\"x\":0.2,\"y\":0.2,\"width\":0.4,\"height\":0.4}", Roi.class);

        assertEquals(List.of(), parsed.exclusions());
        assertEquals(0, parsed.minContainment().compareTo(ZERO));
    }
}
