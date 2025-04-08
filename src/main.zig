const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    var automaton: SuffixAutomaton = try .init(gpa);

    // Process each letter in the input string ω.
    const input = "E";
    for (input) |byte| {
        for (0..8) |bit_idx| {
            const bit = byte >> @intCast(7 - bit_idx);
            try automaton.addBit(gpa, @truncate(bit));
        }
    }

    const stdout = std.io.getStdOut().writer();
    try std.zon.stringify.serialize(automaton, .{}, stdout);
}

const State = struct {
    /// The length of the longest suffix suffix in this state
    suffix_len: usize,
    /// Index of the singular parent state for this state
    link: ?usize,
    /// Index of child transition states
    transitions: [256]?usize,

    fn init(suffix_len: usize, parent: usize) @This() {
        return .{
            .suffix_len = suffix_len,
            .parent = parent,
            .transitions = @splat(null),
        };
    }
};

fn SuffixAutomaton(comptime string: []const u8) type {
    // The maximum possible number of states is 2*N - 1
    var states: [string.len * 2 - 1]State = undefined;
    var states_idx: usize = 0; // tracking the next unused index

    // Add the initial state
    states[states_idx] = .init(0, null);
    states_idx += 1;

    // The index of the state representing the whole string
    var last: usize = 0;

    for (0.., string) |str_idx, byte| {
        // Add "r", or the state representing the whole string after adding the byte
        states[states_idx] = .init(str_idx + 1, 0);
        const r_idx: usize = states_idx;
        states_idx += 1;

        // Add edges to "r" and find the "p" that links to "q"
        // "p" is the state we use to follow parent links to find where to add transitions
        // "q" is the state where the search for the new suffix ends just before a mismatch
        var p_idx: ?usize = last;
        while (states[p_idx].transitions[byte] == null) {
            states[p_idx].transitions[byte] = r_idx;
            p_idx = states[p_idx].link;
            if (p_idx == null) break;
        }

        if (p_idx != null) {
            const q_idx: usize = states[p_idx].transitions[byte].?;
            const p_suffix_len = states[p_idx].suffix_len;

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
                while (states[p_idx].transitions[byte] == q_idx) {
                    states[p_idx].transitions[byte] = clone_idx;
                    p_idx = states[p_idx].link;
                    if (p_idx == null) break;
                }
            }
        }

        // Update the state representing the entire string
        last = r_idx;
    }

    // Haha, now we can have fun
}
