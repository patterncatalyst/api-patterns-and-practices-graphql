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
        String code = codeOf(exception);
        return code == null ? null : Json.createValue(code);
    }

    /** The {@code @ErrorCode} of the exception's class, or null. The error metric reads codes through the same rule. */
    static String codeOf(Throwable exception) {
        ErrorCode code = exception == null ? null : exception.getClass().getAnnotation(ErrorCode.class);
        return code == null ? null : code.value();
    }
}
