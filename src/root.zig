//! Storage:
//! A show has a slice of Sets.
//! A show has a slice of Performers, sorted lexicographically by Symbol+Number (e.g. C1).
//! Each Set has a slice of Dots, in the same order as the show's slice of performers.
//! Performers can be looked up O(log(n)), the index can be used on any set to find their dot.

const std = @import("std");

pub const Coordinate = struct {
    x: f64,
    y: f64,
};

pub const Scale = struct {
    ratio: Coordinate,

    pub const default = field;

    pub fn translateXTo(self: Scale, x: f64) f64 {
        return self.ratio.x * x;
    }

    pub fn translateYTo(self: Scale, y: f64) f64 {
        return self.ratio.y * y;
    }

    pub fn translateTo(self: Scale, dot: Coordinate) Coordinate {
        return .{
            .x = self.translateXTo(dot.x),
            .y = self.translateYTo(dot.y),
        };
    }

    test translateTo {
        var s = Scale{ .ratio = .{ .x = 2.0, .y = 0.5 } };
        try std.testing.expectEqual(Coordinate{ .x = 2.0, .y = 0.5 }, s.translateTo(Coordinate{ .x = 1.0, .y = 1.0 }));
    }

    pub fn translateXFrom(self: Scale, x: f64) f64 {
        return x / self.ratio.x;
    }

    pub fn translateYFrom(self: Scale, y: f64) f64 {
        return y / self.ratio.y;
    }

    pub fn translateFrom(self: Scale, dot: Coordinate) Coordinate {
        return .{
            .x = self.translateXFrom(dot.x),
            .y = self.translateYFrom(dot.y),
        };
    }

    test translateFrom {
        var s = Scale{ .ratio = .{ .x = 2.0, .y = 0.5 } };
        try std.testing.expectEqual(Coordinate{ .x = 0.5, .y = 2.0 }, s.translateFrom(Coordinate{ .x = 1.0, .y = 1.0 }));
    }

    pub fn translateX(from: Scale, to: Scale, x: f64) f64 {
        return to.translateXTo(from.translateXFrom(x));
    }

    pub fn translateY(from: Scale, to: Scale, y: f64) f64 {
        return to.translateYTo(from.translateYFrom(y));
    }

    pub fn translate(from: Scale, to: Scale, dot: Coordinate) Coordinate {
        return to.translateTo(from.translateFrom(dot));
    }

    test translate {
        const d = Coordinate{ .x = 1.0, .y = 1.0 };
        const s = Scale{ .ratio = .{ .x = 2.0, .y = 0.5 } };
        try std.testing.expectEqual(d, Scale.translate(s, s, d));
    }

    /// Field scale is the canonical scale.
    /// The front sideline is -1.0.
    /// The back sideline is +1.0.
    /// The side 1 goal line is -1.0.
    /// The side 2 goal line is +1.0.
    pub const field = Scale{ .ratio = .{ .x = 1.0, .y = 1.0 } };

    /// A football field is 100 yards long and 160 feet wide.
    pub const foot = Scale{ .ratio = .{ .x = 100.0 * 3.0 / 2.0, .y = 160.0 / 2.0 } };

    /// A football field is 100 yards long and 160 feet wide.
    pub const inch = Scale{ .ratio = .{ .x = 100.0 * 3.0 * 12.0 / 2.0, .y = 160.0 * 12.0 / 2.0 } };

    /// Field length is 8 steps per 5 yards times 100 yards.
    /// Field width is 28 steps FSL to FH, FH to BH, and BH to BSL.
    /// Divide both by 2 becaue the origin is the center of the field.
    pub const step = Scale{ .ratio = .{ .x = 8.0 / 5.0 * 100.0 / 2.0, .y = 28.0 * 3.0 / 2.0 } };

    test "scales" {
        var d = Coordinate{ .x = 1.0, .y = 0.0 };
        var act = Scale.translate(step, inch, d);
        try std.testing.expectEqual(22.5, act.x);
        try std.testing.expectEqual(0.0, act.y);
        d = .{ .x = 0.0, .y = 1.0 };
        act = Scale.translate(step, inch, d);
        try std.testing.expectEqual(0.0, act.x);
        try std.testing.expectApproxEqAbs(22.85, act.y, 0.00999);
        d = .{ .x = 1.0, .y = 1.0 };
        act = Scale.translate(step, inch, d);
        try std.testing.expectEqual(22.5, act.x);
        try std.testing.expectApproxEqAbs(22.85, act.y, 0.00999);
    }
};

test "round trip" {
    const d = Coordinate{ .x = 1.5, .y = -1.0 };
    try std.testing.expectEqual(d, Scale.inch.translateFrom(Scale.inch.translateTo(d)));
    try std.testing.expectEqual(d, Scale.inch.translateTo(Scale.inch.translateFrom(d)));
    try std.testing.expectEqual(d, Scale.step.translateFrom(Scale.step.translateTo(d)));
    try std.testing.expectEqual(d, Scale.step.translateTo(Scale.step.translateFrom(d)));
    try std.testing.expectEqual(d, Scale.translate(Scale.step, Scale.inch, Scale.translate(Scale.inch, Scale.step, d)));
}

pub const Section = struct {
    /// Typically a single uppercase character, but can be any string.
    symbol: []const u8,
    name: []const u8,
};

pub const Performer = struct {
    section: Section,
    number: u8,
};

pub const Dot = struct {
    coordinate: Coordinate,
    performer: Performer,
};

pub const Measures = struct {
    first: u32,
    last: u32,
};

pub const Set = struct {
    performers: []const Performer,
    coordinates: []const Coordinate,
    counts: u32,
    measures: Measures,

    pub fn iterator(self: *const Set) Iterator {
        return .{ .set = self };
    }

    pub const Iterator = struct {
        set: *const Set,
        index: usize,

        pub fn next(self: *Iterator) ?Dot {
            if (self.index < self.set.performers.len) {
                return .{
                    .coordinate = self.set.coordinates[self.index],
                    .performer = self.set.performers[self.index],
                };
            }
            return null;
        }
    };
};

pub const Show = struct {
    const Sections = std.HashMapUnmanaged(Section, void, struct {
        pub fn hash(self: @This(), section: Section) u64 {
            _ = self;
            var hasher = std.hash.Wyhash.init(12345);
            std.hash.autoHashStrat(&hasher, section.symbol, .Deep);
            return hasher.final();
        }
        pub fn eql(self: @This(), l: Section, r: Section) bool {
            _ = self;
            return std.mem.eql(u8, l.symbol, r.symbol) and std.mem.eql(u8, l.name, r.name);
        }
    }, 80);

    allocator: std.mem.Allocator,
    sections: Sections = .empty,
    performers: std.ArrayList([]const Performer) = .{},
    /// Show dots are stored in their canonical form where the range -1:1 is one football field.
    coordinates: std.ArrayList([]const Coordinate) = .{},
    counts: std.ArrayList(u32) = .{},
    measures: std.ArrayList(u32) = .{},
    set_names: std.ArrayList([]const u8) = .{},

    pub fn init(allocator: std.mem.Allocator) Show {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Show) void {
        self.sections.deinit(self.allocator);
        self.coordinates.deinit(self.allocator);
        self.counts.deinit(self.allocator);
        self.measures.deinit(self.allocator);
        self.set_names.deinit(self.allocator);
    }

    pub fn addSection(self: *Show, section: Section) !Sections.GetOrPutResult {
        return self.sections.getOrPut(self.allocator, section);
    }

    pub fn addSet(self: *Show, name: []const u8, coordinates: []const Coordinate, counts: u32, measures: u32) !void {
        try self.set_names.append(self.allocator, name);
        try self.coordinates.append(self.allocator, coordinates);
        try self.counts.append(self.allocator, counts);
        try self.measures.append(self.allocator, measures);
    }

    pub fn getMeasures(self: Show, index: usize) Measures {
        var first: u32 = 1;
        for (self.measures.items[0..index]) |m| {
            first += m;
        }
        return .{ .first = first, .last = first + self.measures.items[index] - 1 };
    }

    pub fn iterator(self: *const Show) Iterator {
        return .{ .show = self };
    }

    pub const Iterator = struct {
        show: *const Show,
        index: usize,

        pub fn next(self: *Iterator) ?Set {
            if (self.index < self.show.coordinates.len) {
                return .{
                    .performers = self.show.performers,
                    .coordinates = self.show.coordinates[self.index],
                    .counts = self.show.counts[self.index],
                    .measures = self.show.getMeasures(self.index),
                    .name = self.show.set_names[self.index],
                };
            }
            return null;
        }
    };
};

test Show {
    var show = Show.init(std.testing.allocator);
    defer show.deinit();

    _ = try show.addSection(.{ .symbol = "A", .name = "alto saxophone" });
    _ = try show.addSection(.{ .symbol = "B", .name = "baritone" });
    _ = try show.addSection(.{ .symbol = "C", .name = "clarinet" });
    _ = try show.addSection(.{ .symbol = "G", .name = "colorguard" });
    _ = try show.addSection(.{ .symbol = "D", .name = "bass drum" });
    _ = try show.addSection(.{ .symbol = "F", .name = "flute" });
    _ = try show.addSection(.{ .symbol = "M", .name = "mellophone" });
    _ = try show.addSection(.{ .symbol = "N", .name = "tenor saxophone" });
    _ = try show.addSection(.{ .symbol = "R", .name = "trombone" });
    _ = try show.addSection(.{ .symbol = "T", .name = "trumpet" });
    _ = try show.addSection(.{ .symbol = "S", .name = "snare drum" });
    _ = try show.addSection(.{ .symbol = "U", .name = "tuba" });

    try show.addSet("0", &[_]Coordinate{}, 4, 1);
    try show.addSet("1", &[_]Coordinate{}, 8, 2);
    try show.addSet("2", &[_]Coordinate{}, 8, 2);
    try show.addSet("2A", &[_]Coordinate{}, 1, 4);
    try std.testing.expectEqual(Measures{ .first = 1, .last = 1 }, show.getMeasures(0));
    try std.testing.expectEqual(Measures{ .first = 2, .last = 3 }, show.getMeasures(1));
    try std.testing.expectEqual(Measures{ .first = 4, .last = 5 }, show.getMeasures(2));
    try std.testing.expectEqual(Measures{ .first = 6, .last = 9 }, show.getMeasures(3));
}

test {
    // Step scale.
    const c1_coords = [_]Coordinate{
        .{ .x = -16.0, .y = -14.0 },
    };
    try std.testing.expectEqual(Coordinate{ .x = -360.0, .y = -320.0 }, Scale.translate(Scale.step, Scale.inch, c1_coords[0]));
}
