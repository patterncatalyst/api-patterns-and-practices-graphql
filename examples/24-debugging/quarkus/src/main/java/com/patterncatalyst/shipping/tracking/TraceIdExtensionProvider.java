package com.patterncatalyst.shipping.tracking;

import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanContext;
import io.smallrye.graphql.api.ErrorExtensionProvider;
import jakarta.json.Json;
import jakarta.json.JsonValue;

/**
 * extensions.traceId on every execution error: the trace id of the request the
 * error belongs to, the id a client quotes when it reports the problem. SmallRye
 * asks each registered {@link ErrorExtensionProvider} for its value when it
 * serializes an error (the {@code ServiceLoader} file lists this class beside
 * {@link DeclaredErrorCodeProvider}), and {@code error-extension-fields} names the
 * keys that reach the response. The id is not a secret: it identifies the trace,
 * and reading the trace takes access to the observability backend. Errors the
 * engine raises itself get the key from {@link TraceIdInstrumentation}.
 */
public class TraceIdExtensionProvider implements ErrorExtensionProvider {
    @Override
    public String getKey() {
        return "traceId";
    }

    @Override
    public JsonValue mapValueFrom(Throwable exception) {
        SpanContext context = Span.current().getSpanContext();
        return context.isValid() ? Json.createValue(context.getTraceId()) : null;
    }
}
