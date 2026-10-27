# Moto Camera Restored

[![LineageOS Device Sync](https://github.com/vrwindsor1/Moto-Camera-Restored/actions/workflows/update-devices.yml/badge.svg)](https://github.com/vrwindsor1/Moto-Camera-Restored/actions/workflows/update-devices.yml)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform: Magisk / KernelSU / APatch](https://img.shields.io/badge/Root-Magisk%20%7C%20KernelSU%20%7C%20APatch-orange.svg)](#installation)

> **Bringing native Motorola Camera features, auxiliary lens support, and proprietary image tuning back to LineageOS and custom ROMs.**

---

## 🎯 Purpose & Mission

When you unlock your bootloader and flash an AOSP-based custom ROM (such as **LineageOS**, **crDroid**, **PixelOS**, or **Evolution X**) on a Motorola device, you gain speed and Android updates—but you lose Motorola's proprietary camera pipeline.

Standard AOSP camera apps (like LineageOS *Aperture*) often cannot take full advantage of:
* **Auxiliary lenses:** Ultrawide, macro, telephoto, and depth sensors.
* **Proprietary imaging algorithms:** Moto Night Vision, Spot Color, Cinemagraph, and Moto AI enhancements.
* **Device-specific tuning:** Correct ISP configurations, exposure calibration, and dual-camera stereoscopic depth maps.

**Moto Camera Restored** bridges this gap by porting, debloating, and adapting the native Motorola Camera suites (**Moto Camera 3, 4, and 5**) to run seamlessly on modern custom ROM builds.

---

## 🌐 Why LineageOS as the Upstream Baseline?

This project is **not** exclusive to LineageOS. However, we specifically target the official LineageOS device roster as our compatibility baseline for a simple reason:

> **Nearly every active custom ROM in the Motorola community forks or inherits its device tree, kernel, and vendor HALs directly from LineageOS.**

Whether you run **LineageOS**, **crDroid**, **PixelOS**, **DerpFest**, or **Havoc**, they almost universally rely on the same upstream LineageOS hardware abstraction layer. If a device has an actively maintained LineageOS tree, it has the hardware foundation required for **Moto Camera Restored** to function properly.

---

## 📱 Device Compatibility Matrix

We automatically track and synchronize our compatibility matrix with the official LineageOS Wiki.

👉 **[View the Full LineageOS Device Compatibility Matrix (COMPATIBILITY.md)](COMPATIBILITY.md)**

### Supported Generations Overview

| Camera Generation | Original Target Era | Target Devices Example | Recommended Suite |
| :--- | :--- | :--- | :--- |
| **Moto Camera 2** | Snapdragon 630 / 632 / 636 / 835 (Android 7–9) | `payton` (Moto X4), `lake` (G7 Plus), `river` (G7), `nash` (Z2 Force) | **MotCamera 3 Suite / 4 Suite** |
| **Moto Camera 3** | Snapdragon 662 / 750G / 765G / 870 (Android 10–11) | `nio` (Moto G100), `kiev` (Moto G 5G), `guamp` (G9 Play) | **MotCamera 3 Suite / 4 Suite** |
| **Moto Camera 4** | Snapdragon 695 / 680 / 778G / 888+ (Android 12–13) | `dubai` (Edge 30), `miami` (Edge 30 Neo), `rhode` (G52) | **MotCamera 4 Suite / 5 Suite** |
| **Moto Camera 5** | Snapdragon 8 Gen 2 / 8+ Gen 1 / 6 Gen 1 (Android 14+) | `rtwo` (Edge 40 Pro / Edge+ 2023), `genevn` (G Stylus 5G 2023) | **MotCamera 5 Suite** |

---

## 🛠️ Installation

### Prerequisites
* Root access via **Magisk (v24.0+)**, **KernelSU (v0.6.0+)**, or **APatch**.
* A Motorola device running an Android 12, 13, 14, or 15 custom ROM based on LineageOS device trees.

### Steps
1. Navigate to the **[Releases](../../releases)** section.
2. Download the installer zip appropriate for your device generation (or the unified installer package).
3. Flash the zip in **Magisk Manager**, **KernelSU Manager**, or **APatch**.
4. Reboot your device.
5. Grant all requested camera, storage, and location permissions on first launch.

---

## 🤖 Automated Upstream Tracking

This repository includes a dedicated GitHub Action ([`.github/workflows/update-devices.yml`](.github/workflows/update-devices.yml)) that:
1. Automatically monitors the [`LineageOS/lineage_wiki`](https://github.com/LineageOS/lineage_wiki) repository weekly.
2. Extracts metadata for all 90+ Motorola devices in the LineageOS ecosystem.
3. Detects active maintainers, branch updates, and chipset configurations.
4. Automatically regenerates and commits changes to [COMPATIBILITY.md](COMPATIBILITY.md).

---

## 🤝 Contributing

Contributions, device bug reports, and pull requests are welcome!
* If a specific camera feature or auxiliary lens fails on your device, please open an **Issue** with logcat output (`adb logcat -s MotoCamera:V CameraManager:V`).
* If you have tested a combination on a device listed in [COMPATIBILITY.md](COMPATIBILITY.md), feel free to submit a PR updating test notes.

---

## 📄 License & Disclaimer

* Custom porting scripts and installer assets are licensed under **GPL-3.0**.
* Motorola, Moto, and related trademarks are the intellectual property of **Motorola Mobility LLC / Lenovo**.
* This is an independent open-source community mod and is not affiliated with or endorsed by Motorola Mobility or the LineageOS Project.
