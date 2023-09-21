const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const Linkage = std.Build.Step.Compile.Linkage;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(Linkage, "linkage", "The linking mode for libraries") orelse .static;
    const lib_name = "icutu";
    const can_generate_objects = b.option(bool, "canGenerateObjects", "Can generate objects") orelse false;
    const has_win32_api = builtin.os.tag == .windows;
    const platform_linux_based = builtin.os.tag == .linux;
    const u_elf = builtin.os.tag == .linux;

    const lib = std.Build.Step.Compile.create(b, .{
        .name = lib_name,
        .kind = .lib,
        .linkage = linkage,
        .target = target,
        .optimize = optimize,
    });

    const common = b.dependency("common", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });
    const icuuc = common.artifact("icuuc");

    const i18n = b.dependency("internationalization", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });
    const icui18n = i18n.artifact("icui18n");

    if (linkage == .static) {
        lib.defineCMacro("U_STATIC_IMPLEMENTATION", null);
    }

    // HACK This is an ugly hack to deal with private headers.
    const icuuc_root = common.builder.pathFromRoot("cpp");
    const icuuc_arg = std.mem.concat(b.allocator, u8, &.{ "-I", icuuc_root }) catch @panic("OOM");
    const icui18n_root = i18n.builder.pathFromRoot("cpp");
    const icui18n_arg = std.mem.concat(b.allocator, u8, &.{ "-I", icui18n_root }) catch @panic("OOM");

    // Configuration
    if (can_generate_objects) lib.defineCMacro("CAN_GENERATE_OBJECTS", null);
    if (has_win32_api) lib.defineCMacro("U_PLATFORM_HAS_WIN32_API", null);
    if (platform_linux_based) lib.defineCMacro("U_PLATFORM_IS_LINUX_BASED", null);
    if (u_elf) lib.defineCMacro("U_ELF", null);

    lib.linkLibCpp();
    lib.defineCMacro("U_TOOLUTIL_IMPLEMENTATION", null);
    lib.linkLibrary(icuuc);
    lib.installLibraryHeaders(icuuc);
    lib.linkLibrary(icui18n);
    lib.installLibraryHeaders(icui18n);
    lib.addIncludePath(.{ .path = "cpp" });

    addSourceFiles(b, lib, &.{ "-fno-exceptions", icuuc_arg, icui18n_arg }) catch @panic("OOM");
    //lib.installHeadersDirectory(b.pathJoin(&.{ "cpp", "unicode" }), "unicode");
    b.installArtifact(lib);
}

fn addSourceFiles(b: *std.Build, artifact: *std.Build.Step.Compile, flags: []const []const u8) !void {
    var files = std.ArrayList([]const u8).init(b.allocator);
    var sources_txt = try std.fs.cwd().openFile(b.pathFromRoot("cpp/sources.txt"), .{});
    var reader = sources_txt.reader();
    var buffer: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buffer, '\n')) |l| {
        const line = std.mem.trim(u8, l, " \t\r\n");
        try files.append(b.pathJoin(&.{ "cpp", line }));
    }

    artifact.addCSourceFiles(files.items, flags);
}
