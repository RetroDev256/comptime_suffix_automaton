//! ComptimeSuffixAutomaton constructs an optimal code graph for checking if
//! the string "needle" is a substring or suffix of the string "haystack".

const State = struct {
    /// The length of the longest suffix in this state
    suffix_len: usize,
    /// Index of the singular parent state for this state
    link: ?usize,
    /// Index of child transition states
    transitions: [256]?usize,

    fn init(suffix_len: usize, link: ?usize) @This() {
        return .{
            .suffix_len = suffix_len,
            .link = link,
            .transitions = @splat(null),
        };
    }
};

pub fn ComptimeSuffixAutomaton(
    comptime haystack: []const u8,
    comptime options: struct {
        /// Optional: Add an extra branch to exit if the needle is longer than the haystack
        early_exit: bool = false,
    },
) type {
    // The maximum possible number of states is 2*N - 1
    var states: [haystack.len * 2 - 1]State = undefined;
    var states_idx: usize = 0; // tracking the next unused index

    // Add the initial state
    states[states_idx] = .init(0, null);
    states_idx += 1;

    // The index of the state representing the whole string
    var last: usize = 0;

    for (0.., haystack) |str_idx, byte| {
        // Add "r", or the state representing the whole string after adding the byte
        states[states_idx] = .init(str_idx + 1, 0);
        const r_idx: usize = states_idx;
        states_idx += 1;

        // Add edges to "r" and find the "p" that links to "q"
        // "p" is the state we use to follow parent links to find where to add transitions
        // "q" is the state where the search for the new suffix ends just before a mismatch
        var p_idx: ?usize = last;
        while (states[p_idx.?].transitions[byte] == null) {
            states[p_idx.?].transitions[byte] = r_idx;
            p_idx = states[p_idx.?].link;
            if (p_idx == null) break;
        }

        if (p_idx != null) {
            const q_idx: usize = states[p_idx.?].transitions[byte].?;
            const p_suffix_len = states[p_idx.?].suffix_len;

            if (p_suffix_len + 1 == states[q_idx].suffix_len) {
                // There is no need to split "q", just set the correct parent link
                states[r_idx].link = q_idx;
            } else {
                // Split "q" into "clone": a duplicate state of "q" to preserve parent links

                // Copy the edges and parent of "q"
                const clone_idx: usize = states_idx;
                states[clone_idx] = .init(p_suffix_len + 1, states[q_idx].link);
                states[clone_idx].transitions = states[q_idx].transitions;
                states_idx += 1;

                // Make "clone" the new parent of "q" and "r"
                states[q_idx].link = clone_idx;
                states[r_idx].link = clone_idx;

                // Make transitions pointing to "q" point at "clone" instead
                while (states[p_idx.?].transitions[byte] == q_idx) {
                    states[p_idx.?].transitions[byte] = clone_idx;
                    p_idx = states[p_idx.?].link;
                    if (p_idx == null) break;
                }
            }
        }

        // Update the state representing the entire string
        last = r_idx;
    }

    // Calculate terminating nodes (there are at most 2*N - 1 states)
    var state_terminals: [haystack.len * 2 - 1]bool = @splat(false);
    var p_idx: usize = last;
    while (true) {
        state_terminals[p_idx] = true;
        if (states[p_idx].link) |parent| {
            p_idx = parent;
        } else {
            break;
        }
    }

    // Final constructed suffix automaton
    const automaton: [states_idx]State = states[0..states_idx].*;

    // Final constructed suffix automaton terminals list
    const terminals: [states_idx]bool = state_terminals[0..states_idx].*;

    return struct {
        /// returns true if "needle" is in "haystack"
        pub fn substr(needle: []const u8) bool {
            var rem_slice: []const u8 = needle;

            if (options.early_exit) {
                if (rem_slice.len > automaton.len) return false;
            }

            @setEvalBranchQuota(automaton.len * 256);
            state: switch (@as(usize, 0)) {
                inline 0...automaton.len - 1 => |idx| {
                    // Lookup success - we have matched the automaton transitions
                    if (rem_slice.len == 0) return true;
                    // Indexing the transition lookup table - advance the automaton
                    switch (rem_slice[0]) {
                        inline else => |byte| {
                            if (automaton[idx].transitions[byte]) |transition| {
                                rem_slice = rem_slice[1..];
                                continue :state transition;
                            }
                            // A lack of a valid transition is also a lookup failure
                            return false;
                        },
                    }
                },
                else => unreachable,
            }
        }

        /// returns true if "needle" is a suffix of "haystack"
        pub fn suffix(needle: []const u8) bool {
            var rem_slice: []const u8 = needle;

            if (options.early_exit) {
                if (rem_slice.len > automaton.len) return false;
            }

            @setEvalBranchQuota(automaton.len * 256);
            state: switch (@as(usize, 0)) {
                inline 0...automaton.len - 1 => |idx| {
                    // We have reached a final state, but must still check if it is a suffix
                    if (rem_slice.len == 0) return terminals[idx];
                    // Indexing the transition lookup table - advance the automaton
                    switch (rem_slice[0]) {
                        inline else => |byte| {
                            if (automaton[idx].transitions[byte]) |transition| {
                                rem_slice = rem_slice[1..];
                                continue :state transition;
                            }
                            // A lack of a valid transition is also a lookup failure
                            return false;
                        },
                    }
                },
                else => unreachable,
            }
        }
    };
}

test "general usage" {
    const expectEqual = @import("std").testing.expectEqual;
    const TestAutomaton = ComptimeSuffixAutomaton("hello world", .{});

    const substrings: []const []const u8 = &.{
        "",           "h",           "he",      "hel",      "hell",
        "hello",      "hello ",      "hello w", "hello wo", "hello wor",
        "hello worl", "hello world", "e",       "el",       "ell",
        "ello",       "ello ",       "ello w",  "ello wo",  "ello wor",
        "ello worl",  "ello world",  "l",       "ll",       "llo",
        "llo ",       "llo w",       "llo wo",  "llo wor",  "llo worl",
        "llo world",  "l",           "lo",      "lo ",      "lo w",
        "lo wo",      "lo wor",      "lo worl", "lo world", "o",
        "o ",         "o w",         "o wo",    "o wor",    "o worl",
        "o world",    " ",           " w",      " wo",      " wor",
        " worl",      " world",      "w",       "wo",       "wor",
        "worl",       "world",       "o",       "or",       "orl",
        "orld",       "r",           "rl",      "rld",      "l",
        "ld",         "d",
    };

    for (substrings) |needle| {
        try expectEqual(true, TestAutomaton.substr(needle));
    }

    const suffixes: []const []const u8 = &.{
        "hello world", "ello world", "llo world", "lo world",
        "o world",     " world",     "world",     "orld",
        "rld",         "ld",         "d",         "",
    };

    for (suffixes) |needle| {
        try expectEqual(true, TestAutomaton.suffix(needle));
    }

    const invalid_substrings: []const []const u8 = &.{
        "\x00",        "helloo",        "hello  world", "hell world",
        "hello-world", "w0rld",         "HELLO",        "hello  worl",
        "ello  world", "helo",          "hella",        "hellow",
        "helloworld",  "hello wor ld",  "he llo",       "hello  ",
        " hello",      "hello  w",      "helloworld ",  "ello word",
        "hhello",      "helloo world",  "heello world", "hell  o world",
        "h e l l o",   "hell o w orld", "hel lo",       "ello wworld",
        "helloworld!", "hello.world",   "hello_worl",   "worldhello",
        "helloorld",   "ello wrld",     "hllo world",
    };

    for (invalid_substrings) |needle| {
        try expectEqual(false, TestAutomaton.substr(needle));
    }

    const invalid_suffixes: []const []const u8 = &.{
        "\x00",   "hello worl", "hello",    "ello wor", "llo wor",
        "lo wor", "o wor",      " wor",     "wor",      "worl",
        "hell",   "hel",        "he",       "h",        "ello",
        "ello w", "llo w",      "lo w",     "o w",      " w",
        "w",      "wo",         "rld!",     "world!",   "worlds",
        "orld!",  "orlds",      "rld ",     "ld!",      "d!",
        "world_", "worl d",     " wor ld",  " worl  d", "wolrd",
        "worrld", "wo rld",     " wor l d", "wor1d",    "ORLD",
        "orld ",
    };

    for (invalid_suffixes) |needle| {
        try expectEqual(false, TestAutomaton.suffix(needle));
    }
}
