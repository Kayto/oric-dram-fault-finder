#!/usr/bin/env python3
"""
build.py - ORIC DRAM Fault Finder ROM Builder

Assembles the ROM source using ca65/ld65 and creates the ROM image.

Author: Kayto
Version: 2.0
Date: January 2026
License: MIT License

Configuration:
    Edit build.config.json to set paths to ca65 and ld65 executables.
    
    If you don't have cc65 installed locally, you can use Docker:
    - Install Docker: https://www.docker.com/
    - Set docker_image in config
    - Recommended image: dawidbuchwald/cc65-tools-make

Usage:
    python build.py [options]
    
Options:
    --check         Check if tools are available

Examples:
    python build.py                    # Build ROM
    python build.py --check            # Verify tool configuration
"""

import argparse
import json
import subprocess
import sys
import shutil
from pathlib import Path


# Default configuration
DEFAULT_CONFIG = {
    "ca65": "ca65",
    "ld65": "ld65",
    "docker_image": ""
}

CONFIG_FILE = "build.config.json"

# Source and output files
SOURCE_FILE = "src/dram_fault_finder_rom_auto.s"
ROM_CONFIG = "src/rom.cfg"
OUTPUT_ROM = "bin/dram_fault_finder_rom_auto.bin"


def load_config(script_dir: Path) -> dict:
    """Load configuration from JSON file."""
    config_path = script_dir / CONFIG_FILE
    
    if config_path.exists():
        try:
            with open(config_path, 'r') as f:
                config = json.load(f)
            return {
                "ca65": config.get("ca65", DEFAULT_CONFIG["ca65"]),
                "ld65": config.get("ld65", DEFAULT_CONFIG["ld65"]),
                "docker_image": config.get("docker_image", "")
            }
        except (json.JSONDecodeError, KeyError) as e:
            print(f"Warning: Config file error: {e}")
            print("Using defaults...")
    
    return DEFAULT_CONFIG.copy()


def run_command(cmd: list, capture: bool = True, timeout: int = 120) -> tuple:
    """Run command and return (success, stdout, stderr)."""
    try:
        result = subprocess.run(
            cmd, 
            capture_output=capture, 
            text=True,
            timeout=timeout,
            shell=False
        )
        return result.returncode == 0, result.stdout, result.stderr
    except FileNotFoundError:
        return False, "", "Command not found"
    except subprocess.TimeoutExpired:
        return False, "", "Command timed out"
    except Exception as e:
        return False, "", str(e)


def check_tool(cmd: str) -> tuple:
    """Check if a tool is available and get version."""
    if cmd.startswith("docker "):
        success, stdout, stderr = run_command(["docker", "--version"])
        if success:
            return True, f"Docker: {stdout.strip()}"
        return False, "Docker not available"
    
    success, stdout, stderr = run_command([cmd, "--version"])
    output = stdout if stdout else stderr
    if output and ("ca65" in output.lower() or "ld65" in output.lower() or "cc65" in output.lower()):
        version = output.split('\n')[0]
        return True, version
    if success:
        version = output.split('\n')[0] if output else "unknown"
        return True, version
    return False, "Not found"


def find_in_path(name: str) -> str:
    """Try to find executable in PATH or common locations."""
    result = shutil.which(name)
    if result:
        return result
    
    common_paths = [
        Path(f"C:/cc65/bin/{name}.exe"),
        Path(f"C:/Program Files/cc65/bin/{name}.exe"),
        Path(f"C:/Program Files (x86)/cc65/bin/{name}.exe"),
        Path(f"C:/MyPrograms/cc65/bin/{name}.exe"),
        Path(f"/usr/local/bin/{name}"),
        Path(f"/opt/homebrew/bin/{name}"),
        Path(f"/usr/bin/{name}"),
    ]
    
    for p in common_paths:
        if p.exists():
            return str(p)
    
    return None


def build_docker(script_dir: Path, docker_image: str) -> bool:
    """Build using Docker cc65 image."""
    print(f"  Using Docker: {docker_image}")
    
    source = script_dir / SOURCE_FILE
    rom_cfg = script_dir / ROM_CONFIG
    obj_name = source.stem + '.o'
    out_name = Path(OUTPUT_ROM).name
    
    cmd = [
        'docker', 'run', '--rm',
        '-v', f'{script_dir}:/src',
        '--entrypoint', '/bin/sh',
        docker_image,
        '-c', f'cd /src && ca65 {SOURCE_FILE} -o bin/{obj_name} && ld65 -C {ROM_CONFIG} -o {OUTPUT_ROM} bin/{obj_name} && rm -f bin/{obj_name}'
    ]
    
    success, stdout, err = run_command(cmd, timeout=180)
    
    if success and (script_dir / OUTPUT_ROM).exists():
        return True
    
    print(f"  Docker build failed: {err}")
    return False


def build_native(script_dir: Path, config: dict) -> bool:
    """Build using native ca65/ld65."""
    ca65 = config.get('ca65', 'ca65')
    ld65 = config.get('ld65', 'ld65')
    
    source = script_dir / SOURCE_FILE
    rom_cfg = script_dir / ROM_CONFIG
    obj_file = script_dir / 'bin' / (source.stem + '.o')
    output = script_dir / OUTPUT_ROM
    
    # Ensure bin directory exists
    obj_file.parent.mkdir(exist_ok=True)
    
    # Assemble
    print(f"  Assembling {source.name}...")
    success, stdout, err = run_command([ca65, str(source), '-o', str(obj_file)])
    if not success:
        print(f"  Assembly failed: {err}")
        return False
    
    # Link
    print(f"  Linking with {rom_cfg.name}...")
    success, stdout, err = run_command([ld65, '-C', str(rom_cfg), '-o', str(output), str(obj_file)])
    
    # Show any output (ca65/ld65 print info messages to stderr)
    if stdout:
        print(f"  {stdout.strip()}")
    if err and 'ROM total size' in err:
        print(f"  {err.strip()}")
    elif err and not success:
        print(f"  Linking failed: {err}")
    
    # Cleanup object file
    obj_file.unlink(missing_ok=True)
    
    return success and output.exists()


def build(script_dir: Path, config: dict) -> bool:
    """Build the ROM."""
    docker_image = config.get('docker_image', '')
    
    if docker_image:
        return build_docker(script_dir, docker_image)
    else:
        return build_native(script_dir, config)


def do_check(config: dict):
    """Check tool availability."""
    print("Checking build configuration...\n")
    
    docker_image = config.get('docker_image', '')
    
    if docker_image:
        print(f"docker_image: {docker_image}")
        ok, info = check_tool('docker')
        if ok:
            print(f"  Docker: {info}")
            print(f"  Will use image: {docker_image}")
        else:
            print(f"  Docker NOT FOUND")
        print()
        return
    
    ca65 = config.get('ca65', 'ca65')
    ld65 = config.get('ld65', 'ld65')
    
    print("docker_image: (not set - using native tools)")
    print()
    
    # Check ca65
    print(f"ca65: {ca65}")
    ok, info = check_tool(ca65)
    if ok:
        print(f"  OK - {info}")
    else:
        print(f"  NOT FOUND")
        found = find_in_path('ca65')
        if found:
            print(f"  Hint: Found at {found}")
    
    print()
    
    # Check ld65
    print(f"ld65: {ld65}")
    ok, info = check_tool(ld65)
    if ok:
        print(f"  OK - {info}")
    else:
        print(f"  NOT FOUND")
        found = find_in_path('ld65')
        if found:
            print(f"  Hint: Found at {found}")
    
    print()
    print("Configuration options in build.config.json:")
    print()
    print("  Option 1: Set docker_image to use Docker")
    print('    "docker_image": "dawidbuchwald/cc65-tools-make"')
    print()
    print("  Option 2: Set ca65/ld65 paths for native tools")
    print('    "ca65": "/path/to/ca65"')
    print('    "ld65": "/path/to/ld65"')
    print()
    print("Install cc65: https://cc65.github.io/")


def main():
    parser = argparse.ArgumentParser(
        description='Build ORIC DRAM Fault Finder ROM',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python build.py                    # Build ROM
    python build.py --check            # Verify tool configuration

Output:
    bin/dram_fault_finder_rom_auto.bin - 16KB ROM image

Configuration:
    Edit build.config.json to set paths to ca65 and ld65.
"""
    )
    parser.add_argument('--check', action='store_true',
                        help='Check tool availability')
    args = parser.parse_args()
    
    # Paths
    script_dir = Path(__file__).parent
    
    # Load config
    config = load_config(script_dir)
    
    # Handle --check
    if args.check:
        do_check(config)
        return
    
    # Check source exists
    source = script_dir / SOURCE_FILE
    if not source.exists():
        print(f"Error: Source not found: {source}")
        sys.exit(1)
    
    # Check ROM config exists
    rom_cfg = script_dir / ROM_CONFIG
    if not rom_cfg.exists():
        print(f"Error: ROM config not found: {rom_cfg}")
        sys.exit(1)
    
    # Ensure output directory exists
    (script_dir / 'bin').mkdir(exist_ok=True)
    
    # Build
    print(f"Building ORIC DRAM Fault Finder ROM")
    print(f"  Source: {SOURCE_FILE}")
    print(f"  Config: {ROM_CONFIG}")
    
    success = build(script_dir, config)
    
    if not success:
        print("\nBuild failed!")
        print("Run 'python build.py --check' to verify tool configuration.")
        sys.exit(1)
    
    # Get file size
    output = script_dir / OUTPUT_ROM
    size = output.stat().st_size
    
    print(f"\nBuild successful!")
    print(f"  {OUTPUT_ROM} ({size} bytes)")


if __name__ == '__main__':
    main()
