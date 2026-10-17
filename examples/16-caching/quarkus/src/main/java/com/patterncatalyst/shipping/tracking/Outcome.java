package com.patterncatalyst.shipping.tracking;

import java.util.List;

/**
 * What a bulk source operation returns for one key: the value (null when the
 * owner has nothing under that key) or the failure the owner reported for that
 * key alone. A bulk operation returns one {@code Outcome} per requested key, in
 * the order the keys were asked for.
 */
public record Outcome<T>(T value, RuntimeException failure) {

    public static <T> Outcome<T> found(T value) {
        return new Outcome<>(value, null);
    }

    public static <T> Outcome<T> failed(RuntimeException failure) {
        return new Outcome<>(null, failure);
    }

    /**
     * The values in key order, or the first failure thrown. SmallRye resolves a
     * batch method with one result list, so a failure in any key fails the
     * whole batch (see the README's blast-radius note).
     */
    public static <T> List<T> values(List<Outcome<T>> outcomes) {
        for (Outcome<T> outcome : outcomes) {
            if (outcome.failure() != null) {
                throw outcome.failure();
            }
        }
        return outcomes.stream().map(Outcome::value).toList();
    }
}
