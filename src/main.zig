const std = @import("std");
const dots = @import("dots");

const pixel = dots.Scale{ .ratio = .{ .x = 800, .y = -426 } };

fn FmtAlt(comptime f: anytype) type {
    return std.fmt.Alt(std.meta.fields(std.meta.ArgsTuple(@TypeOf(f)))[0].type, f);
}

fn fmtAlt(comptime f: anytype, d: anytype) FmtAlt(f) {
    return .{ .data = d };
}

fn printLine(cs: [2]dots.Coordinate, writer: *std.io.Writer) std.io.Writer.Error!void {
    try writer.print("<line x1=\"{}\" y1=\"{}\" x2=\"{}\" y2=\"{}\" stroke=\"black\"/>", .{ cs[0].x, cs[0].y, cs[1].x, cs[1].y });
}

fn printPerformer(p: dots.Performer, writer: *std.io.Writer) std.io.Writer.Error!void {
    try writer.print("<text>{s}{}</text>\n", .{ p.section.symbol, p.number });
}

fn printDot(d: dots.Dot, writer: *std.io.Writer) std.io.Writer.Error!void {
    try writer.print("<g>\n<circle r=\"2\" fill=\"black\"/>\n", .{});
    try writer.print(
        "<g transform=\"translate(14, 26)\">\n<line stroke=\"black\" x1=\"-10\" y1=\"-22\" x2=\"0\" y2=\"-12\"/>{f}\n",
        .{fmtAlt(printPerformer, d.performer)},
    );
    try writer.print("</g>\n</g>\n", .{});
}

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
        const line = dots.Scale.foot.translateXFrom(@as(f64, @floatFromInt((50 - self.yard_line) * 3)));
        const dx = dots.Scale.step.translateXFrom(self.steps);
        const x_abs = switch (self.direction) {
            .on => line,
            // Numbers get smaller, closer to the origin.
            .inside => line - dx,
            // Numbers get bigger, farther from the origin.
            .outside => line + dx,
        };
        return switch (self.side) {
            .side1 => -x_abs,
            .side2 => x_abs,
        };
    }

    pub const Side = enum { side1, side2 };
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

pub fn dot(performer: dots.Performer, ltr: LeftToRight, ftb: FrontToBack) dots.Dot {
    return .{ .performer = performer, .coordinate = .{ .x = ltr.delta(), .y = ftb.delta() } };
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
    try parseSide(s, &result);
    try parseLtrDirection(s, &result);
    try parseYardLine(s, &result);
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

test {
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
        try std.testing.expectEqualStrings(exp.set, act.set);
        try std.testing.expectEqualDeep(exp.letter, act.letter);
        try std.testing.expectEqual(exp.counts, act.counts);
        try std.testing.expectEqual(exp.ltr.side, act.ltr.side);
        try std.testing.expectEqual(exp.ltr.steps, act.ltr.steps);
        try std.testing.expectEqual(exp.ltr.direction, act.ltr.direction);
        try std.testing.expectEqual(exp.ltr.yard_line, act.ltr.yard_line);
        try std.testing.expectEqual(exp.ftb.steps, act.ftb.steps);
        try std.testing.expectEqual(exp.ftb.direction, act.ftb.direction);
        try std.testing.expectEqual(exp.ftb.marking, act.ftb.marking);
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
    const coords = &[_]dots.Dot{
        dot(c1, .ltr(0.0, .inside, .side1, 40), .ftb(0.0, .in_front_of, .front_hash)),
        dot(c1, .ltr(0.0, .inside, .side1, 40), .ftb(0.0, .in_front_of, .front_hash)),
        dot(c1, .ltr(3.0, .outside, .side1, 50), .ftb(9.0, .in_front_of, .front_hash)),
        dot(c1, .ltr(0.0, .inside, .side1, 40), .ftb(1.0, .behind, .front_side_line)),
        dot(c1, .ltr(0.0, .inside, .side1, 40), .ftb(1.0, .behind, .front_side_line)),
        dot(c1, .ltr(0.0, .inside, .side1, 40), .ftb(1.0, .behind, .front_side_line)),
        dot(c1, .ltr(2.25, .inside, .side1, 30), .ftb(3.75, .behind, .front_side_line)),
        dot(c1, .ltr(1.75, .inside, .side1, 35), .ftb(0.75, .in_front_of, .front_side_line)),
        dot(c1, .ltr(2.75, .inside, .side1, 40), .ftb(0.25, .behind, .front_side_line)),
        dot(c1, .ltr(0.0, .inside, .side1, 45), .ftb(0.0, .in_front_of, .front_side_line)),
        dot(c1, .ltr(0.0, .inside, .side1, 50), .ftb(4.0, .behind, .front_side_line)),
        dot(c1, .ltr(1.5, .inside, .side2, 45), .ftb(6.25, .behind, .front_side_line)),
        dot(c1, .ltr(1.5, .inside, .side2, 45), .ftb(6.25, .behind, .front_side_line)),
        dot(c1, .ltr(1.5, .inside, .side2, 45), .ftb(6.25, .behind, .front_side_line)),
        dot(c1, .ltr(0.0, .inside, .side2, 45), .ftb(10.0, .behind, .front_side_line)),
        dot(c1, .ltr(0.0, .inside, .side1, 45), .ftb(4.0, .behind, .front_side_line)),
        dot(c1, .ltr(2.0, .outside, .side1, 35), .ftb(8.0, .behind, .front_side_line)),
        dot(c1, .ltr(2.0, .outside, .side1, 35), .ftb(8.0, .behind, .front_side_line)),
        dot(c1, .ltr(2.0, .outside, .side1, 35), .ftb(8.0, .behind, .front_side_line)),
        dot(c1, .ltr(0.0, .inside, .side1, 45), .ftb(0.0, .in_front_of, .front_side_line)),
        dot(c1, .ltr(0.0, .inside, .side1, 50), .ftb(1.0, .behind, .front_side_line)),
        dot(c1, .ltr(0.0, .inside, .side1, 50), .ftb(1.0, .behind, .front_side_line)),
        dot(c1, .ltr(0.0, .inside, .side1, 50), .ftb(1.0, .behind, .front_side_line)),
        dot(c1, .ltr(0.0, .inside, .side1, 50), .ftb(1.0, .behind, .front_side_line)),
        dot(c1, .ltr(1.75, .outside, .side1, 50), .ftb(0.25, .in_front_of, .front_side_line)),
        dot(c1, .ltr(1.25, .inside, .side2, 45), .ftb(13.25, .in_front_of, .front_hash)),
        dot(c1, .ltr(3.5, .outside, .side2, 40), .ftb(4.25, .behind, .front_hash)),
        dot(c1, .ltr(3.5, .outside, .side2, 40), .ftb(4.25, .behind, .front_hash)),
        dot(c1, .ltr(4.0, .outside, .side2, 35), .ftb(4.0, .in_front_of, .front_hash)),
        dot(c1, .ltr(4.0, .outside, .side2, 35), .ftb(4.0, .in_front_of, .front_hash)),
        dot(c1, .ltr(2.0, .inside, .side2, 30), .ftb(2.0, .in_front_of, .front_hash)),
        dot(c1, .ltr(2.0, .inside, .side2, 30), .ftb(2.0, .in_front_of, .front_hash)),
        dot(c1, .ltr(4.0, .outside, .side2, 35), .ftb(0.0, .in_front_of, .front_hash)),
        dot(c1, .ltr(2.0, .inside, .side2, 30), .ftb(4.0, .behind, .front_hash)),
        dot(c1, .ltr(3.0, .outside, .side2, 30), .ftb(2.0, .in_front_of, .front_hash)),
        dot(c1, .ltr(0.0, .inside, .side2, 25), .ftb(8.0, .in_front_of, .front_hash)),
        dot(c1, .ltr(3.75, .inside, .side2, 20), .ftb(13.25, .behind, .front_side_line)),
        dot(c1, .ltr(1.0, .outside, .side2, 20), .ftb(6.5, .behind, .front_side_line)),
        dot(c1, .ltr(1.0, .outside, .side2, 20), .ftb(6.5, .behind, .front_side_line)),
        dot(c1, .ltr(3.25, .outside, .side2, 20), .ftb(6.5, .behind, .front_side_line)),
        dot(c1, .ltr(3.25, .outside, .side2, 20), .ftb(6.5, .behind, .front_side_line)),
        dot(c1, .ltr(4.0, .outside, .side2, 20), .ftb(7.0, .in_front_of, .front_hash)),
        dot(c1, .ltr(4.0, .outside, .side2, 20), .ftb(7.0, .in_front_of, .front_hash)),
        dot(c1, .ltr(1.0, .inside, .side2, 20), .ftb(4.0, .behind, .front_side_line)),
        dot(c1, .ltr(1.0, .inside, .side2, 20), .ftb(4.0, .behind, .front_side_line)),
        dot(c1, .ltr(3.0, .inside, .side2, 25), .ftb(1.0, .behind, .front_side_line)),
        dot(c1, .ltr(3.0, .inside, .side2, 25), .ftb(1.0, .behind, .front_side_line)),
        dot(c1, .ltr(3.0, .inside, .side2, 25), .ftb(1.0, .behind, .front_side_line)),
        dot(c1, .ltr(3.0, .inside, .side2, 25), .ftb(1.0, .behind, .front_side_line)),
        dot(c1, .ltr(3.0, .inside, .side2, 25), .ftb(1.0, .behind, .front_side_line)),
        dot(c1, .ltr(0.0, .inside, .side2, 30), .ftb(2.0, .in_front_of, .front_side_line)),
        dot(c1, .ltr(0.0, .inside, .side2, 30), .ftb(2.0, .in_front_of, .front_side_line)),
    };
    try stdout.print(
        "<svg viewBox=\"{} {} {} {}\" xmlns=\"http://www.w3.org/2000/svg\">\n",
        .{ -1000, -500, 2000, 1000 },
        // .{ -pixel.ratio.x, pixel.ratio.y, pixel.ratio.x * 2, -pixel.ratio.y * 2 },
    );
    try stdout.print("<style> svg {{ background-color: gray; }}</style>\n", .{});
    const back = pixel.translateYTo(1.0);
    // const back_hash = pixel.translateYTo(1.0 - FrontToBack.hash_dy);
    const front = pixel.translateYTo(-1.0);
    // const front_hash = pixel.translateYTo(-1.0 + FrontToBack.hash_dy);
    const left = pixel.translateXTo(-1.0);
    const right = pixel.translateXTo(1.0);
    // Back side line
    try stdout.print("{f}\n", .{fmtAlt(printLine, .{ dots.Coordinate{ .x = left, .y = back }, dots.Coordinate{ .x = right, .y = back } })});
    // try stdout.print("{f}\n", .{fmtAlt(printLine, .{ dots.Coordinate{ .x = left, .y = back_hash }, dots.Coordinate{ .x = right, .y = back_hash } })});
    // Front side line
    try stdout.print("{f}\n", .{fmtAlt(printLine, .{ dots.Coordinate{ .x = left, .y = front }, dots.Coordinate{ .x = right, .y = front } })});
    // try stdout.print("{f}\n", .{fmtAlt(printLine, .{ dots.Coordinate{ .x = left, .y = front_hash }, dots.Coordinate{ .x = right, .y = front_hash } })});
    // Side 1 goal line
    try stdout.print("{f}\n", .{fmtAlt(printLine, .{ dots.Coordinate{ .x = left, .y = back }, dots.Coordinate{ .x = left, .y = front } })});
    // Side 2 goal line
    try stdout.print("{f}\n", .{fmtAlt(printLine, .{ dots.Coordinate{ .x = right, .y = back }, dots.Coordinate{ .x = right, .y = front } })});
    // 50 yard line
    try stdout.print("{f}\n", .{fmtAlt(printLine, .{ dots.Coordinate{ .x = 0, .y = back }, dots.Coordinate{ .x = 0, .y = front } })});
    for (1..10) |i| {
        try stdout.print("<g transform=\"translate({}, 0)\">\n{f}</g>", .{
            dots.Scale.translateX(.foot, pixel, @as(f64, @floatFromInt(i * 15))),
            fmtAlt(printLine, .{ dots.Coordinate{ .x = 0, .y = back }, dots.Coordinate{ .x = 0, .y = front } }),
        });
        try stdout.print("<g transform=\"translate({}, 0)\">\n{f}</g>", .{
            dots.Scale.translateX(.foot, pixel, -@as(f64, @floatFromInt(i * 15))),
            fmtAlt(printLine, .{ dots.Coordinate{ .x = 0, .y = back }, dots.Coordinate{ .x = 0, .y = front } }),
        });
    }
    std.debug.print("    dx     dy   dist\n", .{});
    for (coords[0 .. coords.len - 1], coords[1..]) |d0, d1| {
        const dx = dots.Scale.step.translateXTo(d1.coordinate.x - d0.coordinate.x);
        const dy = dots.Scale.step.translateYTo(d1.coordinate.y - d0.coordinate.y);
        std.debug.print("{:6.2} {:6.2} {:6.2}\n", .{ dx, dy, std.math.sqrt(dx * dx + dy * dy) });
        const coord0 = pixel.translateTo(d0.coordinate);
        const coord1 = pixel.translateTo(d1.coordinate);
        try stdout.print("<line x1=\"{}\" y1=\"{}\" x2=\"{}\" y2=\"{}\" stroke=\"black\"/>\n", .{ coord0.x, coord0.y, coord1.x, coord1.y });
    }
    // var show = dots.Show{
    //     .coordinates = coords,
    // };

    for (coords) |d| {
        const c = pixel.translateTo(d.coordinate);
        try stdout.print("<g transform=\"translate({}, {})\">\n{f}</g>\n", .{ c.x, c.y, fmtAlt(printDot, d) });
    }
    try stdout.print("</svg>\n", .{});

    try stdout.flush(); // Don't forget to flush!
}
