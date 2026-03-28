# MeloNX Air5 Edition

<p align="center">
  <strong>Emulator Nintendo Switch khusus iPad Air 5</strong><br/>
  A Nintendo Switch emulator optimized exclusively for the iPad Air 5 (M1 chip)
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-iPadOS%2016%2B-blue"/>
  <img alt="Device" src="https://img.shields.io/badge/device-iPad%20Air%205-orange"/>
  <img alt="Language" src="https://img.shields.io/badge/language-Swift%205.9-red"/>
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green"/>
</p>

---

## Tentang / About

**MeloNX Air5 Edition** adalah fork dari MeloNX yang dirancang dan dioptimalkan khusus untuk **iPad Air 5 (generasi ke-5)** yang menggunakan chip **Apple M1**. Versi ini memanfaatkan sepenuhnya keunggulan arsitektur M1 pada iPad Air 5 untuk memberikan performa emulasi Nintendo Switch terbaik.

MeloNX Air5 Edition is a fork of MeloNX designed and optimized exclusively for the **5th generation iPad Air** powered by the **Apple M1 chip**. This edition fully leverages the M1 architecture to deliver the best possible Nintendo Switch emulation experience on the device.

---

## Fitur / Features

- 🎮 **Emulasi Nintendo Switch penuh** – Emulate Nintendo Switch titles on iPadOS
- ⚡ **Dioptimalkan untuk Apple M1** – CPU and GPU optimizations targeting the M1's performance and efficiency cores
- 🖥️ **Layar 10.9" 2360×1640** – Native rendering at iPad Air 5's native resolution (264 ppi)
- 🎨 **Metal GPU Backend** – Full Metal API integration for hardware-accelerated graphics
- 🔊 **AVAudioEngine Audio** – Low-latency audio via AVFoundation/AVAudioEngine
- 🕹️ **On-screen Controller** – iPad-optimized on-screen gamepad layout
- 🎮 **MFi & Xbox/PS Controller Support** – Physical controller support via GameController framework
- 💾 **Save States** – Quick save and load game states
- 📂 **ROM Management** – Built-in ROM library browser
- 🔋 **Adaptive Performance** – Dynamic performance scaling to balance FPS and battery life

---

## Persyaratan / Requirements

| Komponen | Spesifikasi |
|---|---|
| Perangkat | **iPad Air (5th generation)** |
| Chip | Apple M1 |
| RAM | 8 GB |
| OS | iPadOS 16.0 atau lebih baru |
| Penyimpanan | Min. 4 GB ruang bebas |

> ⚠️ Aplikasi ini **hanya** dirancang untuk iPad Air 5. Versi iPad lain tidak didukung secara resmi.

---

## Instalasi / Installation

### Via AltStore / Sideloadly
1. Unduh file `.ipa` dari [Releases](https://github.com/Runiajahnih900/MeloNX-Air5-Edition/releases)
2. Install menggunakan AltStore atau Sideloadly
3. Trust the developer certificate di **Settings → General → VPN & Device Management**

### Build dari Source
1. Clone repositori ini
2. Buka `MeloNX.xcodeproj` di Xcode 15+
3. Set your development team di project settings
4. Build dan run ke iPad Air 5

```bash
git clone https://github.com/Runiajahnih900/MeloNX-Air5-Edition.git
cd MeloNX-Air5-Edition
open MeloNX.xcodeproj
```

---

## Struktur Proyek / Project Structure

```
MeloNX-Air5-Edition/
├── Sources/MeloNX/
│   ├── Core/
│   │   ├── CPU/          # ARM64/AArch64 CPU emulation core
│   │   ├── GPU/          # GPU emulation (NVN/Maxwell)
│   │   ├── Memory/       # Memory management & MMU
│   │   └── Audio/        # Audio emulation & mixing
│   ├── Platform/
│   │   ├── iPadAir5/     # iPad Air 5 (M1) specific optimizations
│   │   └── Metal/        # Metal GPU backend
│   ├── UI/
│   │   ├── Views/        # SwiftUI views
│   │   ├── ViewModels/   # MVVM view models
│   │   └── Components/   # Reusable UI components
│   ├── Utilities/        # Helpers, extensions, constants
│   └── Resources/        # Assets, shaders, localizations
├── Tests/MeloNXTests/    # Unit tests
└── MeloNX.xcodeproj/     # Xcode project
```

---

## Arsitektur / Architecture

```
┌─────────────────────────────────────────────────┐
│                   SwiftUI Layer                  │
│          (iPad Air 5 Optimized UI/UX)            │
└────────────────────┬────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────┐
│              Emulator Core (Swift/C++)           │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  CPU     │  │  Memory  │  │  Audio Engine │  │
│  │ ARM64    │  │  MMU/TLB │  │  AVAudioEngine│  │
│  └──────────┘  └──────────┘  └───────────────┘  │
│  ┌──────────────────────────────────────────┐    │
│  │       GPU (NVN → Metal Translation)      │    │
│  │    Optimized for Apple M1 GPU Cores      │    │
│  └──────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────┐
│           iPad Air 5 Hardware (M1)               │
│    8× CPU Cores  │  7-core GPU  │  8GB LPDDR4X   │
└─────────────────────────────────────────────────┘
```

---

## Pengembangan / Development

Kontribusi sangat disambut! Silakan buka issue atau pull request. / Contributions are welcome! Please open an issue or pull request.

### Panduan Kontribusi
1. Fork repositori
2. Buat branch fitur (`git checkout -b feature/nama-fitur`)
3. Commit perubahan (`git commit -m 'Add: nama fitur'`)
4. Push ke branch (`git push origin feature/nama-fitur`)
5. Buka Pull Request

---

## Lisensi / License

Proyek ini dilisensikan di bawah [MIT License](LICENSE).

---

## Penafian / Disclaimer

MeloNX Air5 Edition adalah proyek open-source yang dibuat untuk tujuan penelitian dan edukasi. Pengguna bertanggung jawab penuh untuk memastikan penggunaan perangkat lunak ini sesuai dengan hukum yang berlaku di wilayah mereka. Harap dump game dari konsol Nintendo Switch yang Anda miliki secara legal sebelum menggunakan emulator ini.

MeloNX Air5 Edition is an open-source project created for research and educational purposes. Users are solely responsible for ensuring their use of this software complies with applicable laws in their region. Please legally dump games from your own Nintendo Switch console before using this emulator.

---

<p align="center">Made with ❤️ for iPad Air 5</p>