# Moto Camera Restored

<p align="center">
  <a href="https://deepmind.google"><img src="https://img.shields.io/badge/Pair%20Programmed%20With-Google%20DeepMind%20Antigravity-blueviolet?style=flat-square&logo=google" alt="Pair Programmed With Google DeepMind Antigravity"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=flat-square" alt="License"></a>
  <a href="#flash-via-recovery-sideload"><img src="https://img.shields.io/badge/Method-Recovery%20Sideload%20(No%20Root)-success.svg?style=flat-square" alt="Recovery Sideload"></a>
  <a href="#ota-survival-addond"><img src="https://img.shields.io/badge/OTA-addon.d%20Survival-orange.svg?style=flat-square" alt="addon.d Survival"></a>
  <a href="https://github.com/vrwindsor1/Moto-Camera-Restored/actions/workflows/update-devices.yml"><img src="https://github.com/vrwindsor1/Moto-Camera-Restored/actions/workflows/update-devices.yml/badge.svg?style=flat-square" alt="LineageOS Device Sync"></a>
</p>

An all-in-one universal recovery package compiler that extracts Motorola Camera suites (**Moto Camera 2, 3, 4, and 5**), companion AI services, vendor hardware abstraction layers (HALs), and multi-camera tuning libraries directly from official Motorola stock firmware and packages them into **flashable zip packages for recovery sideload** on custom ROMs (Android 13+).

> [!IMPORTANT]
> **100% Rootless — Recovery Sideload Only**:  
> This project does **NOT** use Magisk, KernelSU, or APatch. Camera packages are compiled into recovery-flashable zips installed via `adb sideload` in **Lineage Recovery, TWRP, or OrangeFox**. The camera stack integrates directly into the ROM partition structure.

> [!NOTE]
> **No Proprietary Files Hosted**:  
> This repository contains **no copyrighted binaries, proprietary firmware blobs, or Motorola APKs**. All device-specific camera packages and HAL services are dynamically harvested on your local machine directly from official Motorola stock firmware provided by the user.

> [!TIP]
> **OTA Survival (`addon.d`) Included**:  
> All generated recovery packages include an `addon.d` survival script. Camera apps, services, and libraries survive custom ROM OTA updates without needing to be re-flashed.

---

## 🎯 Purpose & Mission

When you unlock your bootloader and flash an AOSP-based custom ROM (such as **LineageOS**, **crDroid**, **PixelOS**, or **Evolution X**) on a Motorola device, you gain speed, cleaner software, and newer Android versions—but you lose Motorola's proprietary camera pipeline.

Standard AOSP camera apps (like LineageOS *Aperture*) frequently cannot take full advantage of:
* **Auxiliary lenses:** Ultrawide, macro, telephoto, and depth sensors.
* **Proprietary imaging algorithms:** Moto Night Vision, Spot Color, Cinemagraph, and Moto AI photo enhancements.
* **Device-specific tuning:** Correct ISP configurations, exposure calibration, and dual-camera stereoscopic depth maps.

**Moto Camera Restored** unites the tooling for **MotCamera 2**, **MotCamera 3**, **MotCamera 4**, and **MotCamera 5** into a single toolkit. It allows you to feed in your device's stock firmware and automatically generate a tailored recovery package that restores native camera performance.

> [!NOTE]
> **Native Restoration, Not Cross-Porting**:  
> The explicit goal of this project is to restore the **original camera generation each device was designed to run** (e.g., restoring Moto Camera 2 on devices that originally shipped with Camera 2, or Moto Camera 4 on devices designed for Camera 4). We do **not** cross-port newer, incompatible camera versions onto older hardware. This ensures 100% hardware fidelity, preserving factory ISP calibration, multi-lens switching, and sensor stability.

---

## 🌐 Why LineageOS as the Upstream Baseline?

This project is **not** exclusive to LineageOS. However, we specifically target the official LineageOS device roster as our compatibility baseline for a simple reason:

> **Nearly every active custom ROM in the Motorola community forks or inherits its device tree, kernel, and vendor HALs directly from LineageOS.**

Whether you run **LineageOS**, **crDroid**, **PixelOS**, **DerpFest**, or **Havoc**, they almost universally rely on the same upstream LineageOS hardware abstraction layer. If a device has an actively maintained LineageOS tree, it provides the clean, standard hardware foundation required for the restored camera stack to function properly.

---

## 📱 Device Compatibility Matrix

We automatically track and synchronize our compatibility matrix with the official LineageOS Wiki.

👉 **[View the Full LineageOS Device Compatibility Matrix (COMPATIBILITY.md)](COMPATIBILITY.md)**

### 🔍 How to Identify Your Device's Camera Generation

| Generation | Package Name | Version Range | Official Launch Window (Play Store) | Key Identifying Features |
| :--- | :--- | :--- | :--- | :--- |
| **Moto Camera 2** | `com.motorola.camera2` | `v5.x` – `v7.x` *(e.g. 7.2.x)* | Select devices launched in **2016 – 2019** | Classic circular carousel dial UI, quick-capture wrist twist gesture, early dual-lens depth slider. |
| **Moto Camera 3** | `com.motorola.camera3` | `v7.x` – `v8.x` *(e.g. 8.0.x, 8.1.x)* | Select devices launched in **2020 and beyond** | Modern flat UI layout with dedicated bottom mode drawer, integrated Google Lens shortcut, Spot Color and Cinemagraph modes. |
| **Moto Camera 4** | `com.motorola.camera3` | `v9.x` *(e.g. 9.0.x, 9.1.x)* | Select devices launched in **2022 and beyond** | Material You dynamic theming, companion AI engine (`camera.provider.ai`), multi-mic audio zoom, redesigned quick settings panel. |
| **Moto Camera 5 / Pro** | `com.motorola.camera5`<br>`com.motorola.camerapro`<br>`com.motorola.camera3` | `v1.x` *(Pro/Cam5)* or `v10.x+` | Select devices launched in **2025 and beyond** | Hello UI design language, Moto AI photo enhancement engine, Pro manual controls with focus peaking, zebra striping, action stabilization. |

> [!TIP]
> **How to verify your stock camera generation:**  
> On your stock device or firmware:
> * **App Info (GUI):** Open **Settings ➔ Apps ➔ Camera**, scroll to the bottom to view the app version.
> * **Package Name (CLI):** Run `adb shell pm list packages | grep motorola.camera`
> * **Version Code (CLI):** Run `adb shell dumpsys package <package_name> | grep versionName`

---

## 🛠️ Installation & Usage Guide

### 1. Prerequisites
- **Official Motorola Stock Firmware** for your device (downloaded via Motorola Rescue and Smart Assistant / RSA, mirrors.lolinet.com, or official firmware dumps). The compiler accepts:
  - A directory containing `super.img_sparsechunk.*`
  - A stock firmware `.zip` archive
  - Extracted partition images (`product.img`, `system_ext.img`, etc.)
  - A pre-extracted folder structure (`product/`, `system_ext/`, etc.)
- A computer running **Linux** or **Windows**.
- A custom recovery installed on your phone (**Lineage Recovery**, **TWRP**, or **OrangeFox**).

#### Host System Dependencies (Linux)
Ensure dynamic partition and filesystem extraction tools are installed:

| Distribution | Command |
| :--- | :--- |
| **Fedora / RHEL** | `sudo dnf install android-tools erofs-utils zip curl python3` |
| **Ubuntu / Debian** | `sudo apt install android-sdk-libsparse-utils erofs-utils zip curl python3` |
| **Arch Linux** | `sudo pacman -S android-tools erofs-utils zip curl python` |

---

### 2. Build the Recovery Package

#### Linux
```bash
chmod +x compile_recovery_package_linux.sh

# Interactive mode (prompts for firmware path):
./compile_recovery_package_linux.sh

# CLI mode:
./compile_recovery_package_linux.sh "/path/to/stock_firmware"
```

#### Windows
* **PowerShell:**
  ```powershell
  .\compile_recovery_package_windows.ps1 -FirmwarePath "C:\path\to\stock_firmware"
  ```
* **Batch:**
  Double-click `compile_recovery_package_windows.bat` and follow the prompts.

The compiled package will be placed in the `output/` directory:
```text
output/MotoCameraRestored_<device>_Recovery_Installer.zip
```

---

### 3. Flash via Recovery Sideload
1. Reboot your Motorola device into **Recovery Mode** (Lineage Recovery, TWRP, or OrangeFox).
2. Put the device into sideload mode:
   * **Lineage Recovery:** Select **Apply Update** $\rightarrow$ **Apply from ADB**.
   * **TWRP / OrangeFox:** Select **Advanced** $\rightarrow$ **ADB Sideload** (swipe to confirm).
3. Connect the device to your PC via USB and execute:
   ```bash
   adb sideload output/MotoCameraRestored_<device>_Recovery_Installer.zip
   ```
4. If Lineage Recovery prompts about signature verification failing, choose **Install anyway** (expected for custom packages).
5. Once sideloading completes successfully, select **Reboot system now**.

---

## 🔄 OTA Survival (`addon.d`)

The generated recovery package places an `addon.d` survival script in `/system/addon.d/` (or `/system_ext/addon.d/`). When you update your LineageOS or custom ROM build:
1. The ROM updater backs up all restored camera apps, permissions, and HAL libraries.
2. The ROM update is applied.
3. The `addon.d` script automatically restores the camera files before rebooting.
4. **No re-flashing required after ROM OTAs.**

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
* If a specific auxiliary lens or camera mode fails on your device, please open an **Issue** with logcat output (`adb logcat -s MotoCamera:V CameraManager:V`).
* If you have tested a combination on a device listed in [COMPATIBILITY.md](COMPATIBILITY.md), feel free to submit a PR updating test notes.

---

## 📄 License & Disclaimer

- The compiler, packaging scripts, and template assets are released under the **[Apache License 2.0](LICENSE)**.
- **Motorola**, **Moto**, and associated logos are trademarks of **Motorola Mobility LLC / Lenovo**.
- This is an independent, non-commercial open-source community project and is not affiliated with or endorsed by Motorola Mobility LLC or the LineageOS Project.
