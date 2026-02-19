const std = @import("std");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");
const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const DeviceWrapper = vk.DeviceWrapper;
const Instance = vk.InstanceProxy;
const Device = vk.DeviceProxy;

const required_layer_names = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const required_extensions = [_][*:0]const u8{
    vk.extensions.ext_debug_utils.name,
    vk.extensions.khr_get_physical_device_properties_2.name,
    vk.extensions.khr_portability_enumeration.name,
};

const required_device_extensions = [_][*:0]const u8{
    vk.extensions.khr_copy_commands_2.name,
};

const required_device_features = vk.PhysicalDeviceFeatures{
    .sampler_anisotropy = .true,
};

const vkGetInstanceProcAddr = @extern(vk.PfnGetInstanceProcAddr, .{
    .name = "vkGetInstanceProcAddr",
});

pub const GraphicsContext = struct {
    pub const CommandBuffer = vk.CommandBufferProxy;

    allocator: Allocator,

    vkb: BaseWrapper,

    instance: Instance,
    debug_messenger: vk.DebugUtilsMessengerEXT,
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    features: vk.PhysicalDeviceFeatures,
    mem_props: vk.PhysicalDeviceMemoryProperties,

    dev: Device,
    graphics_queue: Queue,
    present_queue: Queue,

    pub fn init(allocator: Allocator, app_name: [*:0]const u8) !GraphicsContext {
        var self: GraphicsContext = undefined;
        self.allocator = allocator;
        self.vkb = BaseWrapper.load(vkGetInstanceProcAddr);

        const app_info = vk.ApplicationInfo{
            .p_application_name = app_name,
            .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
            .p_engine_name = app_name,
            .engine_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
            .api_version = @bitCast(vk.API_VERSION_1_0),
        };

        const instance = try self.vkb.createInstance(&.{
            .flags = .{ .enumerate_portability_bit_khr = true },
            .p_application_info = &app_info,
            .enabled_layer_count = required_layer_names.len,
            .pp_enabled_layer_names = @ptrCast(&required_layer_names),
            .enabled_extension_count = required_extensions.len,
            .pp_enabled_extension_names = @ptrCast(&required_extensions),
        }, null);

        const vki = try allocator.create(InstanceWrapper);
        errdefer allocator.destroy(vki);
        vki.* = InstanceWrapper.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr.?);
        self.instance = Instance.init(instance, vki);
        errdefer self.instance.destroyInstance(null);

        self.debug_messenger = try self.instance.createDebugUtilsMessengerEXT(&.{
            .message_severity = .{
                //.verbose_bit_ext = true,
                //.info_bit_ext = true,
                .warning_bit_ext = true,
                .error_bit_ext = true,
            },
            .message_type = .{
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
            },
            .pfn_user_callback = &debugUtilsMessengerCallback,
            .p_user_data = null,
        }, null);

        const candidate = try pickPhysicalDevice(self.instance, allocator);
        self.pdev = candidate.pdev;
        self.props = candidate.props;
        self.features = candidate.features;

        const dev = try initializeCandidate(self.instance, candidate);

        const vkd = try allocator.create(DeviceWrapper);
        errdefer allocator.destroy(vkd);
        vkd.* = DeviceWrapper.load(dev, self.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
        self.dev = Device.init(dev, vkd);
        errdefer self.dev.destroyDevice(null);

        self.graphics_queue = Queue.init(self.dev, candidate.queues.graphics_family);

        self.mem_props = self.instance.getPhysicalDeviceMemoryProperties(self.pdev);

        return self;
    }

    pub fn deinit(self: GraphicsContext) void {
        self.dev.destroyDevice(null);
        self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null);
        self.instance.destroyInstance(null);

        // Don't forget to free the tables to prevent a memory leak.
        self.allocator.destroy(self.dev.wrapper);
        self.allocator.destroy(self.instance.wrapper);
    }

    fn debugUtilsMessengerCallback(severity: vk.DebugUtilsMessageSeverityFlagsEXT, msg_type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, user_data: ?*anyopaque) callconv(.c) vk.Bool32 {
        _ = user_data;
        const severity_str = if (severity.verbose_bit_ext) "verbose" else if (severity.info_bit_ext) "info" else if (severity.warning_bit_ext) "warning" else if (severity.error_bit_ext) "error" else "unknown";

        const type_str = if (msg_type.general_bit_ext) "general" else if (msg_type.validation_bit_ext) "validation" else if (msg_type.performance_bit_ext) "performance" else if (msg_type.device_address_binding_bit_ext) "device addr" else "unknown";

        const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.p_message else "NO MESSAGE!";
        std.debug.print("[{s}][{s}]. Message:\n  {s}\n", .{ severity_str, type_str, message });

        return .false;
    }

    pub fn deviceName(self: *const GraphicsContext) []const u8 {
        return std.mem.sliceTo(&self.props.device_name, 0);
    }

    pub fn findMemoryTypeIndex(self: GraphicsContext, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
        for (self.mem_props.memory_types[0..self.mem_props.memory_type_count], 0..) |mem_type, i| {
            if (memory_type_bits & (@as(u32, 1) << @truncate(i)) != 0 and mem_type.property_flags.contains(flags)) {
                return @truncate(i);
            }
        }

        return error.NoSuitableMemoryType;
    }

    pub fn allocate(self: GraphicsContext, requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
        return try self.dev.allocateMemory(&.{
            .allocation_size = requirements.size,
            .memory_type_index = try self.findMemoryTypeIndex(requirements.memory_type_bits, flags),
        }, null);
    }
};

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(device: Device, family: u32) Queue {
        return .{
            .handle = device.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};

fn initializeCandidate(instance: Instance, candidate: DeviceCandidate) !vk.Device {
    const priority = [_]f32{1};
    const qci = [_]vk.DeviceQueueCreateInfo{
        .{
            .queue_family_index = candidate.queues.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
    };

    return try instance.createDevice(candidate.pdev, &.{
        .queue_create_info_count = qci.len,
        .p_queue_create_infos = &qci,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
        .p_enabled_features = &required_device_features,
    }, null);
}

const DeviceCandidate = struct {
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    features: vk.PhysicalDeviceFeatures,
    queues: QueueAllocation,
};

const QueueAllocation = struct {
    graphics_family: u32,
};

fn pickPhysicalDevice(
    instance: Instance,
    allocator: Allocator,
) !DeviceCandidate {
    const pdevs = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(pdevs);

    for (pdevs) |pdev| {
        if (try checkSuitable(instance, pdev, allocator)) |candidate| {
            return candidate;
        }
    }

    return error.NoSuitableDevice;
}

fn checkSuitable(
    instance: Instance,
    pdev: vk.PhysicalDevice,
    allocator: Allocator,
) !?DeviceCandidate {
    if (!try checkExtensionSupport(instance, pdev, allocator)) {
        return null;
    }

    const features = instance.getPhysicalDeviceFeatures(pdev);
    if (!try checkFeatureSupport(features)) {
        return null;
    }

    if (try allocateQueues(instance, pdev, allocator)) |allocation| {
        const props = instance.getPhysicalDeviceProperties(pdev);
        return DeviceCandidate{
            .pdev = pdev,
            .props = props,
            .features = features,
            .queues = allocation,
        };
    }

    return null;
}

fn allocateQueues(instance: Instance, pdev: vk.PhysicalDevice, allocator: Allocator) !?QueueAllocation {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);

    var graphics_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }
    }

    if (graphics_family != null) {
        return QueueAllocation{
            .graphics_family = graphics_family.?,
        };
    }

    return null;
}

fn checkExtensionSupport(
    instance: Instance,
    pdev: vk.PhysicalDevice,
    allocator: Allocator,
) !bool {
    const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
    defer allocator.free(propsv);

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}

fn checkFeatureSupport(features: vk.PhysicalDeviceFeatures) !bool {
    inline for (@typeInfo(vk.PhysicalDeviceFeatures).@"struct".fields) |feature| {
        if (@field(required_device_features, feature.name) == .true and @field(features, feature.name) == .false) {
            return false;
        }
    }

    return true;
}
