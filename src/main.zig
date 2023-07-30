const std = @import("std");
const builtin = @import("builtin");
const unicode = @import("unicode.zig");
const fontconfig = @import("fontconfig.zig");

const max_unicode: u21 = 0x10FFFD;
const all_chars = blk: {
    var all: [max_unicode + 1]u21 = undefined;
    @setEvalBranchQuota(max_unicode);
    for (0..max_unicode) |i|
        all[i] = i;
    break :blk all;
};
pub fn main() !u8 {
    // TODO: Add back in
    // defer fontconfig.deinit();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    defer bw.flush() catch @panic("could not flush stdout"); // don't forget to flush!
    const stdout = bw.writer();

    // std.os.argv is os specific
    var arg_iterator = std.process.args();
    const arg0 = arg_iterator.next().?;
    const options = parseCommandLine(&arg_iterator) catch |err| {
        if (err == error.UserRequestedHelp) {
            try usage(stdout, arg0);
            return 0;
        }
        try usage(std.io.getStdErr().writer(), arg0);
        return 2;
    };

    var unicode_ranges = unicode.all_ranges();
    if (options.list_groups) {
        defer unicode_ranges.reset();
        while (unicode_ranges.next()) |range| {
            try stdout.print("{s}", .{range.name});
            for (range.name.len..unicode_ranges.longest_name_len + 2) |_|
                try stdout.writeByte(' ');
            try stdout.print("U+{X} - U+{X}\n", .{ range.starting_codepoint, range.ending_codepoint });
        }
        return 0;
    }
    if (options.list_fonts) {
        var fq = fontconfig.FontQuery.init(allocator);
        defer fq.deinit();
        var fl = try fq.fontList(options.pattern);
        var longest_family_name = @as(usize, 0);
        var longest_style_name = @as(usize, 0);
        for (fl.list.items) |f| {
            longest_family_name = @max(f.family.len, longest_family_name);
            longest_style_name = @max(f.style.len, longest_style_name);
        }

        std.sort.insertion(fontconfig.Font, fl.list.items, {}, cmpFont);
        for (fl.list.items) |f| {
            try stdout.print("Family: {s}", .{f.family});
            for (f.family.len..longest_family_name + 1) |_|
                try stdout.writeByte(' ');
            try stdout.print("Chars: {d:5}\tStyle: {s}", .{ f.supported_chars.len, f.style });
            for (f.style.len..longest_style_name + 1) |_|
                try stdout.writeByte(' ');
            try stdout.print("\tName: {s}\n", .{
                f.full_name,
            });
        }
        return 0;
    }
    const exclude_previous = options.fonts != null;
    const fonts: []fontconfig.Font = blk: {
        if (options.fonts == null) break :blk &[_]fontconfig.Font{};
        const fo = options.fonts.?;
        var si = std.mem.splitScalar(u8, fo, ',');
        var fq = fontconfig.FontQuery.init(allocator);
        defer fq.deinit();
        var fl = try fq.fontList(options.pattern);
        // This messes with data after, and we don't need to deinit anyway
        // defer fl.deinit();
        var al = try std.ArrayList(fontconfig.Font).initCapacity(allocator, std.mem.count(u8, fo, ",") + 2);
        defer al.deinit();
        while (si.next()) |font_str| {
            const font = font_blk: {
                for (fl.list.items) |f|
                    if (std.ascii.eqlIgnoreCase(f.family, font_str))
                        break :font_blk f;
                try std.io.getStdErr().writer().print("Error: Font '{s}' not installed", .{font_str});
                return 255;
            };

            al.appendAssumeCapacity(font);
        }
        al.appendAssumeCapacity(.{
            .full_name = "Unsupported",
            .family = "Unsupported by any preferred font",
            .style = "Regular",
            .supported_chars = &all_chars,
        });
        break :blk try al.toOwnedSlice();
    };

    const order_by_range = if (std.ascii.eqlIgnoreCase("font", options.order))
        false
    else if (std.ascii.eqlIgnoreCase("range", options.order))
        true
    else
        null;
    if (order_by_range == null) {
        try std.io.getStdErr().writer().print("Error: Order type '{s}' invalid", .{options.order});
        return 255;
    }
    std.log.debug("{0} prefered fonts:", .{fonts.len - 1});
    for (fonts[0 .. fonts.len - 1]) |f|
        std.log.debug("\t{s}", .{f.family});
    if (options.groups) |group| {
        while (unicode_ranges.next()) |range| {
            var it = std.mem.splitScalar(u8, group, ',');
            while (it.next()) |desired_group| {
                if (std.mem.eql(u8, range.name, desired_group)) {
                    try outputRange(
                        allocator,
                        range.starting_codepoint,
                        range.ending_codepoint,
                        fonts,
                        exclude_previous,
                        order_by_range.?,
                        stdout,
                    );
                }
            }
        }
    } else {
        try outputRange(
            allocator,
            0,
            max_unicode,
            fonts,
            exclude_previous,
            order_by_range.?,
            stdout,
        );
    }

    return 0;
}
fn cmpFont(context: void, a: fontconfig.Font, b: fontconfig.Font) bool {
    _ = context;
    return std.mem.order(u8, a.family, b.family) == .lt; // a.family < b.family;
}
fn cmpRangeList(context: void, a: fontconfig.RangeFont, b: fontconfig.RangeFont) bool {
    _ = context;
    return a.starting_codepoint < b.starting_codepoint;
}
fn formatRangeFontEndingCodepoint(
    data: fontconfig.RangeFont,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = options;
    if (data.starting_codepoint == data.ending_codepoint) return;
    try std.fmt.format(writer, "-{" ++ fmt ++ "}", .{data.ending_codepoint});
}
fn fmtRangeFontEndingCodepoint(range_font: fontconfig.RangeFont) std.fmt.Formatter(formatRangeFontEndingCodepoint) {
    return .{
        .data = range_font,
    };
}
fn outputRange(
    allocator: std.mem.Allocator,
    starting_codepoint: u21,
    ending_codepoint: u21,
    fonts: []const fontconfig.Font,
    exclude_previous: bool,
    order_by_range: bool,
    writer: anytype,
) !void {
    var fq = fontconfig.FontQuery.init(allocator);
    defer fq.deinit();
    var range_fonts = try fq.fontsForRange(starting_codepoint, ending_codepoint, fonts, exclude_previous); // do we want hard limits around this?
    defer allocator.free(range_fonts);

    std.log.debug("Got {d} range fonts back from query", .{range_fonts.len});
    if (order_by_range)
        std.sort.insertion(fontconfig.RangeFont, range_fonts, {}, cmpRangeList);

    for (range_fonts) |range_font| {
        try writer.print("{s}U+{x}{x}={s}\n", .{
            if (std.mem.eql(u8, range_font.font.full_name, "Unsupported")) "#" else "",
            range_font.starting_codepoint,
            fmtRangeFontEndingCodepoint(range_font), //.ending_codepoint,
            range_font.font.family,
        });
    }
}

const Options = struct {
    end_of_options_signifier: ?usize = null,
    groups: ?[]const u8 = null,
    fonts: ?[]const u8 = &[_]u8{},
    list_groups: bool = false,
    list_fonts: bool = false,
    pattern: [:0]const u8 = ":regular:normal:spacing=100:slant=0",
    order: [:0]const u8 = "font",
};

fn usage(writer: anytype, arg0: []const u8) !void {
    try writer.print(
        \\usage: {s} [OPTION]...
        \\
        \\Options:
        \\  -p, --pattern     font pattern to use (Default: :regular:normal:spacing=100:slant=0)
        \\  -g, --groups      group names to process, comma delimited (e.g. Thai,Lao - default is all groups)
        \\  -f, --fonts       prefered fonts in order, comma delimited (e.g. "DejaVu Sans Mono,Hack Nerd Font" - default is all fonts)
        \\                    note this will change the behavior such that ranges supported by the first font found will not
        \\                    be considered for use by subsequent fonts
        \\  -o, --order       order by (Default: font, can also order by range)
        \\  -G, --list-groups list all groups and exit
        \\  -F, --list-fonts  list all fonts matching pattern and exit
        \\  -h, --help        display this help text and exit
        \\
    , .{arg0});
}

fn parseCommandLine(arg_iterator: anytype) !Options {
    var current_arg: usize = 0;
    var rc = Options{};
    while (arg_iterator.next()) |arg| {
        if (std.mem.eql(u8, arg, "--")) {
            rc.end_of_options_signifier = current_arg + 1;
            return rc;
        }
        if (try getArgValue(arg_iterator, arg, "groups", "g", .{})) |val| {
            rc.groups = val;
        } else if (try getArgValue(arg_iterator, arg, "pattern", "p", .{})) |val| {
            rc.pattern = val;
        } else if (try getArgValue(arg_iterator, arg, "fonts", "f", .{})) |val| {
            rc.fonts = val;
        } else if (try getArgValue(arg_iterator, arg, "order", "o", .{})) |val| {
            rc.order = val;
        } else if (try getArgValue(arg_iterator, arg, "list-groups", "G", .{ .is_bool = true })) |_| {
            rc.list_groups = true;
        } else if (try getArgValue(arg_iterator, arg, "list-fonts", "F", .{ .is_bool = true })) |_| {
            rc.list_fonts = true;
        } else if (try getArgValue(arg_iterator, arg, "help", "h", .{ .is_bool = true })) |_| {
            return error.UserRequestedHelp;
        } else {
            if (!builtin.is_test)
                try std.io.getStdErr().writer().print("invalid option: {s}\n\n", .{arg});
            return error.InvalidOption;
        }
        current_arg += 1;
    }
    return rc;
}
const ArgOptions = struct {
    is_bool: bool = false,
    is_required: bool = false,
};
fn getArgValue(
    arg_iterator: anytype,
    arg: [:0]const u8,
    comptime name: ?[]const u8,
    comptime short_name: ?[]const u8,
    arg_options: ArgOptions,
) !?[:0]const u8 {
    if (short_name) |s| {
        if (std.mem.eql(u8, "-" ++ s, arg)) {
            if (arg_options.is_bool) return arg;
            if (arg_iterator.next()) |val| {
                return val;
            } else return error.NoValueOnFlag;
        }
    }
    if (name) |n| {
        if (std.mem.eql(u8, "--" ++ n, arg)) {
            if (arg_options.is_bool) return "";
            if (arg_iterator.next()) |val| {
                return val;
            } else return error.NoValueOnName;
        }
        if (std.mem.startsWith(u8, arg, "--" ++ n ++ "=")) {
            if (arg_options.is_bool) return error.EqualsInvalidForBooleanArgument;
            return arg[("--" ++ n ++ "=").len.. :0];
        }
    }
    return null;
}

// Tests run in this order:
//
// 1. Main file
//    - In order, from top to bottom
// 2. Referenced file(s), if any
//    - In order, from top to bottom
//
// libfontconfig gets inconsistent in a hurry with a lot of init/deinit, so
// we only want to deinit once. Because we have no way of saying "go do other
// tests, then come back", we have no way of controlling deinitialization other
// than something that's not super obvious. So, we're adding this comment.
// We will allow fontconfig tests to do our deinit() call, and we shall ignore
// deinitialization here
test "startup" {
    // std.testing.log_level = .debug;
}
test "command line parses with short name" {
    var it = try std.process.ArgIteratorGeneral(.{}).init(std.testing.allocator, "-g Latin-1");
    defer it.deinit();
    const options = try parseCommandLine(&it);
    try std.testing.expectEqualStrings("Latin-1", options.groups.?);
}
test "command line parses with long name no equals" {
    var it = try std.process.ArgIteratorGeneral(.{}).init(std.testing.allocator, "--groups Latin-1");
    defer it.deinit();
    const options = try parseCommandLine(&it);
    try std.testing.expectEqualStrings("Latin-1", options.groups.?);
}
test "command line parses with long name equals" {
    var log_level = std.testing.log_level;
    defer std.testing.log_level = log_level;
    std.testing.log_level = .debug;
    var it = try std.process.ArgIteratorGeneral(.{}).init(std.testing.allocator, "--groups=Latin-1");
    defer it.deinit();
    const options = try parseCommandLine(&it);
    try std.testing.expectEqualStrings("Latin-1", options.groups.?);
}
test "Get ranges" {
    std.log.debug("get ranges", .{});
    // defer fontconfig.deinit();
    var fq = fontconfig.FontQuery.init(std.testing.allocator);
    defer fq.deinit();
    var fl = try fq.fontList(":regular:normal:spacing=100:slant=0");
    defer fl.deinit();
    try std.testing.expect(fl.list.items.len > 0);
    var matched = blk: {
        for (fl.list.items) |item| {
            std.log.debug("full_name: '{s}'", .{item.full_name});
            if (std.mem.eql(u8, "DejaVu Sans Mono", item.full_name))
                break :blk item;
        }
        break :blk null;
    };
    try std.testing.expect(matched != null);
    const arr: []const fontconfig.Font = &[_]fontconfig.Font{matched.?};
    var al = std.ArrayList(u8).init(std.testing.allocator);
    defer al.deinit();
    const range_name = "Basic Latin";
    var matched_range = try blk: {
        var unicode_ranges = unicode.all_ranges();
        while (unicode_ranges.next()) |range| {
            var it = std.mem.splitScalar(u8, range_name, ',');
            while (it.next()) |desired_range| {
                if (std.mem.eql(u8, range.name, desired_range)) {
                    break :blk range;
                }
            }
        }
        break :blk error.RangeNotFound;
    };
    var log_level = std.testing.log_level;
    std.testing.log_level = .debug;
    defer std.testing.log_level = log_level;
    try outputRange(std.testing.allocator, matched_range.starting_codepoint, matched_range.ending_codepoint, arr, false, al.writer());
    try std.testing.expectEqualStrings(al.items, "U+20-7e=DejaVu Sans Mono\n");

    std.log.debug("\nwhole unicode space:", .{});
    try outputRange(std.testing.allocator, 0, max_unicode, arr, false, al.writer());
    const expected =
        \\U+20-7e=DejaVu Sans Mono
        \\U+20-7e=DejaVu Sans Mono
        \\U+a0-1c3=DejaVu Sans Mono
        \\U+1cd-1e3=DejaVu Sans Mono
        \\U+1e6-1f0=DejaVu Sans Mono
        \\U+1f4-1f6=DejaVu Sans Mono
    ;
    try std.testing.expectStringStartsWith(al.items, expected);

    // try std.testing.expectEqual(@as(usize, 3322), matched.?.supported_chars.len);
}

test "teardown, followed by libraries" {
    std.testing.refAllDecls(@This()); // Only catches public decls
    _ = @import("unicode.zig");
}
