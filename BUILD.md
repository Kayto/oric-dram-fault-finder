# ORIC DRAM Fault Finder - Build Instructions

## Quick Build

```bash
python build.py          # Build ROM
python build.py --check  # Verify tool paths
```

## Output Files

The build produces:
- `bin/dram_fault_finder_rom_auto.bin` - 16KB ROM image

## Configuration

Edit `build.config.json` to set paths to the cc65 tools:

```json
{
    "ca65": "ca65",
    "ld65": "ld65"
}
```

### Examples

**Windows (cc65 in PATH):**
```json
{
    "ca65": "ca65",
    "ld65": "ld65"
}
```

**Windows (custom path):**
```json
{
    "ca65": "C:\\cc65\\bin\\ca65.exe",
    "ld65": "C:\\cc65\\bin\\ld65.exe"
}
```

**macOS (Homebrew):**
```json
{
    "ca65": "/opt/homebrew/bin/ca65",
    "ld65": "/opt/homebrew/bin/ld65"
}
```

**Linux:**
```json
{
    "ca65": "/usr/bin/ca65",
    "ld65": "/usr/bin/ld65"
}
```

## Installing cc65

### Native Installation

| Platform | Installation |
|----------|--------------|
| **Windows** | Download from [GitHub releases](https://github.com/cc65/cc65/releases), extract, add `bin/` to PATH |
| **macOS** | `brew install cc65` |
| **Linux (Debian/Ubuntu)** | `apt install cc65` |

### Using Docker

If you prefer Docker, set `docker_image` in the config file:

```json
{
    "docker_image": "dawidbuchwald/cc65-tools-make"
}
```

When `docker_image` is set, the build script will automatically use Docker instead of native tools.

I use [dawidbuchwald/cc65-tools-make](https://github.com/dawidbuchwald/cc65-tools-make) by Dawid Buchwald - it includes all the cc65 tools needed.

## Manual Build

If you prefer to run commands manually:

```bash
# Assemble
ca65 src/dram_fault_finder_rom_auto.s -o bin/dram_fault_finder_rom_auto.o

# Link with ROM config
ld65 -C src/rom.cfg -o bin/dram_fault_finder_rom_auto.bin bin/dram_fault_finder_rom_auto.o

# Clean up
rm bin/dram_fault_finder_rom_auto.o
```

## ROM Configuration

The `src/rom.cfg` linker configuration places code at $C000 for the BASIC ROM slot:

```
MEMORY {
    ROM: start = $C000, size = $4000, fill = yes, fillval = $FF;
}
```

This creates a 16KB ROM image suitable for burning to a 27128 EPROM.

## Source Files

| File | Description |
|------|-------------|
| `src/dram_fault_finder_rom_auto.s` | Main auto-running ROM source |
| `src/rom.cfg` | Linker configuration for ROM |

## Pre-built Binary

A pre-built ROM image is included in the `bin/` folder:
- `dram_fault_finder_rom_auto.bin` - 16KB ROM image
