package com.smartfarm.inventory.inventory.thumbnail;

import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import com.smartfarm.inventory.inventory.application.InventoryException;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class ThumbnailControllerTest {
    @Test
    void successfulPreviewIsJpegNoStoreAndDoesNotExposeAnObjectLocation() throws Exception {
        UUID asset = UUID.randomUUID();
        byte[] jpeg = new ThumbnailCodec().create(new java.io.ByteArrayInputStream(
                ThumbnailCodecTest.image("png", 40, 20)), "image/png");
        ThumbnailService service = mock(ThumbnailService.class);
        when(service.thumbnail(asset)).thenReturn(jpeg);
        MockMvcBuilders.standaloneSetup(new ThumbnailController(service)).setControllerAdvice(new ThumbnailProblemHandler())
                .build().perform(get("/api/v1/media-assets/{asset}/thumbnail", asset))
                .andExpect(status().isOk()).andExpect(content().contentType("image/jpeg"))
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(header().doesNotExist("Location")).andExpect(content().bytes(jpeg));
    }

    @Test
    void unavailableOrInaccessiblePreviewReturnsSafeProblemsWithoutOriginalFallback() throws Exception {
        UUID asset = UUID.randomUUID();
        ThumbnailService service = mock(ThumbnailService.class);
        var mvc = MockMvcBuilders.standaloneSetup(new ThumbnailController(service))
                .setControllerAdvice(new ThumbnailProblemHandler()).build();
        for (RuntimeException failure : new RuntimeException[] {
                ThumbnailException.unsupported(), ThumbnailException.unavailable(), InventoryException.notFound()}) {
            doThrow(failure).when(service).thumbnail(asset);
            int expected = failure instanceof ThumbnailException thumbnail ? thumbnail.status() : 404;
            mvc.perform(get("/api/v1/media-assets/{asset}/thumbnail", asset))
                    .andExpect(status().is(expected)).andExpect(content().contentType("application/problem+json"))
                    .andExpect(header().string("Cache-Control", "no-store"))
                    .andExpect(jsonPath("$.status").value(expected)).andExpect(header().doesNotExist("Location"));
        }
    }
}
