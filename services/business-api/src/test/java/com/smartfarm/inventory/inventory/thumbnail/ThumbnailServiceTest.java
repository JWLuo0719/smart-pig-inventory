package com.smartfarm.inventory.inventory.thumbnail;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.smartfarm.inventory.capture.infrastructure.StagedObjectStorage;
import com.smartfarm.inventory.capture.infrastructure.UploadStorageException;
import com.smartfarm.inventory.inventory.application.InventoryException;
import com.smartfarm.inventory.inventory.infrastructure.SecurityReviewActor;
import com.smartfarm.inventory.inventory.thumbnail.JdbcThumbnailRepository.Source;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.Arrays;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class ThumbnailServiceTest {
    private final UUID organization = UUID.randomUUID(), asset = UUID.randomUUID();
    private final JdbcThumbnailRepository repository = mock(JdbcThumbnailRepository.class);
    private final SecurityReviewActor actor = mock(SecurityReviewActor.class);
    private final MemoryStorage storage = spy(new MemoryStorage());
    private final AtomicReference<Source> current = new AtomicReference<>();
    private byte[] original;
    private ThumbnailService service;

    @BeforeEach
    void setup() throws Exception {
        original = ThumbnailCodecTest.image("png", 640, 320);
        current.set(new Source(organization, asset, "image/png", original.length, "a".repeat(64), "private-original", null));
        storage.objects.put("private-original", original);
        when(actor.activeOrganizationId()).thenReturn(organization);
        when(repository.find(any(), any())).thenAnswer(call -> {
            Source source = current.get();
            return source != null && source.organizationId().equals(call.getArgument(0))
                    && source.assetId().equals(call.getArgument(1)) ? Optional.of(source) : Optional.empty();
        });
        when(repository.attach(any(), anyString())).thenAnswer(call -> {
            Source source = current.get();
            if (source == null) return false;
            current.set(new Source(source.organizationId(), source.assetId(), source.contentType(), source.byteSize(),
                    source.sha256(), source.storageKey(), call.getArgument(1)));
            return true;
        });
        service = new ThumbnailService(repository, storage, new ThumbnailCodec(), actor);
    }

    @Test
    void generatesPrivateOrgScopedCacheAndEveryHitReauthorizesWithoutChangingOriginal() {
        byte[] output = service.thumbnail(asset);
        String key = current.get().thumbnailKey();
        assertEquals("thumbnails/v1/" + organization + "/" + asset + "/" + "a".repeat(64) + "-320.jpg", key);
        assertArrayEquals(output, storage.objects.get(key));
        assertArrayEquals(original, storage.objects.get("private-original"));
        assertArrayEquals(output, service.thumbnail(asset));
        verify(storage, times(1)).open("private-original");
        verify(storage, times(1)).putDerivedJpeg(eq(key), any());
        verify(actor, atLeast(5)).assertCanView(organization);
    }

    @Test
    void missingCorruptOrOversizedDerivedObjectIsRebuiltThroughOriginal() {
        service.thumbnail(asset);
        String key = current.get().thumbnailKey();
        storage.objects.remove(key);
        assertTrue(new ThumbnailCodec().validCached(service.thumbnail(asset)));
        storage.objects.put(key, new byte[] {0, 1, 2});
        assertTrue(new ThumbnailCodec().validCached(service.thumbnail(asset)));
        storage.objects.put(key, new byte[ThumbnailCodec.MAX_THUMBNAIL_BYTES + 1]);
        assertTrue(new ThumbnailCodec().validCached(service.thumbnail(asset)));
        verify(storage, times(4)).putDerivedJpeg(eq(key), any());
    }

    @Test
    void otherOrganizationOrDeletedMediaCannotReadOriginalOrCachedBytes() {
        when(actor.activeOrganizationId()).thenReturn(UUID.randomUUID());
        assertEquals(404, assertThrows(InventoryException.class, () -> service.thumbnail(asset)).status());
        verifyNoInteractions(storage);
        when(actor.activeOrganizationId()).thenReturn(organization);
        service.thumbnail(asset);
        clearInvocations(storage);
        current.set(null);
        assertEquals(404, assertThrows(InventoryException.class, () -> service.thumbnail(asset)).status());
        verifyNoInteractions(storage);
    }

    @Test
    void deletionDuringGenerationOrCachedReadStopsTheResponseAndDoesNotAttachADeletedSource() throws Exception {
        ThumbnailCodec deletingCodec = new ThumbnailCodec() {
            @Override public byte[] create(InputStream source, String contentType) throws java.io.IOException {
                byte[] output = super.create(source, contentType);
                current.set(null);
                return output;
            }
        };
        var deletingService = new ThumbnailService(repository, storage, deletingCodec, actor);
        assertEquals(404, assertThrows(InventoryException.class, () -> deletingService.thumbnail(asset)).status());
        verify(storage, never()).putDerivedJpeg(anyString(), any());
        verify(repository, never()).attach(any(), anyString());
        setup();
        service.thumbnail(asset);
        String key = current.get().thumbnailKey();
        doAnswer(call -> { current.set(null); return Optional.of(new ByteArrayInputStream(storage.objects.get(key))); })
                .when(storage).openDerived(key);
        assertEquals(404, assertThrows(InventoryException.class, () -> service.thumbnail(asset)).status());
    }

    @Test
    void storageFailuresAre503KeepThePointerUnchangedAndCanRecover() {
        doThrow(mock(UploadStorageException.class)).when(storage).putDerivedJpeg(anyString(), any());
        assertEquals(503, assertThrows(ThumbnailException.class, () -> service.thumbnail(asset)).status());
        assertNull(current.get().thumbnailKey());
        doCallRealMethod().when(storage).putDerivedJpeg(anyString(), any());
        assertTrue(new ThumbnailCodec().validCached(service.thumbnail(asset)));
        doThrow(mock(UploadStorageException.class)).when(storage).openDerived(anyString());
        assertEquals(503, assertThrows(ThumbnailException.class, () -> service.thumbnail(asset)).status());
    }

    @Test
    void unsupportedTypesAndRecordedByteLimitFailBeforeObjectRead() {
        for (String type : new String[] {"image/heic", "video/mp4"}) {
            Source source = current.get();
            current.set(new Source(organization, asset, type, 100, source.sha256(), source.storageKey(), null));
            assertEquals(422, assertThrows(ThumbnailException.class, () -> service.thumbnail(asset)).status());
        }
        Source source = current.get();
        current.set(new Source(organization, asset, "image/jpeg", ThumbnailCodec.MAX_SOURCE_BYTES + 1L,
                source.sha256(), source.storageKey(), null));
        assertEquals(422, assertThrows(ThumbnailException.class, () -> service.thumbnail(asset)).status());
        verifyNoInteractions(storage);
    }

    @Test
    void atMostTwoGenerationsRunAndBusyRequestCanRetryAfterAWorkerCompletes() throws Exception {
        CountDownLatch entered = new CountDownLatch(2), release = new CountDownLatch(1);
        ThumbnailCodec blocking = new ThumbnailCodec() {
            @Override public byte[] create(InputStream source, String contentType) throws java.io.IOException {
                entered.countDown();
                try { if (!release.await(5, TimeUnit.SECONDS)) throw new java.io.IOException("test timeout"); }
                catch (InterruptedException exception) { Thread.currentThread().interrupt(); throw new java.io.IOException(exception); }
                return super.create(source, contentType);
            }
        };
        var limited = new ThumbnailService(repository, storage, blocking, actor);
        try (var workers = Executors.newFixedThreadPool(2)) {
            var first = workers.submit(() -> limited.thumbnail(asset));
            var second = workers.submit(() -> limited.thumbnail(asset));
            try {
                assertTrue(entered.await(5, TimeUnit.SECONDS));
                assertEquals(503, assertThrows(ThumbnailException.class, () -> limited.thumbnail(asset)).status());
            } finally { release.countDown(); }
            assertTrue(first.get(5, TimeUnit.SECONDS).length > 0);
            assertTrue(second.get(5, TimeUnit.SECONDS).length > 0);
            assertTrue(limited.thumbnail(asset).length > 0);
        }
    }

    static class MemoryStorage implements StagedObjectStorage {
        final Map<String, byte[]> objects = new ConcurrentHashMap<>();
        @Override public InputStream open(String key) { return new ByteArrayInputStream(objects.get(key)); }
        @Override public Optional<InputStream> openDerived(String key) {
            return Optional.ofNullable(objects.get(key)).map(ByteArrayInputStream::new);
        }
        @Override public void putDerivedJpeg(String key, byte[] bytes) { objects.put(key, Arrays.copyOf(bytes, bytes.length)); }
        @Override public String stage(UUID packageId, UUID assetId, InputStream source, long length) { throw new UnsupportedOperationException(); }
        @Override public String promote(String key, UUID organizationId, UUID assetId) { throw new UnsupportedOperationException(); }
        @Override public void deleteQuietly(String key) { objects.remove(key); }
    }
}
