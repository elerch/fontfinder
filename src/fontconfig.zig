const std = @import("std");
const unicode = @import("unicode.zig");
const c = @cImport({
    @cInclude("fontconfig/fontconfig.h");
});
const log = std.log.scoped(.fontconfig);

extern fn allCharacters(p: ?*const c.FcPattern, chars: *[*]u32) c_int;
extern fn freeAllCharacters(chars: *[*]usize) void;

pub const RangeFont = struct {
    starting_codepoint: u21,
    ending_codepoint: u21,
    font: Font,
};

pub const Font = struct {
    full_name: []const u8,
    family: []const u8,
    style: []const u8,
    supported_chars: []const u21,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        freeAllCharacters(self.supported_chars.ptr);
    }
};

pub const FontList = struct {
    list: std.ArrayList(Font),
    allocator: std.mem.Allocator,
    pattern: *c.FcPattern,
    fontset: *c.FcFontSet,

    const Self = @This();
    pub fn initCapacity(allocator: std.mem.Allocator, num: usize, pattern: *c.FcPattern, fontset: *c.FcFontSet) std.mem.Allocator.Error!Self {
        var al = try std.ArrayList(Font).initCapacity(allocator, num);
        return Self{
            .allocator = allocator,
            .list = al,
            .pattern = pattern,
            .fontset = fontset,
        };
    }

    pub fn deinit(self: *Self) void {
        c.FcPatternDestroy(self.pattern);
        c.FcFontSetDestroy(self.fontset);
        self.list.deinit();
    }

    pub fn addFontAssumeCapacity(
        self: *Self,
        full_name: []const u8,
        family: []const u8,
        style: []const u8,
        supported_chars: []const u21,
    ) !void {
        self.list.appendAssumeCapacity(.{
            .full_name = full_name,
            .family = family,
            .style = style,
            .supported_chars = supported_chars,
        });
    }
};

var fc_config: ?*c.FcConfig = null;
var deinited = false;
// pub var test_should_deinit = true;
/// De-initializes the underlying c library. Should only be called
/// after all processing has completed
pub fn deinit() void {
    // https://refspecs.linuxfoundation.org/fontconfig-2.6.0/r2370.html
    // Says that "Note that calling this function with the return from FcConfigGetCurrent will place the library in an indeterminate state."
    // However, it seems as though you can't do this either:
    //
    // 1. c.FcInitLoadConfigAndFonts();
    // 2. c.FcConfigDestroy();
    // 3. c.FcInitLoadConfigAndFonts();
    // 4. c.FcConfigDestroy(); // Seg fault here
    if (deinited) @panic("Cannot deinitialize this library more than once");
    deinited = true;
    if (fc_config) |conf| {
        log.debug("destroying config: do not use library or call me again", .{});
        c.FcConfigDestroy(conf);
    }
    fc_config = null;
}

pub const FontQuery = struct {
    allocator: std.mem.Allocator,
    // fc_config: ?*c.FcConfig = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }
    pub fn deinit(self: *Self) void {
        _ = self;
        // if (self.all_fonts) |a| a.deinit();
    }

    pub fn fontList(self: *Self, pattern: [:0]const u8) !FontList {
        if (fc_config == null and deinited) @panic("fontconfig C library is in an inconsistent state - should not use");
        if (fc_config == null) fc_config = c.FcInitLoadConfigAndFonts();
        const config = if (fc_config) |conf| conf else return error.FontConfigInitLoadFailure;

        // Pretty sure we want this...
        const pat = c.FcNameParse(pattern);
        // We cannot destroy the pattern until we're completely done
        // This will be managed by FontList object
        // defer if (pat != null) c.FcPatternDestroy(pat);

        // const pat = c.FcPatternCreate(); // *FcPattern
        // defer if (pat != null) c.FcPatternDestroy(pat);
        //
        // // FC_WEIGHT_NORMAL is 80
        // // This is equivalent to "regular" style
        // if (c.FcPatternAddInteger(pat, c.FC_WEIGHT, c.FC_WEIGHT_NORMAL) != c.FcTrue) return error.FontConfigCouldNotSetPattern;
        //
        // // This is "normal" vs Bold or Italic
        // if (c.FcPatternAddInteger(pat, c.FC_WIDTH, c.FC_WIDTH_NORMAL) != c.FcTrue) return error.FontConfigCouldNotSetPattern;
        //
        // // Monospaced fonts
        // if (c.FcPatternAddInteger(pat, c.FC_SPACING, c.FC_MONO) != c.FcTrue) return error.FontConfigCouldNotSetPattern;
        //
        // // FC_SLANT_ROMAN is 0 (italic 100, oblique 110)
        // if (c.FcPatternAddInteger(pat, c.FC_SLANT, c.FC_SLANT_ROMAN) != c.FcTrue) return error.FontConfigCouldNotSetPattern;
        //
        const os = c.FcObjectSetBuild(c.FC_FAMILY, c.FC_STYLE, c.FC_LANG, c.FC_FULLNAME, c.FC_CHARSET, @as(?*u8, null)); // *FcObjectSet
        defer if (os != null) c.FcObjectSetDestroy(os);
        const fs = c.FcFontList(config, pat, os); // FcFontSet
        // TODO: Move this defer into deinit
        // defer if (fs != null) c.FcFontSetDestroy(fs);

        // Use the following only when needed. NameUnparse allocates memory
        // log.debug("Total matching fonts: {d}. Pattern: {s}\n", .{ fs.*.nfont, c.FcNameUnparse(pat) });
        log.debug("Total matching fonts: {d}", .{fs.*.nfont});
        var rc = try FontList.initCapacity(self.allocator, @as(usize, @intCast(fs.*.nfont)), pat.?, fs.?);
        errdefer rc.deinit();
        for (0..@as(usize, @intCast(fs.*.nfont))) |i| {
            const font = fs.*.fonts[i].?; // *FcPattern
            var fullname: [*:0]c.FcChar8 = undefined;
            var style: [*:0]c.FcChar8 = undefined;
            var family: [*:0]c.FcChar8 = undefined;

            var charset: [*]u21 = undefined;
            const len = allCharacters(font, @ptrCast(&charset));
            if (len < 0) return error.FontConfigCouldNotGetCharSet;

            // https://refspecs.linuxfoundation.org/fontconfig-2.6.0/r600.html
            // Note that these (like FcPatternGet) do not make a copy of any data structure referenced by the return value
            // https://refspecs.linuxfoundation.org/fontconfig-2.6.0/r570.html
            // The value returned is not a copy, but rather refers to the data stored within the pattern directly. Applications must not free this value.
            if (c.FcPatternGetString(font, c.FC_FULLNAME, 0, @as([*c][*c]c.FcChar8, @ptrCast(&fullname))) != c.FcResultMatch)
                fullname = @constCast(@ptrCast("".ptr));
            // return error.FontConfigCouldNotGetFontFullName;

            if (c.FcPatternGetString(font, c.FC_FAMILY, 0, @as([*c][*c]c.FcChar8, @ptrCast(&family))) != c.FcResultMatch)
                return error.FontConfigHasNoFamily;
            if (c.FcPatternGetString(font, c.FC_STYLE, 0, @as([*c][*c]c.FcChar8, @ptrCast(&style))) != c.FcResultMatch)
                return error.FontConfigHasNoStyle;

            log.debug(
                "Chars: {d:5.0} Family '{s}' Style '{s}' Full Name: {s}",
                .{ @as(usize, @intCast(len)), family, style, fullname },
            );

            try rc.addFontAssumeCapacity(
                fullname[0..std.mem.len(fullname)],
                family[0..std.mem.len(family)],
                style[0..std.mem.len(style)],
                charset[0..@as(usize, @intCast(len))],
            );
        }
        return rc;
    }

    pub fn fontsForRange(
        self: *Self,
        starting_codepoint: u21,
        ending_codepoint: u21,
        fonts: []const Font,
        exclude_previous: bool,
    ) ![]RangeFont {
        // const group_len = group.ending_codepoint - group.starting_codepoint;
        var rc = std.ArrayList(RangeFont).init(self.allocator);
        defer rc.deinit();

        var previously_supported = blk: {
            if (!exclude_previous) break :blk null;
            var al = try std.ArrayList(bool).initCapacity(self.allocator, ending_codepoint - starting_codepoint);
            defer al.deinit();
            for (starting_codepoint..ending_codepoint) |_|
                al.appendAssumeCapacity(false);
            break :blk try al.toOwnedSlice();
        };
        defer if (previously_supported) |p| self.allocator.free(p);

        for (fonts) |font| {
            var current_start = @as(u21, 0);
            var current_end = @as(u21, 0);
            var inx = @as(usize, 0);

            var range_count = @as(usize, 0);
            // Advance to the start of the range
            while (inx < font.supported_chars.len and
                font.supported_chars[inx] < starting_codepoint)
                inx += 1;

            while (inx < font.supported_chars.len and
                font.supported_chars[inx] < ending_codepoint)
            {
                if (previously_supported) |p| {
                    if (p[font.supported_chars[inx]]) {
                        inx += 1;
                        continue; // This was already supported - continue
                    }
                }
                // We found the beginning of a range
                current_start = font.supported_chars[inx];
                current_end = font.supported_chars[inx];
                if (previously_supported) |p|
                    p[font.supported_chars[inx]] = true;

                // Advance to the next supported character, then start checking for continuous ranges
                inx += 1;
                while (inx < font.supported_chars.len and
                    font.supported_chars[inx] == current_end + 1 and
                    font.supported_chars[inx] <= ending_codepoint and
                    (!exclude_previous or !previously_supported.?[font.supported_chars[inx]]))
                {
                    if (previously_supported) |p|
                        p[font.supported_chars[inx]] = true;
                    inx += 1;
                    current_end += 1;
                }

                // We've found the end of the range (which could be the end of a group)
                // If we have not hit the stops, inx at this point is at the beginning of
                // a new range
                range_count += 1;
                try rc.append(.{
                    .font = font,
                    .starting_codepoint = current_start,
                    .ending_codepoint = current_end,
                });
            }
        }
        return rc.toOwnedSlice();
    }
};

test {
    std.testing.refAllDecls(@This()); // Only catches public decls
}
test "Get fonts" {
    // std.testing.log_level = .debug;
    log.debug("get fonts", .{});
    var fq = FontQuery.init(std.testing.allocator);
    defer fq.deinit();
    var fl = try fq.fontList(":regular:normal:spacing=100:slant=0");
    defer fl.deinit();
    try std.testing.expect(fl.list.items.len > 0);
    var matched = blk: {
        for (fl.list.items) |item| {
            log.debug("full_name: '{s}'", .{item.full_name});
            if (std.mem.eql(u8, "DejaVu Sans Mono", item.full_name))
                break :blk item;
        }
        break :blk null;
    };
    try std.testing.expect(matched != null);
    try std.testing.expectEqual(@as(usize, 3322), matched.?.supported_chars.len);
}
test {
    // if (test_should_deinit) deinit();
    deinit();
}
