package com.patterncatalyst.shipping.tracking;

import io.smallrye.graphql.api.ErrorCode;
import io.smallrye.graphql.api.ErrorExtensionProvider;
import jakarta.json.Json;
import jakarta.json.JsonValue;

/** extensions.code from @ErrorCode only; an undeclared exception gets no code (JSON null), and nothing else. */
public class DeclaredErrorCodeProvider implements ErrorExtensionProvider {
    @Override
    public String getKey() {
        return "code";
    }

    @Override
    public JsonValue mapValueFrom(Throwable exception) {
        ErrorCode code = exception.getClass().getAnnotation(ErrorCode.class);
        return code == null ? null : Json.createValue(code.value());
    }
}
