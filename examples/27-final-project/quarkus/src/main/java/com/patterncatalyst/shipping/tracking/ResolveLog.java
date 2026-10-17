package com.patterncatalyst.shipping.tracking;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

import org.jboss.logging.Logger;

/**
 * The application's debug category for reference resolution. At DEBUG, each
 * reference resolver writes one line per distinct key after its bulk read
 * returns: {@code resolve <Type.field> key=<key> outcome=<found|missing>}. The
 * category is {@code INFO} by default and carries reference keys only: a
 * UN/LOCODE or a voyage number, never a token, a variable value or an owner.
 * The level is a logging property (see application.properties).
 */
final class ResolveLog {

    static final String CATEGORY = "com.patterncatalyst.shipping.tracking.resolve";

    private static final Logger LOG = Logger.getLogger(CATEGORY);

    private ResolveLog() {}

    /** One line per distinct key of a bulk read; a key whose owner failed is not logged. */
    static <T> void batch(String coordinate, List<String> keys, List<Outcome<T>> outcomes) {
        if (!LOG.isDebugEnabled()) {
            return;
        }
        Set<String> seen = new HashSet<>();
        for (int i = 0; i < keys.size(); i++) {
            Outcome<T> outcome = outcomes.get(i);
            if (outcome.failure() == null && seen.add(keys.get(i))) {
                LOG.debugf(
                        "resolve %s key=%s outcome=%s", coordinate, keys.get(i), outcome.value() == null ? "missing" : "found");
            }
        }
    }
}
