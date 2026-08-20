package com.smartfarm.inventory.inference;

public interface CountingProvider {
    String key();

    CountingResult count(CountingRequest request);
}

