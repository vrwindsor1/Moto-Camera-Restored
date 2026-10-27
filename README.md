# Moto Camera Restored

<p align="center">
  <a href="https://deepmind.google"><img src="https://img.shields.io/badge/Pair%20Programmed%20With-Google%20DeepMind%20Antigravity-blueviolet?style=flat-square&logo=google" alt="Pair Programmed With Google DeepMind Antigravity"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/vrwindsor1/Moto-Camera-Restored/actions/workflows/update-devices.yml"><img src="https://github.com/vrwindsor1/Moto-Camera-Restored/actions/workflows/update-devices.yml/badge.svg?style=flat-square" alt="LineageOS Device Sync"></a>
</p>

<p align="center">
  <img src="assets/motcamera2_logo.png" width="88" height="88" alt="Moto Camera 2" />
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="assets/motcamera3_logo.png" width="88" height="88" alt="Moto Camera 3" />
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="assets/motcamera4_logo.png" width="88" height="88" alt="Moto Camera 4" />
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="assets/motcamera5_logo.png" width="88" height="88" alt="Moto Camera 5" />
</p>

An all-in-one universal recovery package compiler that extracts Motorola Camera suites (**Moto Camera 2, 3, 4, and 5**), companion AI services, vendor hardware abstraction layers (HALs), and multi-camera tuning libraries directly from official Motorola stock firmware and packages them into **flashable zip packages for recovery sideload** on custom ROMs.

---

## 🎯 Purpose & Mission

When you unlock your bootloader and flash an AOSP-based custom ROM (such as **LineageOS**, **crDroid**, **PixelOS**, or **Evolution X**) on a Motorola device, you gain speed, cleaner software, and newer Android versions—but you lose Motorola's proprietary camera pipeline.

Standard AOSP camera apps (like LineageOS *Aperture*) frequently cannot take full advantage of:
* **Auxiliary lenses:** Ultrawide, macro, telephoto, and depth sensors.
* **Ultra-Res mode:** Full-sensor high-resolution capture (e.g., 50MP, 64MP, 108MP, or 200MP Quad/Nonacell pixel binning bypass).
* **Proprietary imaging algorithms:** Moto Night Vision, Spot Color, Cinemagraph, and Moto AI photo enhancements.
* **Device-specific tuning:** Correct ISP configurations, exposure calibration, and dual-camera stereoscopic depth maps.

**Moto Camera Restored** allows you to feed in your device's stock firmware and automatically generate a recovery package that restores the native camera for devices that used **Moto Camera 2**, **Moto Camera 3**, **Moto Camera 4**, or **Moto Camera 5**.

> [!NOTE]
> **Native Restoration, Not Cross-Porting**:  
> The explicit goal of this project is to restore the **original camera generation each device was designed to run** (e.g., restoring Moto Camera 2 on devices that originally shipped with Camera 2, or Moto Camera 4 on devices designed for Camera 4). We do **not** cross-port newer, incompatible camera versions onto older hardware. This ensures 100% hardware fidelity, preserving factory ISP calibration, multi-lens switching, and sensor stability.

---

## 🌐 Why LineageOS as the Upstream Baseline?

This project is **not** exclusive to LineageOS. However, we specifically target the official LineageOS device roster as our compatibility baseline for a simple reason:

> **Nearly every active custom ROM in the Motorola community forks or inherits its device tree, kernel, and vendor HALs directly from LineageOS.**

Whether you run **LineageOS**, **crDroid**, **PixelOS**, **DerpFest**, or **Havoc**, they almost universally rely on the same upstream LineageOS hardware abstraction layer. If a device has an actively maintained LineageOS tree, it provides the clean, standard hardware foundation required for the restored camera stack to function properly.

---

## 📱 Per-Device Compatibility Table

We automatically track and synchronize our per-device compatibility table with the official LineageOS Wiki.

👉 **[View the Per-Device Compatibility Table](COMPATIBILITY.md)**  
📝 **[Submit a Compatibility Report](https://github.com/vrwindsor1/Moto-Camera-Restored/issues/new?template=compatibility_report.yml)**

### 📷 Camera Generation Compatibility Status

| Generation | Package Name | Version Range | Official Device Compatibility | Restored Status |
| :--- | :--- | :--- | :--- | :---: |
| **Moto Camera 2** | `com.motorola.camera2` | `v5.x` – `v7.x` *(e.g. 7.2.x)* | Select devices launched in **2016 – 2019** | ⏳ Planned |
| **Moto Camera 3** | `com.motorola.camera3` | `v7.x` – `v8.x` *(e.g. 8.0.x, 8.1.x)* | Select devices launched in **2020 and beyond** | ⏳ Planned |
| **Moto Camera 4** | `com.motorola.camera3` | `v9.x` *(e.g. 9.0.x, 9.1.x)* | Select devices launched in **2022 and beyond** | 🟢 Working |
| **Moto Camera 5** | `com.motorola.camera5` | `v10.x` *(e.g. 10.0.x)* | Select devices launched in **2025 and beyond** | 🟡 In Development |

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

### 2. Get the Compiler

Choose either **Option A** (clone full repository) or **Option B** (download standalone script for your OS):

#### Option A: Clone the Repository (Recommended)
Clones the complete repository with all template scaffolding included:
```bash
git clone https://github.com/vrwindsor1/Moto-Camera-Restored.git
cd Moto-Camera-Restored
```

#### Option B: Standalone Script Download
If you prefer not to clone the full repository, you can download just the compiler script for your operating system:

* **Linux:**
  ```bash
  curl -sSLO https://raw.githubusercontent.com/vrwindsor1/Moto-Camera-Restored/main/compile_recovery_package_linux.sh
  chmod +x compile_recovery_package_linux.sh
  ```
* **Windows (PowerShell):**
  ```powershell
  Invoke-WebRequest -Uri "https://raw.githubusercontent.com/vrwindsor1/Moto-Camera-Restored/main/compile_recovery_package_windows.ps1" -OutFile "compile_recovery_package_windows.ps1"
  ```

> [!NOTE]
> When using the standalone script, the compiler will detect that local templates are missing and will prompt you to press `[Enter]` to automatically download the matching recovery template module directly from GitHub.

---

### 3. Build the Recovery Package

The compiler extracts your stock firmware, profiles your device hardware and Android release metadata, determines which camera generation is present (`camera4`, `camera5`, etc.), and dynamically resolves the matching recovery scaffolding templates.

#### 📦 Modular Template Resolution
* **Automatic Local Detection:** If you cloned the repository or have the `templates/<camera_gen>` folder in your working directory, the compiler automatically loads it without prompting.
* **Missing Templates / Standalone Execution:** If you run the compiler standalone without the local `templates/` directory present, it will prompt:
  ```text
  [WARN] Recovery template folder for Moto Camera 4 ('templates/camera4') was not found in working directory.

  Please point to a local template directory, or press [Enter] to automatically download from GitHub:
  > Local template path [Enter to download]: 
  ```
  * **Press `[Enter]`:** Automatically downloads the required recovery template module from GitHub and saves it into `./templates/<camera_gen>/` with proper POSIX executable permissions (`toybox`, `update-binary`), caching it for future builds.
  * **Enter a Local Path:** Point to an existing directory on disk containing your templates (such as an existing repository clone or template folder).

#### Linux
```bash
chmod +x compile_recovery_package_linux.sh

# Interactive mode (prompts for firmware path and template resolution):
./compile_recovery_package_linux.sh

# CLI mode:
./compile_recovery_package_linux.sh "/path/to/stock_firmware" [output_dir] [template_dir]
```

#### Windows (PowerShell)
```powershell
# Interactive mode (prompts for firmware path and template resolution):
.\compile_recovery_package_windows.ps1

# CLI mode:
.\compile_recovery_package_windows.ps1 -FirmwarePath "C:\path\to\stock_firmware" [-OutputDir "C:\output"] [-TemplateDir "C:\templates"]
```

The compiled package and build manifest will be placed in the `output/` directory:
```text
output/MotoCameraRestored_<device>_Recovery_Installer.zip
output/MotoCameraRestored_<device>_info.txt
```

---

### 4. Flash via Recovery Sideload
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
4. Automatically regenerates and commits changes to the [Per-Device Compatibility Table](COMPATIBILITY.md).

---

## 🤝 Contributing

Contributions, device bug reports, and pull requests are welcome!
* If a specific auxiliary lens or camera mode fails on your device, please open an **Issue** with logcat output (`adb logcat -s MotoCamera:V CameraManager:V`).
* If you have tested a combination on a device listed in the [Per-Device Compatibility Table](COMPATIBILITY.md), feel free to submit a PR updating test notes.

---

## 📄 License & Disclaimer

- The compiler, packaging scripts, and template assets are released under the **[Apache License 2.0](LICENSE)**.
- **Motorola**, **Moto**, and associated logos are trademarks of **Motorola Mobility LLC / Lenovo**.
- This is an independent, non-commercial open-source community project and is not affiliated with or endorsed by Motorola Mobility LLC or the LineageOS Project.
