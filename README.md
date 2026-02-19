# How to compile

## Install dependencies

- Graphics card + drivers (you probably already have these)
- A terminal (you probably already have this)
- Vulkan SDK
- Zig 0.14.0

### Arch Linux

```
pacman -S vulkan-devel
yay -S zig-bin
```

### Ubuntu Linux

```
apt install vulkan-tools vulkan-validationlayers spirv-tools glslc
```

Then download Zig from https://ziglang.org/download/, or

```
snap install zig --classic --beta
```

### Fedora Linux

```
sudo dnf install vulkan-devel zig libshaderc-devel vulkan-tools
```

### Mac

```
# Download the Vulkan SDK from https://vulkan.lunarg.com/sdk/home
# and then
brew install zig
```

### Windows

```
# Download the Vulkan SDK from https://vulkan.lunarg.com/sdk/home
# and then
winget install zig.zig
```

## Get the code and run it

```
git clone https://codeberg.org/zacoons/minecraftty
cd minecraftty
zig build run
```

If you run into any problems, feel free to open an issue or submit a PR.

# How to "play"

`wasd` to move around.

`hjkl` or arrow keys to look around.

`x` or `esc` to exit the game.

That's it.

# Thanks to

Big thanks to https://vulkan-tutorial.com without which this project wouldn't have been possible. Also thanks to:

- Snektron and contributors for the excellent Zig-Vulkan bindings (https://github.com/Snektron/vulkan-zig)
- mlarouche and co. for the image IO library (https://github.com/zigimg/zigimg)
- kooparse and co. for the linear algebra library (https://github.com/kooparse/zalgebra)
- mgord9518 and co. for perlin-zig (https://github.com/mgord9518/perlin-zig/blob/main/lib/perlin.zig)
