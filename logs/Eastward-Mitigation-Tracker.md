# Eastward iOS Mitigation Tracker

Last update: 2026-04-01 (after latest log 06:55, NV wait patch v4)
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
- [DONE] Force MoltenVK Metal Argument Buffers OFF (`MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0`).
  - Hasil: masih stuck/background.
- [DONE] Force OpenGL backend (`--graphics-backend OpenGl`) untuk isolasi Vulkan.
  - Hasil: tidak valid di iOS, otomatis fallback ke Vulkan (`OpenGL is not supported on Apple platforms, switching to Vulkan!`).
- [DONE] Force low GPU load (handheld mode + `resolution-scale 0.5`).
  - Hasil: masih stuck/background dengan pola sama.

## Mitigasi Aktif di Source (Belum Ada Bukti Log Final)
- [ACTIVE-PENDING] iOS NV wait patch v4: bounded CPU wait + skip wait untuk delta syncpoint kecil + loop-break heuristic saat stallCount berulang pada fence/syncpoint yang sama.
  - Alasan: pola stuck selalu berakhir di `GPU processing thread is too slow, waiting on CPU...`; wait tak terbatas kemungkinan memicu app unresponsive lalu background.

## Hasil Log Terakhir (Sebelum V4)
- Marker `MELONX_IOS_NV_WAIT_V3` sudah muncul (build terbaru terpakai).
- Kasus yang tertangkap: `syncpt=1, target=9565, current=9563, remaining=2` berulang.
- V3 sukses menghindari CPU wait, tapi loop `TryAgain` masih berulang lalu app tetap background/terminate.

## Gejala Konsisten di Log
- Freeze lalu muncul warning:
  - `ServiceNv Wait: GPU processing thread is too slow, waiting on CPU...`
- Setelah itu app masuk lifecycle:
  - `App will resign active`
  - `App entered background`
  - kadang diikuti `Audio session interruption began` (kemungkinan efek lanjutan, bukan akar awal).

## Kesimpulan Sementara
Dengan audio dummy + threading off + shader cache off + non-dualmapped JIT + argument buffers OFF + low GPU load tetap reproduksi, dugaan sangat kuat mengarah ke jalur engine/runtime GPU Vulkan Eastward pada iOS 16.1, bukan sekadar setting game biasa. Uji OpenGL juga tidak bisa dijadikan pembanding karena iOS otomatis fallback ke Vulkan.

## Langkah Berikutnya
1. Build dengan patch iOS bounded CPU wait di `NvHostEvent` yang sudah ada di source.
2. Verifikasi marker log:
  - `MELONX_IOS_NV_WAIT_V4: GPU processing thread is too slow, waiting on CPU... syncpt=..., target=..., current=..., remaining=..., failingCount=..., isIos=true`
  - `MELONX_IOS_NV_WAIT_V4: skipping CPU wait on iOS for small syncpoint delta ..., stallCount=..., returning TryAgain.`
  - `MELONX_IOS_NV_WAIT_V4: small-delta stall persisted for fence, forcing Success to break TryAgain loop...`
  - `MELONX_IOS_NV_WAIT_V4: bounded CPU wait timed out after 16ms, continuing with TryAgain...`
3. Jika masih muncul pola `ServiceNv Wait` + background, tandai issue sebagai engine-level regression/pathology untuk Eastward di iOS.
