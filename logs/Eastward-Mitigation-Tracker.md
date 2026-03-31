# Eastward iOS Mitigation Tracker

Last update: 2026-03-31 (after latest log 07:08)
Title ID: 010071b00f63a000

## Tujuan
Mencatat semua mitigasi yang sudah/pernah dicoba di source workspace ini agar tidak mengulang percobaan yang sama dan supaya status uji jelas sebelum build berikutnya.

## Mitigasi Sudah Diterapkan dan Diuji
- [DONE] Force memory manager ke `HostMapped`.
- [DONE] Disable `Expand Guest RAM`.
- [DONE] Disable `PTC`.
- [DONE] Disable `Ignore Missing Services`.
- [DONE] Enable `Macro HLE`.
- [DONE] Enable `Docked Mode`.
- [DONE] Disable guest/stub logs secara default pada mode stabil.
- [DONE] Eastward scene forensics dijadikan mode opt-in.
- [DONE] ServiceLm guest-log flow control di iOS (drop empty, burst dedupe, rate-limit summary).
- [DONE] Skip ExeFS/NSO/RomFS/Cheat injection khusus Eastward iOS.
- [DONE] Force dummy audio (`--force-dummy-audio`).
  - Hasil: masih stuck/background.
- [DONE] Force backend-threading Off (`--backend-threading Off`) + fix engine agar opsi threading benar-benar dihormati.
  - Hasil: masih stuck/background.
- [DONE] Force disable shader cache (`config.enableShaderCache=false` / `--disable-shader-cache`).
  - Hasil: masih stuck/background.
- [DONE] Force non-dualmapped JIT (`DUAL_MAPPED_JIT=0` khusus Eastward).
  - Hasil: masih stuck/background.

## Mitigasi Aktif di Source (Belum Ada Bukti Log Final)
- [ACTIVE-PENDING] Force MoltenVK Metal Argument Buffers OFF khusus Eastward (`MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0`).
  - Alasan: log masih menunjukkan pola `ServiceNv Wait` setelah seluruh mitigasi sebelumnya; jalur argument-buffer Metal3 belum diisolasi.

## Gejala Konsisten di Log
- Freeze lalu muncul warning:
  - `ServiceNv Wait: GPU processing thread is too slow, waiting on CPU...`
- Setelah itu app masuk lifecycle:
  - `App will resign active`
  - `App entered background`
  - kadang diikuti `Audio session interruption began` (kemungkinan efek lanjutan, bukan akar awal).

## Kesimpulan Sementara
Dengan audio dummy + threading off + shader cache off + non-dualmapped JIT tetap reproduksi, dugaan kuat mengarah ke jalur engine/runtime GPU Vulkan Eastward pada iOS 16.1, bukan sekadar setting game biasa.

## Langkah Berikutnya
1. Build dengan patch force argument buffers OFF yang sudah ada di source.
2. Verifikasi marker log:
  - `Eastward compatibility: forcing MVK argument buffers OFF for Vulkan stability isolation`
  - `Env setup: ... usingArgumentBuffers=false`
3. Jika masih muncul pola `ServiceNv Wait` + background, tandai issue sebagai engine-level regression/pathology untuk Eastward di iOS.
