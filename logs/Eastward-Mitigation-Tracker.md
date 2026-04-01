# Eastward iOS Mitigation Tracker

Last update: 2026-04-01 (after latest log 18:10, v8 profile applied, iPad lifecycle termination still occurs)
Title ID: 010071b00f63a000

## Status Fase Baru (PC-first Baseline)
- Baseline terbaru: scene Eastward yang sebelumnya stuck kini bisa lewat saat diuji di Windows (simulasi PC) pada source terbaru.
- Implikasi: daftar mitigasi lama di bawah ini dianggap sudah dieksplorasi menyeluruh dan **tidak diulang** kecuali ada perubahan code path yang relevan.
- Fokus investigasi berpindah ke gap platform iOS (lifecycle, Vulkan/MoltenVK runtime path, resource pressure), bukan lagi tuning umum yang sudah terbukti gagal.
- Aturan eksperimen baru: setiap perubahan harus lolos regresi scene di PC dulu, baru lanjut validasi di iPad.

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
- [ACTIVE-PENDING] Eastward iOS post-fix profile (v8):
  - Hentikan override lama yang dipaksa terus: `--disable-shader-cache`, `--backend-threading Off`, `--force-dummy-audio`.
  - Pakai baseline runtime default (shader cache aktif, backend-threading default/Auto, audio default) agar tidak menambah stall baru di iOS setelah jalur syncpoint membaik.
- [ACTIVE-PENDING] Eastward iOS post-fix profile (v9):
  - Hentikan force `MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0` khusus Eastward.
  - Kembalikan ke default capability-based (`tier2 => ON`) agar jalur MoltenVK tidak dibatasi mitigasi lama yang sudah tidak efektif.

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

## Hasil Log Terbaru (17:49)
- Marker `MELONX_IOS_EVENTWAIT_V6` tetap muncul dan promosi syncpoint berjalan:
  - `syncpt=2, target=3, before=1, after=3, promotedBy=2`
  - `syncpt=1, target=3, before=1, after=3, promotedBy=2`
- `ServiceNv Wait: GPU processing thread is too slow...` tidak terlihat pada sesi ini.
- Jalur boot game sudah lewat tahap penting:
  - `Loader Start: Application Loaded: Eastward ...`
  - Vulkan device/swapchain berhasil dibuat di MoltenVK.
- Namun app tetap berakhir lifecycle iOS:
  - `App will resign active`
  - `App entered background`
  - `UIApplication.willTerminate received`
- Interpretasi: gap utama saat ini bukan lagi wait syncpoint kecil, melainkan freeze/termination pada jalur runtime iOS setelah game mulai jalan.

## Hasil Log Terbaru (18:10)
- Verifikasi v8 berhasil:
  - Arg lama sudah hilang dari launch argv: `--disable-shader-cache`, `--backend-threading Off`, `--force-dummy-audio`.
  - Backend threading kembali `On`.
  - Shader cache kembali aktif (`Loading 0 shaders from the cache... Shader cache loaded.`).
- Marker `MELONX_IOS_EVENTWAIT_V6` tetap muncul dan promosi syncpoint berjalan.
- `ServiceNv Wait: GPU processing thread is too slow...` tetap tidak terlihat.
- Namun app masih berakhir lifecycle iOS (`will resign active` -> `entered background` -> `willTerminate`).
- Interpretasi: v8 memperbaiki profil runtime, tetapi belum menyelesaikan termination; lanjut v9 (argument buffers tidak dipaksa OFF).

## Gejala Konsisten di Log
- Pola lama (sebelum v6 dominan):
  - `ServiceNv Wait: GPU processing thread is too slow, waiting on CPU...`
- Pola terbaru (setelah v6 aktif):
  - Marker `ServiceNv Wait` bisa tidak muncul sama sekali.
  - App tetap masuk lifecycle: `App will resign active` -> `App entered background` -> `UIApplication.willTerminate received`.

## Kesimpulan Sementara
Lockdown lama (audio dummy + threading off + shader cache off + low GPU load) tidak menyelesaikan kasus, dan kini berpotensi menjadi sumber stall baru pada iOS setelah jalur syncpoint membaik. Dugaan utama tetap di jalur runtime iOS/Vulkan lifecycle setelah game start, bukan masalah setting umum.

## Langkah Berikutnya
1. Build dengan patch v9 (argument buffers capability-based) + patch v6/v7/v8 tetap aktif.
2. Verifikasi marker log:
  - `MELONX_IOS_EVENTWAIT_V6: promoted syncpoint in EventWait fallback. ...`
  - Tidak ada lagi forced args lama di launch argv:
    - `--disable-shader-cache`
    - `--backend-threading Off`
    - `--force-dummy-audio`
  - Tidak ada lagi log `Eastward compatibility: forcing MVK argument buffers OFF ...`.
  - `Env setup ... usingArgumentBuffers=true` pada iPad Air 5 (tier2).
  - `Background graphics compilation failed on MoltenVK, deferring to runtime pipeline creation: ...` (jika terjadi)
3. Jika masih stuck/background tanpa marker `ServiceNv Wait`, lanjutkan forensics ke jalur lifecycle iOS + runtime Vulkan scene (frame progression dan state transition setelah `Application Loaded`).
