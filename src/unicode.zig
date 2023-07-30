const std = @import("std");

// Pulled from: https://www.unicodepedia.com/groups/
const ranges = @embedFile("ranges.txt");
const eval_branch_quota_base = 18500;
const range_count = blk: {
    // This should be related to the number of characters in our embedded file above
    @setEvalBranchQuota(eval_branch_quota_base);
    break :blk std.mem.count(u8, ranges, "\n");
};
const Ranges = struct {
    names: [range_count][]const u8 = undefined,
    starting_codepoints: [range_count]u21 = undefined,
    ending_codepoints: [range_count]u21 = undefined,
    current_inx: usize = 0,
    longest_name_len: usize = 0,

    const Self = @This();

    pub fn first(self: *Self) ?UnicodeGroup {
        self.reset();
        return self.next();
    }
    pub fn reset(self: *Self) void {
        self.current_inx = 0;
    }
    pub fn next(self: *Self) ?UnicodeGroup {
        if (self.current_inx == range_count) return null;
        self.current_inx += 1;
        return self.item(self.current_inx - 1);
    }
    pub fn item(self: Self, index: usize) UnicodeGroup {
        return .{
            .name = self.names[index],
            .starting_codepoint = self.starting_codepoints[index],
            .ending_codepoint = self.ending_codepoints[index],
        };
    }
};

const _all_ranges = blk: {
    @setEvalBranchQuota(eval_branch_quota_base * 2);
    break :blk parseRanges(ranges) catch @compileError("Could not parse ranges.txt");
};

pub fn all_ranges() Ranges {
    return .{
        .names = _all_ranges.names,
        .starting_codepoints = _all_ranges.starting_codepoints,
        .ending_codepoints = _all_ranges.ending_codepoints,
        .longest_name_len = _all_ranges.longest_name_len,
    };
}

pub const UnicodeGroup = struct {
    name: []const u8,
    starting_codepoint: u21,
    ending_codepoint: u21,
};

fn parseRanges(text: []const u8) !Ranges {
    var rc = Ranges{};
    var iterator = std.mem.splitSequence(u8, text, "\n");
    var inx: usize = 0;
    while (iterator.next()) |group|
        if (group.len > 0) {
            const uc = try parseGroup(group);
            rc.names[inx] = uc.name;
            rc.starting_codepoints[inx] = uc.starting_codepoint;
            rc.ending_codepoints[inx] = uc.ending_codepoint;
            rc.longest_name_len = @max(rc.longest_name_len, uc.name.len);
            inx += 1;
        };
    return rc;
}

fn parseGroup(group_text: []const u8) !UnicodeGroup {
    // Basic Latin 	U+0 - U+7F
    var iterator = std.mem.splitSequence(u8, group_text, "\t");
    const name = std.mem.trimRight(u8, iterator.first(), " ");
    const range_text = iterator.next() orelse {
        std.log.err("failed parsing on group '{s}'", .{group_text});
        return error.NoRangeSpecifiedInGroup;
    };
    var range_iterator = std.mem.splitSequence(u8, range_text, " - ");
    const start_text = range_iterator.first();
    const end_text = range_iterator.next() orelse return error.NoEndingCodepointInGroup;
    return UnicodeGroup{
        .name = name,
        .starting_codepoint = try std.fmt.parseUnsigned(u21, start_text[2..], 16),
        .ending_codepoint = try std.fmt.parseUnsigned(u21, end_text[2..], 16),
    };
}

test "check ranges" {
    var parsed_ranges = all_ranges();
    // Entry 8 should be:
    // Cyrillic 	U+400 - U+4FF
    try std.testing.expectEqual(@as(u21, 0x400), parsed_ranges.starting_codepoints[8]);
    try std.testing.expectEqual(@as(u21, 0x4ff), parsed_ranges.ending_codepoints[8]);
    try std.testing.expectEqualStrings("Cyrillic", parsed_ranges.names[8]);

    var range = parsed_ranges.first().?;
    try std.testing.expectEqualStrings("Basic Latin", range.name);
    try std.testing.expectEqual(@as(u21, 0x0), range.starting_codepoint);
    try std.testing.expectEqual(@as(u21, 0x7f), range.ending_codepoint);

    range = parsed_ranges.next().?;
    try std.testing.expectEqualStrings("Latin-1 Supplement", range.name);
    try std.testing.expectEqual(@as(u21, 0x80), range.starting_codepoint);
    try std.testing.expectEqual(@as(u21, 0xff), range.ending_codepoint);
}
