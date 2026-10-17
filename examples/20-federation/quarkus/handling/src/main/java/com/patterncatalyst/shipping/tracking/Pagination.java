package com.patterncatalyst.shipping.tracking;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import java.util.List;
import java.util.function.Function;

/**
 * Everything the two connections share: the argument rules, the cursor codec
 * and the slice algorithm of the Relay Cursor Connections specification.
 *
 * <p>A cursor is opaque to a client but not to the server: base64url, without
 * padding, of {@code <prefix>|v1|<sort key fields>}. The prefix names the
 * connection, so a cursor from one connection is rejected by another, and the
 * version lets the format change without misreading old cursors.
 * Paging seeks on the sort key; it never counts rows from the start, which is
 * why an insert cannot shift a page.
 */
public final class Pagination {

    public static final int DEFAULT_PAGE_SIZE = 10;
    public static final int MAX_PAGE_SIZE = 50;

    private static final String VERSION = "v1";

    private Pagination() {}

    /** The position of an event in {@code handlingHistory}: newest completion first. */
    public record EventKey(Instant completionTime, int sequence) implements Comparable<EventKey> {

        @Override
        public int compareTo(EventKey other) {
            int byTime = completionTime.compareTo(other.completionTime);
            return byTime != 0 ? byTime : Integer.compare(sequence, other.sequence);
        }
    }

    /**
     * Validated page arguments. Exactly one of {@code first} and {@code last}
     * is set; {@code after} and {@code before} are decoded cursors, or null.
     */
    public record Page<K>(Integer first, Integer last, K after, K before) {}

    /** One page of a connection, in connection order, with both directions answered exactly. */
    public record Slice<T>(List<T> items, boolean hasNext, boolean hasPrevious, int totalCount) {}

    /**
     * Validates the arguments, in this order: the range of each size, then
     * the combination, then each cursor. With neither size the page is the
     * first {@value #DEFAULT_PAGE_SIZE}.
     */
    public static <K> Page<K> page(
            Integer first, String after, Integer last, String before, Function<String, K> decodeCursor) {
        checkSize("first", first);
        checkSize("last", last);
        if (first != null && last != null) {
            throw new BadUserInputException("first and last cannot be combined");
        }
        K afterKey = decode("after", after, decodeCursor);
        K beforeKey = decode("before", before, decodeCursor);
        return first == null && last == null
                ? new Page<>(DEFAULT_PAGE_SIZE, null, afterKey, beforeKey)
                : new Page<>(first, last, afterKey, beforeKey);
    }

    /**
     * The slice algorithm of "Pagination algorithm" in the specification: take
     * the edges after the {@code after} cursor and before the {@code before}
     * cursor, then the first or last N of those. {@code newestFirst} is in
     * connection order, so a larger key comes earlier.
     */
    public static <T, K extends Comparable<K>> Slice<T> slice(
            List<T> newestFirst, Function<T, K> key, Page<K> page) {
        int total = newestFirst.size();
        int start = page.after() == null ? 0 : countAtLeast(newestFirst, key, page.after());
        int end = page.before() == null ? total : countGreaterThan(newestFirst, key, page.before());
        end = Math.max(start, end);
        if (page.first() != null) {
            end = Math.min(end, start + page.first());
        }
        if (page.last() != null) {
            start = Math.max(start, end - page.last());
        }
        return new Slice<>(List.copyOf(newestFirst.subList(start, end)), end < total, start > 0, total);
    }

    // Items at or before the cursor in connection order are those with a key >= the cursor's.
    private static <T, K extends Comparable<K>> int countAtLeast(List<T> items, Function<T, K> key, K cursor) {
        return (int) items.stream().filter(item -> key.apply(item).compareTo(cursor) >= 0).count();
    }

    private static <T, K extends Comparable<K>> int countGreaterThan(List<T> items, Function<T, K> key, K cursor) {
        return (int) items.stream().filter(item -> key.apply(item).compareTo(cursor) > 0).count();
    }

    public static String encodeEvent(EventKey key) {
        return encode("evt", key.completionTime().toString(), Integer.toString(key.sequence()));
    }

    public static EventKey decodeEvent(String cursor) {
        String[] fields = decodeFields(cursor, "evt");
        int sequence = Integer.parseInt(fields[1]);
        if (sequence < 1 || !Integer.toString(sequence).equals(fields[1])) {
            throw new IllegalArgumentException("not a sequence number");
        }
        return new EventKey(parseSeconds(fields[0]), sequence);
    }

    private static String encode(String prefix, String... fields) {
        String text = prefix + "|" + VERSION + "|" + String.join("|", fields);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(text.getBytes(StandardCharsets.UTF_8));
    }

    /** The fields after the prefix and version; throws IllegalArgumentException for any cursor this codec did not issue. */
    private static String[] decodeFields(String cursor, String prefix) {
        byte[] bytes = Base64.getUrlDecoder().decode(cursor);
        // Only the canonical encoding is accepted: no padding, no stray characters.
        if (!Base64.getUrlEncoder().withoutPadding().encodeToString(bytes).equals(cursor)) {
            throw new IllegalArgumentException("not canonical base64url");
        }
        String[] parts = new String(bytes, StandardCharsets.UTF_8).split("\\|", -1);
        if (parts.length != 4 || !parts[0].equals(prefix) || !parts[1].equals(VERSION)) {
            throw new IllegalArgumentException("wrong prefix, version or field count");
        }
        return new String[] {parts[2], parts[3]};
    }

    /** A time in the cursor must be the exact text this codec writes: whole seconds, UTC, a trailing Z. */
    private static Instant parseSeconds(String text) {
        Instant time = Instant.parse(text);
        if (!time.toString().equals(text)) {
            throw new IllegalArgumentException("not a whole-second UTC time");
        }
        return time;
    }

    private static String requireText(String text) {
        if (text.isEmpty()) {
            throw new IllegalArgumentException("empty key");
        }
        return text;
    }

    private static void checkSize(String name, Integer size) {
        if (size != null && (size < 0 || size > MAX_PAGE_SIZE)) {
            throw new BadUserInputException(name + " must be between 0 and " + MAX_PAGE_SIZE);
        }
    }

    private static <K> K decode(String name, String cursor, Function<String, K> decodeCursor) {
        if (cursor == null) {
            return null;
        }
        try {
            return decodeCursor.apply(cursor);
        } catch (RuntimeException e) {
            throw new BadUserInputException(name + " is not a valid cursor for this connection");
        }
    }
}
