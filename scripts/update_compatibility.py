#!/usr/bin/env python3
"""
update_compatibility.py
Automatically parses the LineageOS Wiki dataset to extract all Motorola devices,
identifies active maintainer status, infers native camera generations, checks
community test reports in reports/, and generates a comprehensive COMPATIBILITY.md matrix.
"""

import os
import sys
import re
import argparse
from datetime import datetime, timezone
import yaml

def infer_camera_generation(device):
    codename = device.get('codename', '').lower()
    release = str(device.get('release', ''))

    try:
        year = int(release.split('-')[0]) if release else 0
    except ValueError:
        year = 0

    # Motorola official camera era launch windows:
    # - Moto Camera 5: 2025 and beyond (Hello UI / Android 15+, e.g. lamu)
    # - Moto Camera 4: 2022 – 2024 (MyUX v2-v4 / Android 12-14)
    # - Moto Camera 3: 2020 – 2021 (MyUX v1 / Android 10-11)
    # - Moto Camera 2: 2016 – 2019 (Android 7-9)
    # - Moto Camera 1: 2011 – 2015 (Legacy / Android 4-6)
    if codename in {'lamu'}:
        return "Moto Camera 5"
    elif year >= 2025:
        return "Moto Camera 5"
    elif year >= 2022:
        return "Moto Camera 4"
    elif year >= 2020:
        return "Moto Camera 3"
    elif year >= 2016:
        return "Moto Camera 2"
    else:
        return "Moto Camera 1"

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

        native_cam = infer_camera_generation({
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
            'models': models if isinstance(models, list) else ([models] if models else [])
        })

    return devices

def get_device_status(codename, reports_dir="reports"):
    report_file = os.path.join(reports_dir, f"{codename}.md")
    if os.path.exists(report_file):
        try:
            with open(report_file, 'r', encoding='utf-8') as f:
                content = f.read()
            m = re.search(r"-\s+\*\*Current Overall Status:\*\*\s*(.+)", content)
            if m:
                raw_status = m.group(1).strip()
                clean_status = raw_status.replace("**", "").strip()
                return clean_status
        except Exception:
            pass
    return "❔ Untested"

def ensure_device_report_files(devices, reports_dir="reports"):
    os.makedirs(reports_dir, exist_ok=True)

    # Group devices by codename
    by_codename = {}
    for d in devices:
        c = d['codename']
        by_codename.setdefault(c, []).append(d)

    for codename, dev_list in by_codename.items():
        report_file = os.path.join(reports_dir, f"{codename}.md")
        if os.path.exists(report_file):
            continue

        names = sorted(list(set(d['name'] for d in dev_list)))
        combined_names = " / ".join(names)
        native_cam = dev_list[0]['native_cam']

        all_models = []
        for d in dev_list:
            for m in d.get('models', []):
                if m and str(m) not in all_models:
                    all_models.append(str(m))

        models_str = ", ".join(f"`{m}`" for m in all_models) if all_models else "—"

        report_content = f"""# Device Report: {combined_names} (`{codename}`)

<p align="center">
  <a href="../COMPATIBILITY.md"><img src="https://img.shields.io/badge/⬅%20Back%20to-Compatibility%20Matrix-blue?style=flat-square" alt="Compatibility Matrix"></a>
  <a href="https://github.com/vrwindsor1/Moto-Camera-Restored/issues/new?template=compatibility_report.yml"><img src="https://img.shields.io/badge/Submit-New%20Report-success?style=flat-square&logo=github" alt="Submit Report"></a>
  <a href="../LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=flat-square" alt="License"></a>
</p>

## Device Information

- **Marketing Name:** {combined_names}
- **Codename:** `{codename}`
- **Model Number(s):** {models_str}
- **Stock Camera Era:** {native_cam}
- **Current Overall Status:** ❔ **Untested**
- **Total Community Reports:** 0

---

## Community Test Reports

| Report | Compiler | Custom ROM | Stock Firmware | Outcome | Tested Features / Notes |
| :--- | :---: | :--- | :--- | :---: | :--- |
| *No reports yet* | — | — | — | ❔ Untested | Waiting for community test report |

---

<p align="center">
  <a href="../COMPATIBILITY.md">⬅ Back to Full Compatibility Matrix</a> &bull; <a href="../README.md">Installer Documentation</a>
</p>
"""
        with open(report_file, 'w', encoding='utf-8') as f:
            f.write(report_content)

def generate_markdown(devices, output_file, reports_dir="reports"):
    active_devices = [d for d in devices if d['is_active']]
    legacy_devices = [d for d in devices if not d['is_active']]

    active_devices.sort(key=lambda x: x['name'].lower())
    legacy_devices.sort(key=lambda x: x['name'].lower())

    now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')

    content = f"""# Device Compatibility Matrix

> **Automatic Sync:** This table is automatically generated and synchronized with the official [LineageOS Wiki](https://github.com/LineageOS/lineage_wiki) repository via GitHub Actions.  
> **Last Updated:** `{now_utc}`  
> **Total Motorola Devices Tracked:** `{len(devices)}` (`{len(active_devices)}` actively maintained, `{len(legacy_devices)}` discontinued)

---

## Quick Links

- 🏠 **[Installer Documentation & Source (README)](README.md)**
- 📂 **[Individual Device Reports Directory (reports/)](reports/)**
- 📝 **[Submit a Compatibility Report (GitHub Form)](https://github.com/vrwindsor1/Moto-Camera-Restored/issues/new?template=compatibility_report.yml)**
- 🐛 **[Report a Tool Bug / Script Issue](https://github.com/vrwindsor1/Moto-Camera-Restored/issues/new?template=bug_report.yml)**

---

## Result Classifications

Every tested device outcome is classified into one of the following categories:

| Status Badge | Result Category | Definition |
| :---: | :--- | :--- |
| 🟢 | **`Works Perfectly`** | Full success. Moto Camera launches cleanly; all rear physical sensors (Main, Ultrawide, Macro, Telephoto), front selfie, Ultra-Res (high-resolution photo mode), and video recording function without issues. |
| 🟡 | **`Mostly Working`** | Partial success. The app launches and photos can be taken, but specific auxiliary sensors or advanced modes (e.g., slow motion, ultrawide switching, Ultra-Res mode) do not work. |
| 🔴 | **`App Crashes`** | Sideload finishes and the app is installed, but the app immediately crashes, freezes, or force-closes upon launch. |
| ⚪ | **`App Missing`** | Sideload completes, but after booting the ROM, Moto Camera is completely absent from the app drawer and system partition. |
| ⛔ | **`Won't Boot`** | The flashed package caused the device to bootloop, dump into recovery, or hang on the boot animation (softbrick). |
| ⚠️ | **`Won't Compile`** | The compiler script encountered an error, missing dependency, or failed partition extraction and could not generate a flashable zip. |
| ❔ | **`Untested`** | No community-verified test reports submitted yet, but this device is expected to be compatible based on its stock Moto Camera architecture. |

---

## 📱 Actively Maintained Motorola Devices ({len(active_devices)})

Devices listed here have active LineageOS maintainers and up-to-date trees. Since downstream custom ROMs (such as **crDroid**, **PixelOS**, **Evolution X**, and **DerpFest**) inherit LineageOS trees and HALs, these devices represent prime targets for **Moto Camera Restored**.

| Device Name | Codename | LineageOS Branch | Stock Camera Era | Status |
| :--- | :--- | :--- | :--- | :---: |
"""

    for d in active_devices:
        status = get_device_status(d['codename'], reports_dir)
        content += f"| [**{d['name']}**](reports/{d['codename']}.md) | `{d['codename']}` | {d['branch']} | {d['native_cam']} | {status} |\n"

    content += f"""
---

## 🏛️ Legacy / Discontinued Motorola Devices ({len(legacy_devices)})

These devices previously received official LineageOS builds but are no longer actively maintained upstream. Compatibility depends on community-maintained unofficial ROMs.

<details>
<summary>Click to expand legacy devices list</summary>

| Device Name | Codename | Last Branch | Stock Camera Era | Status |
| :--- | :--- | :--- | :--- | :---: |
"""

    for d in legacy_devices:
        status = get_device_status(d['codename'], reports_dir)
        content += f"| [{d['name']}](reports/{d['codename']}.md) | `{d['codename']}` | {d['branch']} | {d['native_cam']} | {status} |\n"

    content += """
</details>
"""

    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"Successfully generated {output_file} with {len(devices)} devices.")

def update_issue_template(devices, template_file=".github/ISSUE_TEMPLATE/compatibility_report.yml"):
    if not os.path.exists(template_file):
        return

    with open(template_file, "r", encoding="utf-8") as f:
        content = f.read()

    unique_devices = {}
    for d in devices:
        key = (d['name'], d['codename'])
        unique_devices[key] = True

    sorted_devs = sorted(unique_devices.keys(), key=lambda x: x[0].lower())
    option_lines = [f'        - "{name} ({codename})"' for name, codename in sorted_devs]
    new_options_block = "\n".join(option_lines)

    pattern = r'(id:\s*device\s*\n\s*attributes:\s*\n\s*label:\s*[^\n]+\n\s*description:\s*[^\n]+\n\s*options:\s*\n)(?:[ \t]*- [^\n]+\n)+'
    if re.search(pattern, content):
        updated_content = re.sub(pattern, r'\g<1>' + new_options_block + '\n', content)
        with open(template_file, "w", encoding="utf-8") as f:
            f.write(updated_content)
        print(f"Successfully updated device dropdown options in {template_file}.")

def main():
    parser = argparse.ArgumentParser(description="Update COMPATIBILITY.md from LineageOS Wiki data")
    parser.add_argument("--wiki-path", default="/tmp/lineage_wiki", help="Path to cloned lineage_wiki repository")
    parser.add_argument("--output", default="COMPATIBILITY.md", help="Output Markdown path")
    parser.add_argument("--reports-dir", default="reports", help="Directory where device report markdown files reside")
    parser.add_argument("--issue-template", default=".github/ISSUE_TEMPLATE/compatibility_report.yml", help="Path to compatibility issue template")
    args = parser.parse_args()

    devices_dir = os.path.join(args.wiki_path, "_data", "devices")
    devices = parse_lineage_devices(devices_dir)
    ensure_device_report_files(devices, args.reports_dir)
    generate_markdown(devices, args.output, args.reports_dir)
    update_issue_template(devices, args.issue_template)

if __name__ == '__main__':
    main()
