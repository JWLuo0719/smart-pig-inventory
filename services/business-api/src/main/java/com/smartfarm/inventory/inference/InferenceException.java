package com.smartfarm.inventory.inference;

public class InferenceException extends RuntimeException {
    private final int status;
    private final String code;

    private InferenceException(int status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public static InferenceException unauthorized() {
        return new InferenceException(401, "INFERENCE_CALLBACK_UNAUTHORIZED", "A valid inference service credential is required");
    }

    public static InferenceException notFound() {
        return new InferenceException(404, "INFERENCE_JOB_NOT_FOUND", "The inference job was not found");
    }

    public static InferenceException conflict(String message) {
        return new InferenceException(409, "INFERENCE_RESULT_CONFLICT", message);
    }

    public static InferenceException invalid(String message) {
        return new InferenceException(422, "INFERENCE_RESULT_INVALID", message);
    }

    public int status() { return status; }
    public String code() { return code; }
}
