const std = @import("std");

fn Vec3(comptime T: type) type {
    return struct {
        const This = @This();

        x: T,
        y: T,
        z: T,

        pub fn length(this: This) T {
            return std.math.sqrt(this.length2());
        }

        pub fn length2(this: This) T {
            return this.x * this.x + this.y * this.y + this.z * this.z;
        }

        pub fn add(a: This, b: This) This {
            return This{
                .x = a.x + b.x,
                .y = a.y + b.y,
                .z = a.z + b.z,
            };
        }

        pub fn sub(a: This, b: This) This {
            return This{
                .x = a.x - b.x,
                .y = a.y - b.y,
                .z = a.z - b.z,
            };
        }

        pub fn negate(a: This) This {
            return This{
                .x = -a.x,
                .y = -a.y,
                .z = -a.z,
            };
        }

        pub fn mul(a: This, b: This) This {
            return This{
                .x = a.x * b.x,
                .y = a.y * b.y,
                .z = a.z * b.z,
            };
        }

        pub fn mulT(a: This, b: T) This {
            return This{
                .x = a.x * b,
                .y = a.y * b,
                .z = a.z * b,
            };
        }

        pub fn dot(a: This, b: This) T {
            return a.x * b.x + a.y * b.y + a.z * b.z;
        }

        pub fn normalize(this: *This) void {
            const nor2 = this.length2();
            if (nor2 > 0) {
                const inv = 1 / std.math.sqrt(nor2);
                this.x *= inv;
                this.y *= inv;
                this.z *= inv;
            }
        }
    };
}

const Vecf32 = Vec3(f32);

const Sphere = struct {
    const This = @This();

    center: Vecf32,
    radius: f32,
    surface_color: Vecf32,
    emission_color: ?Vecf32,
    transparency: f32,
    reflectivity: f32,

    fn radius2(this: This) f32 {
        return this.radius * this.radius;
    }
};

const MAX_RAY_DEPTH = 5;

fn mix(a: f32, b: f32, m: f32) f32 {
    return b * m + a * (1 - m);
}

fn intersect(origin: Vecf32, direction: Vecf32, sphere: Sphere) ?struct { t0: f32, t1: f32 } {
    const l = sphere.center.sub(origin);
    const tca = l.dot(direction);
    if (tca < 0) return null;
    const d2 = l.dot(l) - tca * tca;
    if (d2 > sphere.radius2()) return null;
    const thc = std.math.sqrt(sphere.radius2() - d2);
    const t0 = tca - thc;
    const t1 = tca + thc;
    return .{ .t0 = t0, .t1 = t1 };
}

fn trace(
    rayorig: Vecf32,
    raydir: Vecf32,
    spheres: []Sphere,
    depth: u32,
) Vecf32 {
    //if (raydir.length() != 1) std::cerr << "Error " << raydir << std::endl;
    var tnear = std.math.inf(f32);
    var sphere: ?Sphere = null;
    // find intersection of this ray with the sphere in the scene
    for (0..spheres.len) |i| {
        var t0 = std.math.inf(f32);
        var t1 = std.math.inf(f32);
        if (intersect(rayorig, raydir, spheres[i])) |intersection| {
            t0 = intersection.t0;
            t1 = intersection.t1;
            if (t0 < 0) {
                t0 = t1;
            }
            if (t0 < tnear) {
                tnear = t0;
                sphere = spheres[i];
            }
        }
    }
    // if there's no intersection return black or background color
    if (sphere) |safe_sphere| {
        var surfaceColor = Vecf32{ .x = 0, .y = 0, .z = 0 }; // color of the ray/surfaceof the object intersected by the ray
        const phit = rayorig.add(raydir.mulT(tnear)); // point of intersection
        var nhit = phit.sub(safe_sphere.center); // normal at the intersection point
        nhit.normalize(); // normalize normal direction

        // If the normal and the view direction are not opposite to each other
        // reverse the normal direction. That also means we are inside the sphere so set
        // the inside bool to true. Finally reverse the sign of IdotN which we want
        // positive.
        const bias = 1e-4; // add some bias to the point from which we will be tracing
        var inside = false;
        if (raydir.dot(nhit) > 0) {
            nhit = nhit.negate();
            inside = true;
        }
        if ((safe_sphere.transparency > 0 or safe_sphere.reflectivity > 0) and depth < MAX_RAY_DEPTH) {
            const facingratio = -raydir.dot(nhit);
            // change the mix value to tweak the effect
            const fresneleffect = mix(std.math.pow(f32, 1 - facingratio, 3), 1, 0.1);
            // compute reflection direction (not need to normalize because all vectors
            // are already normalized)
            var refldir = raydir.sub(nhit.mulT(2 * raydir.dot(nhit)));
            refldir.normalize();
            const reflection = trace(phit.add(nhit.mulT(bias)), refldir, spheres, depth + 1);
            var refraction = Vecf32{ .x = 0, .y = 0, .z = 0 };
            // if the sphere is also transparent compute refraction ray (transmission)
            if (safe_sphere.transparency > 0) {
                const ior: f32 = 1.1;
                const eta = if (inside) ior else 1.0 / ior; // are we inside or outside the surface?
                const cosi = -nhit.dot(raydir);
                const k = 1 - eta * eta * (1 - cosi * cosi);
                var refrdir = Vecf32.add(
                    raydir.mulT(eta),
                    nhit.mulT(eta * cosi - std.math.sqrt(k)),
                );
                refrdir.normalize();
                refraction = trace(phit.sub(nhit.mulT(bias)), refrdir, spheres, depth + 1);
            }
            // the result is a mix of reflection and refraction (if the sphere is transparent)
            surfaceColor = Vecf32.add(
                reflection.mulT(fresneleffect),
                refraction.mulT(1 - fresneleffect).mulT(safe_sphere.transparency),
            ).mul(safe_sphere.surface_color);
        } else {
            // it's a diffuse object, no need to raytrace any further
            for (0..spheres.len) |i| {
                const sphere_light = spheres[i];
                if (sphere_light.emission_color) |emission_color| {
                    if (emission_color.x > 0) {
                        // this is a light
                        var transmission = Vecf32{ .x = 1, .y = 1, .z = 1 };
                        var lightDirection = sphere_light.center.sub(phit);
                        lightDirection.normalize();
                        for (0..spheres.len) |j| {
                            if (i != j) {
                                if (intersect(phit.add(nhit.mulT(bias)), lightDirection, spheres[j])) |_| {
                                    transmission = Vecf32{ .x = 0, .y = 0, .z = 0 };
                                    break;
                                }
                            }
                        }
                        surfaceColor = surfaceColor.add(
                            safe_sphere.surface_color.mul(transmission).mulT(max(0.0, nhit.dot(lightDirection))).mul(emission_color),
                        );
                    }
                }
            }
        }
        if (safe_sphere.emission_color) |emission_color| {
            return surfaceColor.add(emission_color);
        } else {
            return surfaceColor.add(Vecf32{ .x = 0, .y = 0, .z = 0 });
        }
    } else return Vecf32{ .x = 2, .y = 2, .z = 2 };
}

fn max(a: f32, b: f32) f32 {
    if (a > b) {
        return a;
    } else {
        return b;
    }
}

fn min(a: f32, b: f32) f32 {
    if (a < b) {
        return a;
    } else {
        return b;
    }
}

fn clamp(a: f32, floor: f32, ceiling: f32) f32 {
    if (a < floor) {
        return floor;
    }
    if (a > ceiling) {
        return ceiling;
    }
    return a;
}

fn render(spheres: []Sphere) !void {
    const width = 640;
    const height = 480;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const image = try allocator.alloc(Vecf32, width * height);
    defer allocator.free(image);

    const fwidth: f32 = @floatFromInt(width);
    const fheight: f32 = @floatFromInt(height);
    const invWidth: f32 = 1.0 / fwidth;
    const invHeight: f32 = 1.0 / fheight;
    const fov: f32 = 30.0;
    const aspectratio = fwidth / fheight;
    const angle = std.math.tan(std.math.pi * 0.5 * fov / 180.0);

    // Trace rays
    for (image, 0..) |*pixel_ptr, i| {
        const x = i % width;
        const y = i / width;
        const fx: f32 = @floatFromInt(x);
        const fy: f32 = @floatFromInt(y);
        const xx = (2.0 * ((fx + 0.5) * invWidth) - 1.0) * angle * aspectratio;
        const yy = (1.0 - 2.0 * (((fy + 0.5) * invHeight))) * angle;
        var raydir = Vecf32{ .x = xx, .y = yy, .z = -1 };
        raydir.normalize();
        pixel_ptr.* = trace(Vecf32{ .x = 0.0, .y = 0.0, .z = 0.0 }, raydir, spheres, 0);
    }

    // Save result to a PPM image
    var file = try std.fs.cwd().createFile("./untitled.ppm", .{});
    defer file.close();

    try file.writer().print("P6\n{} {}\n255\n", .{ width, height });
    var buf = std.io.bufferedWriter(file.writer());
    var w = buf.writer();

    for (image, 0..) |p, i| {
        if (i * 3 % buf.buf.len == 0) {
            try buf.flush();
        }
        const r: u8 = @intFromFloat(clamp(p.x, 0.0, 1.0) * 255.0);
        const g: u8 = @intFromFloat(clamp(p.y, 0.0, 1.0) * 255.0);
        const b: u8 = @intFromFloat(clamp(p.z, 0.0, 1.0) * 255.0);
        try w.writeByte(r);
        try w.writeByte(g);
        try w.writeByte(b);
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var spheres = try allocator.alloc(Sphere, 6);
    defer allocator.free(spheres);

    //plane
    spheres[0] = .{ .center = Vecf32{ .x = 0.0, .y = -10004, .z = -20 }, .radius = 10000, .surface_color = Vecf32{ .x = 0.2, .y = 0.2, .z = 0.2 }, .reflectivity = 0, .transparency = 0, .emission_color = null };
    //spheres
    spheres[1] = .{ .center = Vecf32{ .x = 0.0, .y = 0, .z = -20 }, .radius = 4, .surface_color = Vecf32{ .x = 1.00, .y = 0.32, .z = 0.36 }, .reflectivity = 1, .transparency = 0.5, .emission_color = null };
    spheres[2] = .{ .center = Vecf32{ .x = 5.0, .y = -1, .z = -15 }, .radius = 2, .surface_color = Vecf32{ .x = 0.90, .y = 0.76, .z = 0.46 }, .reflectivity = 1, .transparency = 0.0, .emission_color = null };
    spheres[3] = .{ .center = Vecf32{ .x = 5.0, .y = 0, .z = -25 }, .radius = 3, .surface_color = Vecf32{ .x = 0.65, .y = 0.77, .z = 0.97 }, .reflectivity = 1, .transparency = 0.0, .emission_color = null };
    spheres[4] = .{ .center = Vecf32{ .x = -5.5, .y = 0, .z = -15 }, .radius = 3, .surface_color = Vecf32{ .x = 0.90, .y = 0.90, .z = 0.90 }, .reflectivity = 1, .transparency = 0.0, .emission_color = null };
    // light
    spheres[5] = .{ .center = Vecf32{ .x = 0.0, .y = 20, .z = -30 }, .radius = 3, .surface_color = Vecf32{ .x = 0.00, .y = 0.00, .z = 0.00 }, .reflectivity = 0, .transparency = 0.0, .emission_color = Vecf32{ .x = 3, .y = 3, .z = 3 } };
    try render(spheres);
}
