# Per-Device Compatibility Matrix

> **Automatic Sync:** This table is automatically generated and synchronized with the official [LineageOS Wiki](https://github.com/LineageOS/lineage_wiki) repository via GitHub Actions.  
> **Last Updated:** `2026-10-27 16:50:00 UTC`  
> **Total Motorola Devices Tracked:** `97` (`61` actively maintained, `36` discontinued)

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

## 📱 Actively Maintained Motorola Devices (61)

Devices listed here have active LineageOS maintainers and up-to-date trees. Since downstream custom ROMs (such as **crDroid**, **PixelOS**, **Evolution X**, and **DerpFest**) inherit LineageOS trees and HALs, these devices represent prime targets for **Moto Camera Restored**.

| Device Name | Codename | LineageOS Branch | Stock Camera Era | Status |
| :--- | :--- | :--- | :--- | :---: |
| [**defy 2021**](reports/bathena.md) | `bathena` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**edge**](reports/racer.md) | `racer` | 23.2 | Moto Camera 3 | ❔ Untested |
| [**edge 20**](reports/berlin.md) | `berlin` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**edge 20 pro**](reports/pstar.md) | `pstar` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**edge 2021**](reports/berlna.md) | `berlna` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**edge 2024**](reports/avatrn.md) | `avatrn` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**edge 30**](reports/dubai.md) | `dubai` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**edge 30 fusion**](reports/tundra.md) | `tundra` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**edge 30 neo**](reports/miami.md) | `miami` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**edge 30 ultra**](reports/eqs.md) | `eqs` | 23.2 | Moto Camera 4 | ❔ Untested |
| [**edge 40 pro**](reports/rtwo.md) | `rtwo` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**edge s**](reports/nio.md) | `nio` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**Edge S30**](reports/xpeng.md) | `xpeng` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**edge+ (2023)**](reports/rtwo.md) | `rtwo` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**moto e7 plus**](reports/guam.md) | `guam` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto g 5G**](reports/kiev.md) | `kiev` | 23.2 | Moto Camera 3 | ❔ Untested |
| [**moto g 5G - 2024**](reports/fogo.md) | `fogo` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**moto g 5G plus**](reports/nairo.md) | `nairo` | 23.2 | Moto Camera 3 | ❔ Untested |
| [**moto g play (2021)**](reports/guamna.md) | `guamna` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto g power 2021**](reports/borneo.md) | `borneo` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto g pure**](reports/ellis.md) | `ellis` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto g stylus 5G**](reports/denver.md) | `denver` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto g stylus 5G (2022)**](reports/milanf.md) | `milanf` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**moto g stylus 5G (2023)**](reports/genevn.md) | `genevn` | 24.0 | Moto Camera 4 | 🟢 Works Perfectly |
| [**moto g05**](reports/lamu.md) | `lamu` | 24.0 | Moto Camera 5 | ❔ Untested |
| [**moto g10**](reports/capri.md) | `capri` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto g10 power**](reports/capri.md) | `capri` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto g100**](reports/nio.md) | `nio` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto g15**](reports/lamu.md) | `lamu` | 24.0 | Moto Camera 5 | ❔ Untested |
| [**moto g15 power**](reports/lamu.md) | `lamu` | 24.0 | Moto Camera 5 | ❔ Untested |
| [**moto g200 5G**](reports/xpeng.md) | `xpeng` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto g30**](reports/caprip.md) | `caprip` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto g32**](reports/devon.md) | `devon` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**moto g34 5G**](reports/fogos.md) | `fogos` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**moto g42**](reports/hawao.md) | `hawao` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**moto g45 5G**](reports/fogos.md) | `fogos` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**moto g50**](reports/ibiza.md) | `ibiza` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto g52**](reports/rhode.md) | `rhode` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**moto g6 plus**](reports/evert.md) | `evert` | 22.2 | Moto Camera 2 | ❔ Untested |
| [**moto g7**](reports/river.md) | `river` | 22.2 | Moto Camera 2 | ❔ Untested |
| [**moto g7 play**](reports/channel.md) | `channel` | 22.2 | Moto Camera 2 | ❔ Untested |
| [**moto g7 plus**](reports/lake.md) | `lake` | 22.2 | Moto Camera 2 | ❔ Untested |
| [**moto g7 power**](reports/ocean.md) | `ocean` | 22.2 | Moto Camera 2 | ❔ Untested |
| [**moto g82 5G**](reports/rhodep.md) | `rhodep` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**moto g84 5G**](reports/bangkk.md) | `bangkk` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**moto g9**](reports/guamp.md) | `guamp` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto g9 play**](reports/guamp.md) | `guamp` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto g9 power**](reports/cebu.md) | `cebu` | 24.0 | Moto Camera 3 | ❔ Untested |
| [**moto one 5G**](reports/nairo.md) | `nairo` | 23.2 | Moto Camera 3 | ❔ Untested |
| [**moto one 5G ace**](reports/kiev.md) | `kiev` | 23.2 | Moto Camera 3 | ❔ Untested |
| [**moto S30 Pro**](reports/tundra.md) | `tundra` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**moto x4**](reports/payton.md) | `payton` | 22.2 | Moto Camera 2 | ❔ Untested |
| [**moto X40**](reports/rtwo.md) | `rtwo` | 24.0 | Moto Camera 4 | ❔ Untested |
| [**moto z (2018)**](reports/nash.md) | `nash` | 22.2 | Moto Camera 2 | ❔ Untested |
| [**moto z2 force**](reports/nash.md) | `nash` | 22.2 | Moto Camera 2 | ❔ Untested |
| [**moto z3**](reports/messi.md) | `messi` | 22.2 | Moto Camera 2 | ❔ Untested |
| [**moto z3 play**](reports/beckham.md) | `beckham` | 22.2 | Moto Camera 2 | ❔ Untested |
| [**one action**](reports/troika.md) | `troika` | 24.0 | Moto Camera 2 | ❔ Untested |
| [**one vision**](reports/kane.md) | `kane` | 24.0 | Moto Camera 2 | ❔ Untested |
| [**p50**](reports/kane.md) | `kane` | 24.0 | Moto Camera 2 | ❔ Untested |
| [**ThinkPhone by motorola**](reports/bronco.md) | `bronco` | 24.0 | Moto Camera 4 | ❔ Untested |

---

## 🏛️ Legacy / Discontinued Motorola Devices (36)

These devices previously received official LineageOS builds but are no longer actively maintained upstream. Compatibility depends on community-maintained unofficial ROMs.

<details>
<summary>Click to expand legacy devices list</summary>

| Device Name | Codename | Last Branch | Stock Camera Era | Status |
| :--- | :--- | :--- | :--- | :---: |
| [DROID 4](reports/maserati.md) | `maserati` | 14.1 | Moto Camera 1 | ❔ Untested |
| [DROID BIONIC](reports/targa.md) | `targa` | 14.1 | Moto Camera 1 | ❔ Untested |
| [DROID RAZR (CDMA)](reports/spyder.md) | `spyder` | 14.1 | Moto Camera 1 | ❔ Untested |
| [DROID RAZR (GSM)](reports/umts_spyder.md) | `umts_spyder` | 14.1 | Moto Camera 1 | ❔ Untested |
| [DROID RAZR MAXX (CDMA)](reports/spyder.md) | `spyder` | 14.1 | Moto Camera 1 | ❔ Untested |
| [DROID RAZR MAXX (GSM)](reports/umts_spyder.md) | `umts_spyder` | 14.1 | Moto Camera 1 | ❔ Untested |
| [edge 40 neo](reports/manaus.md) | `manaus` | 23.2 | Moto Camera 4 | ❔ Untested |
| [moto e](reports/condor.md) | `condor` | 14.1 | Moto Camera 1 | ❔ Untested |
| [moto e (2015)](reports/otus.md) | `otus` | 14.1 | Moto Camera 1 | ❔ Untested |
| [moto e LTE (2015)](reports/surnia.md) | `surnia` | 17.1 | Moto Camera 1 | ❔ Untested |
| [moto e5 plus (XT1924-1/2/4/5)](reports/rhannah.md) | `rhannah` | 18.1 | Moto Camera 2 | ❔ Untested |
| [moto e5 plus (XT1924-3/9)](reports/ahannah.md) | `ahannah` | 18.1 | Moto Camera 2 | ❔ Untested |
| [moto e5 plus (XT1924-6/7/8)](reports/hannah.md) | `hannah` | 18.1 | Moto Camera 2 | ❔ Untested |
| [moto g](reports/falcon.md) | `falcon` | 14.1 | Moto Camera 1 | ❔ Untested |
| [moto g (2014)](reports/titan.md) | `titan` | 14.1 | Moto Camera 1 | ❔ Untested |
| [moto g (2015)](reports/osprey.md) | `osprey` | 17.1 | Moto Camera 1 | ❔ Untested |
| [moto g 4G](reports/peregrine.md) | `peregrine` | 14.1 | Moto Camera 1 | ❔ Untested |
| [moto g LTE (2014)](reports/thea.md) | `thea` | 14.1 | Moto Camera 1 | ❔ Untested |
| [moto g3 turbo](reports/merlin.md) | `merlin` | 17.1 | Moto Camera 1 | ❔ Untested |
| [moto g4](reports/athene.md) | `athene` | 14.1 | Moto Camera 2 | ❔ Untested |
| [moto g4 play](reports/harpia.md) | `harpia` | 17.1 | Moto Camera 2 | ❔ Untested |
| [moto g5](reports/cedric.md) | `cedric` | 18.1 | Moto Camera 2 | ❔ Untested |
| [moto g5s](reports/montana.md) | `montana` | 18.1 | Moto Camera 2 | ❔ Untested |
| [moto x](reports/ghost.md) | `ghost` | 13.0 | Moto Camera 1 | ❔ Untested |
| [moto x (2014)](reports/victara.md) | `victara` | 18.1 | Moto Camera 1 | ❔ Untested |
| [moto x play](reports/lux.md) | `lux` | 17.1 | Moto Camera 1 | ❔ Untested |
| [moto x pure edition (2015)](reports/clark.md) | `clark` | 14.1 | Moto Camera 1 | ❔ Untested |
| [moto x style (2015)](reports/clark.md) | `clark` | 14.1 | Moto Camera 1 | ❔ Untested |
| [moto z](reports/griffin.md) | `griffin` | 18.1 | Moto Camera 2 | ❔ Untested |
| [moto z play](reports/addison.md) | `addison` | 18.1 | Moto Camera 2 | ❔ Untested |
| [moto z2 play](reports/albus.md) | `albus` | 18.1 | Moto Camera 2 | ❔ Untested |
| [one fusion+](reports/liber.md) | `liber` | 20 | Moto Camera 3 | ❔ Untested |
| [one fusion+ (India)](reports/liber.md) | `liber` | 20 | Moto Camera 3 | ❔ Untested |
| [one power](reports/chef.md) | `chef` | 19.1 | Moto Camera 2 | ❔ Untested |
| [one zoom](reports/parker.md) | `parker` | 20 | Moto Camera 2 | ❔ Untested |
| [PHOTON Q 4G LTE](reports/xt897.md) | `xt897` | 14.1 | Moto Camera 1 | ❔ Untested |

</details>
