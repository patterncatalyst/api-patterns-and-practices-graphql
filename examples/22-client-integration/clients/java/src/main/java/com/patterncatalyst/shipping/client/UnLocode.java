package com.patterncatalyst.shipping.client;

import org.eclipse.microprofile.graphql.Name;

/**
 * The contract's {@code UnLocode} scalar, carried as a string. The typesafe client treats
 * a class with a static {@code of(String)} factory as a scalar; {@code @Name} gives the
 * type name a variable is declared with, and the value is written with {@code toString()}.
 */
@Name("UnLocode")
public record UnLocode(String value) {

    public static UnLocode of(String value) {
        return new UnLocode(value);
    }

    @Override
    public String toString() {
        return value;
    }
}
