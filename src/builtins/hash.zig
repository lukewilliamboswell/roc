//! Wyhash implementation
//!
//! SPDX-License-Identifier: MIT
//! Copyright (c) 2015-2021 Zig Contributors
//! This file is part of [zig](https://ziglang.org/), which is MIT licensed.
//! The MIT license requires this copyright notice to be included in all copies
//! and substantial portions of the software.
const std = @import("std");
const str = @import("str.zig");
const mem = std.mem;

/// TODO: Document wyhash.
pub fn wyhash(seed: u64, bytes: ?[*]const u8, length: usize) callconv(.C) u64 {
    if (bytes) |nonnull| {
        const slice = nonnull[0..length];
        return wyhash_hash(seed, slice);
    } else {
        return 42;
    }
}

/// TODO: Document wyhash_rocstr.
pub fn wyhash_rocstr(seed: u64, input: str.RocStr) callconv(.C) u64 {
    return wyhash_hash(seed, input.asSlice());
}

const primes = [_]u64{
    0xa0761d6478bd642f,
    0xe7037ed1a0b428db,
    0x8ebc6af09c88c6e3,
    0x589965cc75374cc3,
    0x1d8e4e27c47d124f,
};

fn read_bytes(comptime bytes: u8, data: []const u8) u64 {
    const T = std.meta.Int(.unsigned, 8 * bytes);
    return mem.readInt(T, data[0..bytes], .little);
}

fn read_8bytes_swapped(data: []const u8) u64 {
    return (read_bytes(4, data) << 32 | read_bytes(4, data[4..]));
}

fn mum(a: u64, b: u64) u64 {
    var r = std.math.mulWide(u64, a, b);
    r = (r >> 64) ^ r;
    return @as(u64, @truncate(r));
}

fn mix0(a: u64, b: u64, seed: u64) u64 {
    return mum(a ^ seed ^ primes[0], b ^ seed ^ primes[1]);
}

fn mix1(a: u64, b: u64, seed: u64) u64 {
    return mum(a ^ seed ^ primes[2], b ^ seed ^ primes[3]);
}

// Wyhash version which does not store internal state for handling partial buffers.
// This is needed so that we can maximize the speed for the short key case, which will
// use the non-iterative api which the public Wyhash exposes.
const WyhashStateless = struct {
    seed: u64,
    msg_len: usize,

    pub fn init(seed: u64) WyhashStateless {
        return WyhashStateless{
            .seed = seed,
            .msg_len = 0,
        };
    }

    fn round(self: *WyhashStateless, b: []const u8) void {
        std.debug.assert(b.len == 32);

        self.seed = mix0(
            read_bytes(8, b[0..]),
            read_bytes(8, b[8..]),
            self.seed,
        ) ^ mix1(
            read_bytes(8, b[16..]),
            read_bytes(8, b[24..]),
            self.seed,
        );
    }

    pub fn update(self: *WyhashStateless, b: []const u8) void {
        std.debug.assert(b.len % 32 == 0);

        var off: usize = 0;
        while (off < b.len) : (off += 32) {
            @call(.always_inline, WyhashStateless.round, .{ self, b[off .. off + 32] });
        }

        self.msg_len += b.len;
    }

    pub fn final(self: *WyhashStateless, b: []const u8) u64 {
        std.debug.assert(b.len < 32);

        const seed = self.seed;
        const rem_len = @as(u5, @intCast(b.len));
        const rem_key = b[0..rem_len];

        self.seed = switch (rem_len) {
            0 => seed,
            1 => mix0(read_bytes(1, rem_key), primes[4], seed),
            2 => mix0(read_bytes(2, rem_key), primes[4], seed),
            3 => mix0((read_bytes(2, rem_key) << 8) | read_bytes(1, rem_key[2..]), primes[4], seed),
            4 => mix0(read_bytes(4, rem_key), primes[4], seed),
            5 => mix0((read_bytes(4, rem_key) << 8) | read_bytes(1, rem_key[4..]), primes[4], seed),
            6 => mix0((read_bytes(4, rem_key) << 16) | read_bytes(2, rem_key[4..]), primes[4], seed),
            7 => mix0((read_bytes(4, rem_key) << 24) | (read_bytes(2, rem_key[4..]) << 8) | read_bytes(1, rem_key[6..]), primes[4], seed),
            8 => mix0(read_8bytes_swapped(rem_key), primes[4], seed),
            9 => mix0(read_8bytes_swapped(rem_key), read_bytes(1, rem_key[8..]), seed),
            10 => mix0(read_8bytes_swapped(rem_key), read_bytes(2, rem_key[8..]), seed),
            11 => mix0(read_8bytes_swapped(rem_key), (read_bytes(2, rem_key[8..]) << 8) | read_bytes(1, rem_key[10..]), seed),
            12 => mix0(read_8bytes_swapped(rem_key), read_bytes(4, rem_key[8..]), seed),
            13 => mix0(read_8bytes_swapped(rem_key), (read_bytes(4, rem_key[8..]) << 8) | read_bytes(1, rem_key[12..]), seed),
            14 => mix0(read_8bytes_swapped(rem_key), (read_bytes(4, rem_key[8..]) << 16) | read_bytes(2, rem_key[12..]), seed),
            15 => mix0(read_8bytes_swapped(rem_key), (read_bytes(4, rem_key[8..]) << 24) | (read_bytes(2, rem_key[12..]) << 8) | read_bytes(1, rem_key[14..]), seed),
            16 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed),
            17 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1(read_bytes(1, rem_key[16..]), primes[4], seed),
            18 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1(read_bytes(2, rem_key[16..]), primes[4], seed),
            19 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1((read_bytes(2, rem_key[16..]) << 8) | read_bytes(1, rem_key[18..]), primes[4], seed),
            20 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1(read_bytes(4, rem_key[16..]), primes[4], seed),
            21 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1((read_bytes(4, rem_key[16..]) << 8) | read_bytes(1, rem_key[20..]), primes[4], seed),
            22 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1((read_bytes(4, rem_key[16..]) << 16) | read_bytes(2, rem_key[20..]), primes[4], seed),
            23 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1((read_bytes(4, rem_key[16..]) << 24) | (read_bytes(2, rem_key[20..]) << 8) | read_bytes(1, rem_key[22..]), primes[4], seed),
            24 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1(read_8bytes_swapped(rem_key[16..]), primes[4], seed),
            25 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1(read_8bytes_swapped(rem_key[16..]), read_bytes(1, rem_key[24..]), seed),
            26 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1(read_8bytes_swapped(rem_key[16..]), read_bytes(2, rem_key[24..]), seed),
            27 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1(read_8bytes_swapped(rem_key[16..]), (read_bytes(2, rem_key[24..]) << 8) | read_bytes(1, rem_key[26..]), seed),
            28 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1(read_8bytes_swapped(rem_key[16..]), read_bytes(4, rem_key[24..]), seed),
            29 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1(read_8bytes_swapped(rem_key[16..]), (read_bytes(4, rem_key[24..]) << 8) | read_bytes(1, rem_key[28..]), seed),
            30 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1(read_8bytes_swapped(rem_key[16..]), (read_bytes(4, rem_key[24..]) << 16) | read_bytes(2, rem_key[28..]), seed),
            31 => mix0(read_8bytes_swapped(rem_key), read_8bytes_swapped(rem_key[8..]), seed) ^ mix1(read_8bytes_swapped(rem_key[16..]), (read_bytes(4, rem_key[24..]) << 24) | (read_bytes(2, rem_key[28..]) << 8) | read_bytes(1, rem_key[30..]), seed),
        };

        self.msg_len += b.len;
        return mum(self.seed ^ self.msg_len, primes[4]);
    }

    pub fn hash(seed: u64, input: []const u8) u64 {
        const aligned_len = input.len - (input.len % 32);

        var c = WyhashStateless.init(seed);
        @call(.always_inline, WyhashStateless.update, .{ &c, input[0..aligned_len] });
        return @call(.always_inline, WyhashStateless.final, .{ &c, input[aligned_len..] });
    }
};

/// Fast non-cryptographic 64bit hash function.
/// See https://github.com/wangyi-fudan/wyhash
pub const Wyhash = struct {
    state: WyhashStateless,

    buf: [32]u8,
    buf_len: usize,

    pub fn init(seed: u64) Wyhash {
        return Wyhash{
            .state = WyhashStateless.init(seed),
            .buf = undefined,
            .buf_len = 0,
        };
    }

    pub fn update(self: *Wyhash, b: []const u8) void {
        var off: usize = 0;

        if (self.buf_len != 0 and self.buf_len + b.len >= 32) {
            off += 32 - self.buf_len;
            @memcpy(self.buf[self.buf_len..][0..off], b[0..off]);
            self.state.update(self.buf[0..]);
            self.buf_len = 0;
        }

        const remain_len = b.len - off;
        const aligned_len = remain_len - (remain_len % 32);
        self.state.update(b[off .. off + aligned_len]);

        const remaining = b[off + aligned_len ..];
        @memcpy(self.buf[self.buf_len..][0..remaining.len], remaining);
        self.buf_len += @as(u8, @intCast(b[off + aligned_len ..].len));
    }

    pub fn final(self: *Wyhash) u64 {
        // const seed = self.state.seed;
        // const rem_len = @intCast(u5, self.buf_len);
        const rem_key = self.buf[0..self.buf_len];

        return self.state.final(rem_key);
    }

    pub fn hash(seed: u64, input: []const u8) u64 {
        return WyhashStateless.hash(seed, input);
    }
};

fn wyhash_hash(seed: u64, input: []const u8) u64 {
    return Wyhash.hash(seed, input);
}
