package com.smartfarm.inventory.inventory.thumbnail;

/** Public derivative failures contain no object key, EXIF or underlying storage detail. */
public final class ThumbnailException extends RuntimeException {
    private final int status;
    private final String code;

    private ThumbnailException(int status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public static ThumbnailException unsupported() {
        return new ThumbnailException(422, "THUMBNAIL_UNSUPPORTED",
                "This evidence cannot provide a safe JPEG thumbnail; the original evidence remains available");
    }

    public static ThumbnailException unavailable() {
        return new ThumbnailException(503, "THUMBNAIL_UNAVAILABLE",
                "The thumbnail is temporarily unavailable; retry or open the original evidence");
    }

    public int status() { return status; }
    public String code() { return code; }
}
