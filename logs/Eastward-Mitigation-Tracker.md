# Eastward iOS Mitigation Tracker

Last update: 2026-04-01 (after latest log 15:59, EventWait v6 confirmed, early lifecycle termination persists)
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
- [ACTIVE-PENDING] iOS patch v6: pertahankan NV wait v5 + fallback promosi syncpoint di level `EventWait` (NvHostCtrlDeviceFile) untuk delta kecil agar jalur tidak bergantung hanya pada `NvHostEvent`.
  - Alasan: pola stuck selalu berakhir di `GPU processing thread is too slow, waiting on CPU...`; wait tak terbatas kemungkinan memicu app unresponsive lalu background.
- [ACTIVE-PENDING] Vulkan MoltenVK retry path (v7):
  - Jangan negative-cache graphics pipeline failure sebagai `null` pada MoltenVK.
  - Jangan set `ProgramLinkStatus.Failure` jika background *graphics* pipeline compilation gagal di MoltenVK (defer ke runtime on-demand compile).
  - Alasan: kegagalan pipeline di iOS/MoltenVK bisa transient; cache `null`/forced link failure membuat draw terblok permanen pada state yang sebenarnya bisa recover.

## Hasil Log Terakhir (Sebelum V4)
- Marker `MELONX_IOS_NV_WAIT_V3` sudah muncul (build terbaru terpakai).
- Kasus yang tertangkap: `syncpt=1, target=9565, current=9563, remaining=2` berulang.
- V3 sukses menghindari CPU wait, tapi loop `TryAgain` masih berulang lalu app tetap background/terminate.

## Hasil Log Terakhir (Sebelum V5)
- Marker `MELONX_IOS_NV_WAIT_V4` muncul penuh, termasuk `stallCount=2` dan `forcing Success to break TryAgain loop`.
- Artinya loop-break saja belum cukup; setelah forced-success app tetap resign/background.
- Indikasi kuat ada state syncpoint yang masih tertinggal walau result sudah dipaksa success.

## Hasil Log Terakhir (Sebelum V6)
- Marker `MELONX_IOS_NV_WAIT_V5` muncul lengkap, termasuk promosi syncpoint sukses:
  - `previousCurrent=10286`
  - `promotedCurrent=10288`
  - `promotedBy=2`
- Artinya gap syncpoint di level `NvHostEvent` memang tertutup, tetapi app tetap langsung resign/background sesudahnya.
- Mitigasi v6 menambahkan fallback lebih awal di `EventWait` untuk kasus delta kecil yang sama.

## Hasil Log Terbaru (Setelah V6, sebelum V7)
- Marker `MELONX_IOS_EVENTWAIT_V6` muncul dan promosi syncpoint terjadi sangat awal:
  - `syncpt=2, target=3, before=1, after=3, promotedBy=2`
  - `syncpt=1, target=3, before=1, after=3, promotedBy=2`
- Pada log terbaru ini tidak terlihat lagi marker `MELONX_IOS_NV_WAIT_V5: GPU processing thread is too slow...`.
- Artinya fallback v6 aktif dan menutup kasus small-delta wait paling awal.
- Namun sesi masih berakhir dengan lifecycle background/terminate, jadi akar masalah kemungkinan bergeser ke jalur runtime GPU/pipeline scene tertentu (bukan semata wait-loop syncpoint kecil).

## Hasil Log Terbaru (15:59)
- Marker `MELONX_IOS_EVENTWAIT_V6` muncul lebih awal dan pada beberapa syncpoint:
  - `syncpt=2, target=3, before=1, after=3, promotedBy=2`
  - `syncpt=1, target=3, before=1, after=3, promotedBy=2`
- Marker `MELONX_IOS_NV_WAIT_V5` tidak muncul pada sesi ini.
- App tetap cepat masuk lifecycle:
  - `App will resign active`
  - `App entered background`
  - `UIApplication.willTerminate received`
- Interpretasi: jalur small-delta syncpoint wait sudah bukan blocker utama pada sesi ini; failure bergerak ke jalur runtime/lifecycle lain.

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
1. Build dengan patch v7 (MoltenVK pipeline retry) + patch v6 tetap aktif.
2. Verifikasi marker log:
  - `MELONX_IOS_EVENTWAIT_V6: promoted syncpoint in EventWait fallback. ...`
  - `MELONX_IOS_NV_WAIT_V5: GPU processing thread is too slow, waiting on CPU... syncpt=..., target=..., current=..., remaining=..., failingCount=..., isIos=true`
  - `MELONX_IOS_NV_WAIT_V5: skipping CPU wait on iOS for small syncpoint delta ..., stallCount=..., returning TryAgain.`
  - `MELONX_IOS_NV_WAIT_V5: small-delta stall persisted for fence, forcing Success to break TryAgain loop...`
  - `MELONX_IOS_NV_WAIT_V5: promoted syncpoint after forced success. ... promotedBy=...`
  - `MELONX_IOS_NV_WAIT_V5: bounded CPU wait timed out after 16ms, continuing with TryAgain...`
  - `Background graphics compilation failed on MoltenVK, deferring to runtime pipeline creation: ...` (jika terjadi)
3. Jika masih stuck/background tanpa marker `ServiceNv Wait`, lanjutkan forensics ke jalur Vulkan scene runtime (pipeline churn / compile error burst per draw).
