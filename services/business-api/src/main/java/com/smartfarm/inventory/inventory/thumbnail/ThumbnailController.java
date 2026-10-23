package com.smartfarm.inventory.inventory.thumbnail;

import java.util.UUID;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/media-assets")
public class ThumbnailController {
    private final ThumbnailService service;

    public ThumbnailController(ThumbnailService service) { this.service = service; }

    @GetMapping("/{assetId}/thumbnail")
    public ResponseEntity<byte[]> thumbnail(@PathVariable UUID assetId) {
        byte[] image = service.thumbnail(assetId);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).contentType(MediaType.IMAGE_JPEG)
                .contentLength(image.length).body(image);
    }
}
