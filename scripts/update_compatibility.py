#!/usr/bin/env python3
"""
update_compatibility.py
Automatically parses the LineageOS Wiki dataset to extract all Motorola devices,
identifies active maintainer status, infers native camera generations, and
generates a comprehensive COMPATIBILITY.md matrix.
"""

import os
import sys
import argparse
from datetime import datetime, timezone
import yaml

# Heuristic categorization for Motorola Camera generations based on release year / SoC / codename
CAM2_CODENAMES = {
    'payton', 'lake', 'river', 'ocean', 'evert', 'nash', 'beckham',
    'messi', 'channel', 'ali', 'potter', 'sanders', 'athene', 'cedric',
    'montana', 'albus', 'griffin', 'addison'
}

CAM3_CODENAMES = {
    'kane', 'troika', 'kiev', 'nairo', 'nio', 'denver', 'cebu',
    'guam', 'guamna', 'guamp', 'capri', 'caprip', 'borneo', 'bathena',
    'ibiza', 'racer'
}

CAM5_CODENAMES = {
    'rtwo', 'avatrn', 'fogo', 'fogos', 'lamu', 'lyriq', 'bronco'
}

def infer_camera_generation(device):
    codename = device.get('codename', '').lower()
    release = str(device.get('release', ''))
    soc = str(device.get('soc', '')).lower()

    if codename in CAM2_CODENAMES:
        return "Moto Camera 2", "MotCamera 2 / 3 Recovery Suite"
    if codename in CAM5_CODENAMES:
        return "Moto Camera 5", "MotCamera 5 Recovery Suite"
    if codename in CAM3_CODENAMES:
        return "Moto Camera 3", "MotCamera 3 / 4 Recovery Suite"

    # Fallback heuristics
    try:
        year = int(release.split('-')[0]) if release else 0
    except ValueError:
        year = 0

    if year >= 2023 or 'gen 2' in soc or 'gen 3' in soc or '8+ gen1' in soc:
        return "Moto Camera 5", "MotCamera 5 Recovery Suite"
    elif year >= 2021 or '695' in soc or '778g' in soc or '680' in soc:
        return "Moto Camera 4", "MotCamera 4 / 5 Recovery Suite"
    elif year >= 2019:
        return "Moto Camera 3", "MotCamera 3 / 4 Recovery Suite"
    else:
        return "Moto Camera 2", "MotCamera 2 / 3 Recovery Suite"

def parse_lineage_devices(devices_dir):
    devices = []
    if not os.path.isdir(devices_dir):
        print(f"Error: Directory {devices_dir} does not exist.")
        sys.exit(1)

    for fname in sorted(os.listdir(devices_dir)):
        if not fname.endswith('.yml'):
            continue
        filepath = os.path.join(devices_dir, fname)
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                data = yaml.safe_load(f)
        except Exception as e:
            print(f"Warning: Failed to parse {fname}: {e}")
            continue

        if not isinstance(data, dict):
            continue

        vendor = data.get('vendor', '') or data.get('vendor_short', '')
        if 'motorola' not in vendor.lower():
            continue

        maintainers = data.get('maintainers', [])
        is_active = bool(maintainers) and len(maintainers) > 0

        codename = data.get('codename') or fname.replace('.yml', '')
        name = data.get('name', 'Unknown')
        current_branch = str(data.get('current_branch', 'N/A'))
        soc = data.get('soc', 'N/A')
        release = data.get('release', 'N/A')
        models = data.get('models', [])

        native_cam, recommended_suite = infer_camera_generation({
            'codename': codename,
            'release': release,
            'soc': soc
        })

        devices.append({
            'name': name,
            'codename': codename,
            'branch': current_branch,
            'soc': soc,
            'release': release,
            'maintainers': maintainers,
            'is_active': is_active,
            'native_cam': native_cam,
            'recommended_suite': recommended_suite,
            'models': models
        })

    return devices

def generate_markdown(devices, output_file):
    active_devices = [d for d in devices if d['is_active']]
    legacy_devices = [d for d in devices if not d['is_active']]

    # Sort active devices alphabetically by device name
    active_devices.sort(key=lambda x: x['name'].lower())
    legacy_devices.sort(key=lambda x: x['name'].lower())

    now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')

    content = f"""# Device Compatibility Matrix

> **Automatic Sync:** This table is automatically generated and synchronized with the official [LineageOS Wiki](https://github.com/LineageOS/lineage_wiki) repository via GitHub Actions.  
> **Last Updated:** `{now_utc}`  
> **Total Motorola Devices Tracked:** `{len(devices)}` (`{len(active_devices)}` actively maintained, `{len(legacy_devices)}` discontinued)

---

## 📱 Actively Maintained Motorola Devices ({len(active_devices)})

Devices listed here have active LineageOS maintainers and up-to-date trees. Since downstream custom ROMs (such as **crDroid**, **PixelOS**, **Evolution X**, and **DerpFest**) inherit LineageOS trees and HALs, these devices represent prime targets for **Moto Camera Restored**.

All packages are compiled into **recovery sideload flashable zips** (`adb sideload`) with **`addon.d` OTA survival**—**no root (Magisk/KernelSU) required**.

| Device Name | Codename | LineageOS Branch | Chipset / SoC | Stock Camera Era | Recommended Recovery Suite | Maintainers |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
"""

    for d in active_devices:
        maintainer_str = ", ".join(d['maintainers']) if d['maintainers'] else "None"
        content += f"| **{d['name']}** | `{d['codename']}` | {d['branch']} | {d['soc']} | {d['native_cam']} | `{d['recommended_suite']}` | {maintainer_str} |\n"

    content += f"""
---

## 🏛️ Legacy / Discontinued Motorola Devices ({len(legacy_devices)})

These devices previously received official LineageOS builds but are no longer actively maintained upstream. Compatibility depends on community-maintained unofficial ROMs.

<details>
<summary>Click to expand legacy devices list</summary>

| Device Name | Codename | Last Branch | Chipset / SoC | Stock Camera Era |
| :--- | :--- | :--- | :--- | :--- |
"""

    for d in legacy_devices:
        content += f"| {d['name']} | `{d['codename']}` | {d['branch']} | {d['soc']} | {d['native_cam']} |\n"

    content += """
</details>

---

## 🔍 How Recommendations Work
* **Moto Camera 2 Era Devices:** Devices that originally shipped with Android 7–9 ran `com.motorola.camera2`. Moto Camera Restored aims to provide both a native **MotCamera 2 Recovery Suite** adapted for modern Android as well as modern **MotCamera 3 / 4** alternative packages for enhanced auxiliary sensor support.
* **Moto Camera 3 & 4 Era Devices:** Devices shipping with modern multi-lens arrays (ultrawide, macro, telephoto) lose vendor post-processing when flashing custom ROMs. The compiled recovery package restores Moto camera algorithms, physical lens switching, and system permissions into the ROM partition.
* **Moto Camera 5 Era Devices:** High-end and recent 2023–2025 devices utilize Moto's newer AI pipelines requiring the **MotCamera 5 Recovery Suite**.
* **OTA Survival:** Every compiled package installs an `addon.d` backup script into the system partition to survive weekly LineageOS updates without re-sideloading.
"""

    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"Successfully generated {output_file} with {len(devices)} devices.")

def main():
    parser = argparse.ArgumentParser(description="Update COMPATIBILITY.md from LineageOS Wiki data")
    parser.add_argument("--wiki-path", default="/tmp/lineage_wiki", help="Path to cloned lineage_wiki repository")
    parser.add_argument("--output", default="COMPATIBILITY.md", help="Output Markdown path")
    args = parser.parse_args()

    devices_dir = os.path.join(args.wiki_path, "_data", "devices")
    devices = parse_lineage_devices(devices_dir)
    generate_markdown(devices, args.output)

if __name__ == '__main__':
    main()
