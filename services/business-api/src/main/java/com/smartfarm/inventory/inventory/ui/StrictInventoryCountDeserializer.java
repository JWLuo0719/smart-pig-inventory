package com.smartfarm.inventory.inventory.ui;

import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.JsonToken;
import com.fasterxml.jackson.databind.DeserializationContext;
import com.fasterxml.jackson.databind.JsonDeserializer;
import com.fasterxml.jackson.databind.JsonMappingException;
import java.io.IOException;

/** Quantity writes accept only a JSON integer token; never truncate or coerce another type. */
public final class StrictInventoryCountDeserializer extends JsonDeserializer<Integer> {
    @Override
    public Integer deserialize(JsonParser parser, DeserializationContext context) throws IOException {
        if (!parser.hasToken(JsonToken.VALUE_NUMBER_INT)) {
            throw JsonMappingException.from(parser, "Inventory quantity must be a JSON integer");
        }
        // Jackson's bounded integer read rejects values outside the business field's int32 range.
        // Missing/null values remain null and are rejected by the request's @NotNull validation.
        return parser.getIntValue();
    }
}
