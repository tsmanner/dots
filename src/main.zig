const std = @import("std");
const dots = @import("dots");
const xml = @import("xml.zig");

const pixel = dots.Scale{ .ratio = .{ .x = 800, .y = -426 } };

pub const LeftToRight = struct {
    side: Side,
    direction: Direction,
    yard_line: u32,
    steps: f64,

    pub fn ltr(steps: f64, direction: Direction, side: Side, yard_line: u32) LeftToRight {
        return .{
            .side = side,
            .direction = direction,
            .yard_line = yard_line,
            .steps = steps,
        };
    }

    pub fn delta(self: LeftToRight) f64 {
        if (self.side == .middle) {
            return 0;
        }
        const line = dots.Scale.foot.translateXFrom(@as(f64, @floatFromInt((50 - self.yard_line) * 3)));
        const dx = dots.Scale.step.translateXFrom(self.steps);
        const x_abs = switch (self.direction) {
            .on => line,
            // Numbers get smaller, closer to the origin.
            .inside => line - dx,
            // Numbers get bigger, farther from the origin.
            .outside => line + dx,
        };
        switch (self.side) {
            // Never hit because if side is middle we return early.
            .middle => {
                @branchHint(.cold);
                return 0;
            },
            .side1 => return -x_abs,
            .side2 => return x_abs,
        }
    }

    pub const Side = enum { middle, side1, side2 };
    pub const Direction = enum { on, inside, outside };
};

pub const FrontToBack = struct {
    direction: Direction,
    marking: Marking,
    steps: f64,

    const hash_dy = dots.Scale.inch.translateYFrom(53 * 12 + 4);

    pub fn ftb(steps: f64, direction: Direction, marking: Marking) FrontToBack {
        return .{
            .direction = direction,
            .marking = marking,
            .steps = steps,
        };
    }

    pub fn delta(self: FrontToBack) f64 {
        const marking_y = switch (self.marking) {
            .back_side_line => 1.0,
            .back_hash => 1.0 - hash_dy,
            .front_hash => -1.0 + hash_dy,
            .front_side_line => -1.0,
        };
        const dy = dots.Scale.step.translateYFrom(self.steps);
        return switch (self.direction) {
            .on => marking_y,
            // Numbers get bigger.
            .behind => marking_y + dy,
            // Numbers get smaller.
            .in_front_of => marking_y - dy,
        };
    }

    pub const Direction = enum { on, behind, in_front_of };
    pub const Marking = enum { back_side_line, back_hash, front_hash, front_side_line };
};

test {
    const tolerance = 0.0000000001;
    const midfield = dots.Coordinate{ .x = 0, .y = 0 };
    {
        const result = dots.Coordinate{ .x = LeftToRight.ltr(0, .inside, .side1, 50).delta(), .y = FrontToBack.ftb(14.0, .behind, .front_hash).delta() };
        try std.testing.expectApproxEqAbs(midfield.x, result.x, tolerance);
        try std.testing.expectApproxEqAbs(midfield.y, result.y, tolerance);
    }
    {
        const result = dots.Coordinate{ .x = LeftToRight.ltr(0, .outside, .side1, 50).delta(), .y = FrontToBack.ftb(14.0, .in_front_of, .back_hash).delta() };
        try std.testing.expectApproxEqAbs(midfield.x, result.x, tolerance);
        try std.testing.expectApproxEqAbs(midfield.y, result.y, tolerance);
    }
    {
        const result = dots.Coordinate{ .x = LeftToRight.ltr(0, .inside, .side2, 50).delta(), .y = FrontToBack.ftb(42.0, .behind, .front_side_line).delta() };
        try std.testing.expectApproxEqAbs(midfield.x, result.x, tolerance);
        try std.testing.expectApproxEqAbs(midfield.y, result.y, tolerance);
    }
    {
        const result = dots.Coordinate{ .x = LeftToRight.ltr(0, .outside, .side2, 50).delta(), .y = FrontToBack.ftb(42.0, .in_front_of, .back_side_line).delta() };
        try std.testing.expectApproxEqAbs(midfield.x, result.x, tolerance);
        try std.testing.expectApproxEqAbs(midfield.y, result.y, tolerance);
    }
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), dots.Scale.step.translateXFrom(8.0), tolerance);
    {
        const result = dots.Coordinate{ .x = LeftToRight.ltr(8, .inside, .side1, 45).delta(), .y = FrontToBack.ftb(14.0, .behind, .front_hash).delta() };
        try std.testing.expectApproxEqAbs(midfield.x, result.x, tolerance);
        try std.testing.expectApproxEqAbs(midfield.y, result.y, tolerance);
    }
    {
        const result = dots.Coordinate{ .x = LeftToRight.ltr(8, .inside, .side2, 45).delta(), .y = FrontToBack.ftb(14.0, .behind, .front_hash).delta() };
        try std.testing.expectApproxEqAbs(midfield.x, result.x, tolerance);
        try std.testing.expectApproxEqAbs(midfield.y, result.y, tolerance);
    }
}

fn skipWs(s: *std.Io.Reader) !void {
    while (true) {
        switch (try s.peekByte()) {
            ' ', '\t', '\n', '\r' => s.toss(1),
            else => break,
        }
    }
}

fn parseSet(s: *std.Io.Reader) ![]const u8 {
    try skipWs(s);
    return try s.takeDelimiterExclusive(' ');
}

fn parseLetter(s: *std.Io.Reader) !?[]const u8 {
    try skipWs(s);
    switch (try s.peekByte()) {
        '0'...'9' => return null,
        else => {},
    }
    return try s.takeDelimiterExclusive(' ');
}

fn parseCounts(s: *std.Io.Reader) !usize {
    try skipWs(s);
    return try std.fmt.parseInt(usize, try s.takeDelimiterExclusive(' '), 10);
}

fn parseSide(s: *std.Io.Reader, ltr: *LeftToRight) !void {
    try skipWs(s);
    // Skip "Side"
    _ = try s.discardDelimiterExclusive(' ');
    try skipWs(s);
    ltr.side = switch (std.fmt.parseInt(usize, try s.takeDelimiterExclusive(':'), 10) catch return error.InvalidSide) {
        1 => .side1,
        2 => .side2,
        else => return error.SideOutOfRange,
    };
}

fn parseSteps(s: *std.Io.Reader) !f64 {
    try skipWs(s);
    const token = try s.takeDelimiterExclusive(' ');
    const steps = std.fmt.parseFloat(f64, token) catch return error.InvalidStepNumber;
    try skipWs(s);
    // Skip "steps"
    _ = try s.discardDelimiterExclusive(' ');
    return steps;
}

fn parseLtrDirection(s: *std.Io.Reader, ltr: *LeftToRight) !void {
    try skipWs(s);
    {
        const token = try s.peekDelimiterExclusive(' ');
        if (std.mem.eql(u8, token, "On") or std.mem.eql(u8, token, "on")) {
            ltr.steps = 0;
            ltr.direction = .on;
            _ = try s.discard(.limited(token.len));
            return;
        }
    }
    ltr.steps = try parseSteps(s);
    try skipWs(s);
    const token = try s.takeDelimiterExclusive(' ');
    if (std.mem.eql(u8, token, "outside")) {
        ltr.direction = .outside;
    } else if (std.mem.eql(u8, token, "inside")) {
        ltr.direction = .inside;
    } else {
        return error.InvalidLeftToRightDirection;
    }
}

fn parseYardLine(s: *std.Io.Reader, ltr: *LeftToRight) !void {
    try skipWs(s);
    ltr.yard_line = std.fmt.parseInt(u32, try s.takeDelimiterExclusive(' '), 10) catch return error.InvalidYardLine;
    try skipWs(s);
    // Skip "yd"
    _ = try s.discardDelimiterExclusive(' ');
    try skipWs(s);
    // Skip "ln"
    _ = try s.discardDelimiterExclusive(' ');
}

fn parseLeftToRight(s: *std.Io.Reader) !LeftToRight {
    var result: LeftToRight = undefined;
    try skipWs(s);
    const token = try s.peekDelimiterExclusive(' ');
    if (std.mem.eql(u8, token, "Side")) {
        try parseSide(s, &result);
        try parseLtrDirection(s, &result);
        try parseYardLine(s, &result);
        if (result.direction == .on and result.yard_line == 50) {
            result.side = .middle;
        }
    } else {
        result.side = .middle;
        try parseLtrDirection(s, &result);
        try parseYardLine(s, &result);
        // Make sure the rest of the coordinate makes sense.
        if (result.direction != .on) {
            std.debug.print("Direction: {}\n", .{result.direction});
            return error.MissingSideWithDirection;
        } else if (result.yard_line != 50) {
            std.debug.print("Yard Line: {}\n", .{result.yard_line});
            return error.MissingSideWithYardLine;
        } else if (!std.math.approxEqAbs(f64, result.steps, 0.0, 0.00001)) {
            std.debug.print("Steps: {}\n", .{result.steps});
            return error.MissingSideWithSteps;
        }
    }
    return result;
}

fn parseFtbDirection(s: *std.Io.Reader, ftb: *FrontToBack) !void {
    try skipWs(s);
    {
        const token = try s.peekDelimiterExclusive(' ');
        if (std.mem.eql(u8, token, "On") or std.mem.eql(u8, token, "on")) {
            ftb.steps = 0;
            ftb.direction = .on;
            _ = try s.discard(.limited(token.len));
            return;
        }
    }
    ftb.steps = try parseSteps(s);
    try skipWs(s);
    const token = try s.takeDelimiterExclusive(' ');
    if (std.mem.eql(u8, token, "behind")) {
        ftb.direction = .behind;
    } else if (std.mem.eql(u8, token, "in")) {
        // Discard "front"
        try skipWs(s);
        _ = try s.discardDelimiterExclusive(' ');
        // Discard "of"
        try skipWs(s);
        _ = try s.discardDelimiterExclusive(' ');
        ftb.direction = .in_front_of;
    } else {
        std.debug.print("FTB Direction '{s}'\n", .{token});
        return error.InvalidFrontToBackDirection;
    }
}

fn parseMarking(s: *std.Io.Reader, ftb: *FrontToBack) !void {
    try skipWs(s);
    // Match
    //   Back side line
    //   Back Hash (BH)
    //   Front Hash (FH)
    //   Front side line
    const token = try s.take(if (try s.peekByte() == 'B') 14 else 15);
    if (std.mem.eql(u8, token, "Back side line")) {
        ftb.marking = .back_side_line;
    } else if (std.mem.eql(u8, token, "Back Hash (HS)")) {
        ftb.marking = .back_hash;
    } else if (std.mem.eql(u8, token, "Front Hash (HS)")) {
        ftb.marking = .front_hash;
    } else if (std.mem.eql(u8, token, "Front side line")) {
        ftb.marking = .front_side_line;
    } else {
        std.debug.print("FTB marking '{s}'\n", .{token});
        return error.InvalidFrontToBackDirection;
    }
}

fn parseFrontToBack(s: *std.Io.Reader) !FrontToBack {
    var result: FrontToBack = undefined;
    try parseFtbDirection(s, &result);
    try parseMarking(s, &result);
    return result;
}

pub const ParsedCoordinate = struct {
    set: []const u8,
    letter: ?[]const u8,
    counts: usize,
    ltr: LeftToRight,
    ftb: FrontToBack,

    pub fn canonical(self: ParsedCoordinate) dots.Coordinate {
        return .{ .x = self.ltr.delta(), .y = self.ftb.delta() };
    }
};

fn parseCoordinate(s: *std.Io.Reader) !ParsedCoordinate {
    const set = try parseSet(s);
    const letter = try parseLetter(s);
    const counts = try parseCounts(s);
    const ltr = try parseLeftToRight(s);
    const ftb = try parseFrontToBack(s);
    return .{ .set = set, .letter = letter, .counts = counts, .ltr = ltr, .ftb = ftb };
}

/// Caller owns the memory.
fn parseCoordinates(allocator: std.mem.Allocator, s: *std.Io.Reader) ![]ParsedCoordinate {
    var coordinates: std.ArrayList(ParsedCoordinate) = .empty;
    while (true) {
        try coordinates.append(allocator, parseCoordinate(s) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        });
        skipWs(s) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
    }
    return coordinates.toOwnedSlice(allocator);
}

test parseCoordinate {
    for (&[_]std.meta.Tuple(&[_]type{ []const u8, ParsedCoordinate }){
        .{
            "2 A 16 Side 1: 3.0 steps outside 50 yd ln 9.0 steps in front of Front Hash (HS)",
            ParsedCoordinate{
                .set = "2",
                .letter = "A",
                .counts = 16,
                .ltr = .{ .side = .side1, .steps = 3.0, .direction = .outside, .yard_line = 50 },
                .ftb = .{ .steps = 9.0, .direction = .in_front_of, .marking = .front_hash },
            },
        },
        .{
            "3A 8 Side 2: On 45 yd ln On Back Hash (HS)",
            ParsedCoordinate{
                .set = "3A",
                .letter = null,
                .counts = 8,
                .ltr = .{ .side = .side2, .steps = 0.0, .direction = .on, .yard_line = 45 },
                .ftb = .{ .steps = 0.0, .direction = .on, .marking = .back_hash },
            },
        },
    }) |t| {
        const line = t[0];
        const exp = t[1];
        var s = std.io.Reader.fixed(line);
        const act = try parseCoordinate(&s);
        try std.testing.expectEqualDeep(exp, act);
    }
}

test parseCoordinates {
    var s = std.Io.Reader.fixed(
        \\0 0 Side 1: On 40 yd ln On Front Hash (HS)
        \\1 A 72 Side 1: On 40 yd ln On Front Hash (HS)
        \\2 16 Side 1: 3.0 steps outside 50 yd ln 9.0 steps in front of Front Hash (HS)
        \\3B 24 Side 1: On 40 yd ln 1.0 steps behind Front side line
        \\4 C 16 Side 1: 2.25 steps inside 30 yd ln 3.75 steps behind Front side line
        \\5 8 Side 1: 1.75 steps inside 35 yd ln 0.75 steps in front of Front side line
        \\7A 8 Side 1: On 50 yd ln 4.0 steps behind Front side line
        \\8 10 Side 2: 1.5 steps inside 45 yd ln 6.25 steps behind Front side line
        \\16 16 On 50 yd ln 1.0 steps behind Front side line
    );
    const acts = try parseCoordinates(std.testing.allocator, &s);
    defer std.testing.allocator.free(acts);
    const exps: []const ParsedCoordinate = &[_]ParsedCoordinate{
        .{
            .set = "0",
            .letter = null,
            .counts = 0,
            .ltr = .{ .side = .side1, .steps = 0.0, .direction = .on, .yard_line = 40 },
            .ftb = .{ .steps = 0.0, .direction = .on, .marking = .front_hash },
        },
        .{
            .set = "1",
            .letter = "A",
            .counts = 72,
            .ltr = .{ .side = .side1, .steps = 0.0, .direction = .on, .yard_line = 40 },
            .ftb = .{ .steps = 0.0, .direction = .on, .marking = .front_hash },
        },
        .{
            .set = "2",
            .letter = null,
            .counts = 16,
            .ltr = .{ .side = .side1, .steps = 3.0, .direction = .outside, .yard_line = 50 },
            .ftb = .{ .steps = 9.0, .direction = .in_front_of, .marking = .front_hash },
        },
        .{
            .set = "3B",
            .letter = null,
            .counts = 24,
            .ltr = .{ .side = .side1, .steps = 0.0, .direction = .on, .yard_line = 40 },
            .ftb = .{ .steps = 1.0, .direction = .behind, .marking = .front_side_line },
        },
        .{
            .set = "4",
            .letter = "C",
            .counts = 16,
            .ltr = .{ .side = .side1, .steps = 2.25, .direction = .inside, .yard_line = 30 },
            .ftb = .{ .steps = 3.75, .direction = .behind, .marking = .front_side_line },
        },
        .{
            .set = "5",
            .letter = null,
            .counts = 8,
            .ltr = .{ .side = .side1, .steps = 1.75, .direction = .inside, .yard_line = 35 },
            .ftb = .{ .steps = 0.75, .direction = .in_front_of, .marking = .front_side_line },
        },
        .{
            .set = "7A",
            .letter = null,
            .counts = 8,
            .ltr = .{ .side = .middle, .steps = 0.0, .direction = .on, .yard_line = 50 },
            .ftb = .{ .steps = 4.0, .direction = .behind, .marking = .front_side_line },
        },
        .{
            .set = "8",
            .letter = null,
            .counts = 10,
            .ltr = .{ .side = .side2, .steps = 1.5, .direction = .inside, .yard_line = 45 },
            .ftb = .{ .steps = 6.25, .direction = .behind, .marking = .front_side_line },
        },
        .{
            .set = "16",
            .letter = null,
            .counts = 16,
            .ltr = .{ .side = .middle, .steps = 0.0, .direction = .on, .yard_line = 50 },
            .ftb = .{ .steps = 1.0, .direction = .behind, .marking = .front_side_line },
        },
    };
    for (exps, acts) |exp, act| {
        try std.testing.expectEqualDeep(exp, act);
    }
}

pub fn main() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    // C1,2,,16,Side 1: 3.0 steps outside 50 yd ln,9.0 steps in front of Front Hash (HS)
    const clarinet = dots.Section{ .symbol = "C", .name = "clarinet" };
    const c1 = dots.Performer{ .section = clarinet, .number = 1 };
    var s = std.Io.Reader.fixed(
        \\0 0 Side 1: On 40 yd ln On Front Hash (HS)
        \\1 A 72 Side 1: On 40 yd ln On Front Hash (HS)
        \\2 16 Side 1: 3.0 steps outside 50 yd ln 9.0 steps in front of Front Hash (HS)
        \\3 18 Side 1: On 40 yd ln 1.0 steps behind Front side line
        \\3A B 8 Side 1: On 40 yd ln 1.0 steps behind Front side line
        \\3B 24 Side 1: On 40 yd ln 1.0 steps behind Front side line
        \\4 C 16 Side 1: 2.25 steps inside 30 yd ln 3.75 steps behind Front side line
        \\5 8 Side 1: 1.75 steps inside 35 yd ln 0.75 steps in front of Front side line
        \\6 8 Side 1: 2.75 steps inside 40 yd ln 0.25 steps behind Front side line
        \\7 8 Side 1: On 45 yd ln On Front side line
        \\7A 8 Side 1: On 50 yd ln 4.0 steps behind Front side line
        \\8 10 Side 2: 1.5 steps inside 45 yd ln 6.25 steps behind Front side line
        \\9 16 Side 2: 1.5 steps inside 45 yd ln 6.25 steps behind Front side line
        \\9 0 Side 2: 1.5 steps inside 45 yd ln 6.25 steps behind Front side line
        \\10 12 Side 2: On 45 yd ln 10.0 steps behind Front side line
        \\11 16 Side 1: On 45 yd ln 4.0 steps behind Front side line
        \\12 D 16 Side 1: 2.0 steps outside 35 yd ln 8.0 steps behind Front side line
        \\13 12 Side 1: 2.0 steps outside 35 yd ln 8.0 steps behind Front side line
        \\13A E 12 Side 1: 2.0 steps outside 35 yd ln 8.0 steps behind Front side line
        \\14 16 Side 1: On 45 yd ln On Front side line
        \\15 F 16 On 50 yd ln 1.0 steps behind Front side line
        \\16 16 On 50 yd ln 1.0 steps behind Front side line
        \\17 12 On 50 yd ln 1.0 steps behind Front side line
        \\18 G 8 On 50 yd ln 1.0 steps behind Front side line
        \\19 H 16 Side 1: 1.75 steps outside 50 yd ln 0.25 steps in front of Front side line
        \\20 16 Side 2: 1.25 steps inside 45 yd ln 13.25 steps in front of Front Hash (HS)
        \\21 16 Side 2: 3.5 steps outside 40 yd ln 4.25 steps behind Front Hash (HS)
        \\21A I 12 Side 2: 3.5 steps outside 40 yd ln 4.25 steps behind Front Hash (HS)
        \\22 16 Side 2: 4.0 steps outside 35 yd ln 4.0 steps in front of Front Hash (HS)
        \\22A 39 Side 2: 4.0 steps outside 35 yd ln 4.0 steps in front of Front Hash (HS)
        \\23 8 Side 2: 2.0 steps inside 30 yd ln 2.0 steps in front of Front Hash (HS)
        \\24 8 Side 2: 2.0 steps inside 30 yd ln 2.0 steps in front of Front Hash (HS)
        \\25 8 Side 2: 4.0 steps outside 35 yd ln On Front Hash (HS)
        \\26 8 Side 2: 2.0 steps inside 30 yd ln 4.0 steps behind Front Hash (HS)
        \\26A 8 Side 2: 3.0 steps outside 30 yd ln 2.0 steps in front of Front Hash (HS)
        \\27 8 Side 2: On 25 yd ln 8.0 steps in front of Front Hash (HS)
        \\27A 8 Side 2: 3.75 steps inside 20 yd ln 13.25 steps behind Front side line
        \\28 8 Side 2: 1.0 steps outside 20 yd ln 6.5 steps behind Front side line
        \\28A 16 Side 2: 1.0 steps outside 20 yd ln 6.5 steps behind Front side line
        \\29 0 Side 2: 3.25 steps outside 20 yd ln 6.5 steps behind Front side line
        \\29A 4 Side 2: 3.25 steps outside 20 yd ln 6.5 steps behind Front side line
        \\30 16 Side 2: 4.0 steps outside 20 yd ln 7.0 steps in front of Front Hash (HS)
        \\31 8 Side 2: 4.0 steps outside 20 yd ln 7.0 steps in front of Front Hash (HS)
        \\32 8 Side 2: 1.0 steps inside 20 yd ln 4.0 steps behind Front side line
        \\32A 8 Side 2: 1.0 steps inside 20 yd ln 4.0 steps behind Front side line
        \\33 8 Side 2: 3.0 steps inside 25 yd ln 1.0 steps behind Front side line
        \\33A 22 Side 2: 3.0 steps inside 25 yd ln 1.0 steps behind Front side line
        \\34 16 Side 2: 3.0 steps inside 25 yd ln 1.0 steps behind Front side line
        \\34A 4 Side 2: 3.0 steps inside 25 yd ln 1.0 steps behind Front side line
        \\35 16 Side 2: 3.0 steps inside 25 yd ln 1.0 steps behind Front side line
        \\36 16 Side 2: On 30 yd ln 2.0 steps in front of Front side line
        \\36A 38 Side 2: On 30 yd ln 2.0 steps in front of Front side line
    );

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var doc = try xml.Document.init(allocator, stdout, .pretty);

    try doc.open(.svg, .{
        .version = "1.1",
        .viewBox = xml.lazy("{} {} {} {}", .{ -1000, -500, 2000, 1000 }),
        .xmlns = "http://www.w3.org/2000/svg",
    });

    try doc.open(.style, .{});
    try doc.printIndent();
    _ = try doc.writer.write("svg { background-color: gray; stroke: black }\n");
    try doc.close();
    const back = pixel.translateYTo(1.0);
    // const back_hash = pixel.translateYTo(1.0 - FrontToBack.hash_dy);
    const front = pixel.translateYTo(-1.0);
    // const front_hash = pixel.translateYTo(-1.0 + FrontToBack.hash_dy);
    const left = pixel.translateXTo(-1.0);
    const right = pixel.translateXTo(1.0);
    // Back side line
    try doc.selfClose(.line, .{ .x1 = left, .y1 = back, .x2 = right, .y2 = back });
    // Front side line
    try doc.selfClose(.line, .{ .x1 = left, .y1 = front, .x2 = right, .y2 = front });
    // 50 yard line
    try doc.selfClose(.line, .{ .x1 = 0, .y1 = back, .x2 = 0, .y2 = front });
    // 45 down to 0 yard line.
    for (1..11) |i| {
        const pixel_dx = dots.Scale.translateX(.foot, pixel, @as(f64, @floatFromInt(i * 15)));
        try doc.selfClose(.line, .{ .x1 = pixel_dx, .y1 = back, .x2 = pixel_dx, .y2 = front });
        try doc.selfClose(.line, .{ .x1 = -pixel_dx, .y1 = back, .x2 = -pixel_dx, .y2 = front });
    }

    const coords = try parseCoordinates(allocator, &s);
    var prev: ?dots.Coordinate = null;
    _ = c1;
    for (coords) |*coord| {
        const c = pixel.translateTo(coord.canonical());
        try doc.open(.g, .{ .transform = xml.lazy("translate({}, {})", .{ c.x, c.y }) });
        try doc.selfClose(.circle, .{ .r = 2, .fill = "black" });
        // Translate the text and the line connecting it to the dot together.
        try doc.open(.g, .{ .transform = xml.lazy("translate({}, {})", .{ 14, 26 }) });
        try doc.selfClose(.line, .{ .x1 = -10, .y1 = -22, .x2 = 0, .y2 = -12 });
        try doc.printIndent();
        doc.format = .compact;
        // Print the set name
        try doc.open(.text, .{});
        _ = try doc.writer.write(coord.set);
        try doc.close(); // text
        try doc.writer.writeByte('\n');
        doc.format = .pretty;
        // Close translated line and text.
        try doc.close(); // g
        try doc.close();
        if (prev) |p| {
            try doc.selfClose(.line, .{ .x1 = p.x, .y1 = p.y, .x2 = c.x, .y2 = c.y });
        }
        prev = c;
    }
    try doc.close();

    try stdout.flush(); // Don't forget to flush!
}
