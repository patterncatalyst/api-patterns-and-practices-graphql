package com.patterncatalyst.shipping.tracking;

/** A source that cannot answer: the failure a resolver turns into an execution error. */
public class SourceUnavailableException extends RuntimeException {

    public SourceUnavailableException(String message) {
        super(message);
    }
}
