package com.patterncatalyst.shipping.tracking;

/**
 * One entry of the source-call log: which request made the call, which source
 * and operation, the lookup key, and when the call started and ended in
 * milliseconds since the process started.
 */
public record SourceCall(String request, String source, String op, String key, long startMs, long endMs) {}
