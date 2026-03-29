- iOS gameplay stability can degrade with Trace Logs enabled; Eastward session showed extreme |T| spam and force-closes.
- Prefer disabling trace/debug logs by default on iOS devices; allow explicit override only.
- Keep LogCapture in-memory buffer bounded and avoid expensive per-line regex creation in hot path.
- Main app log files should be rotated/pruned to prevent multi-hundred-MB growth.
- For force-close diagnosis, add abnormal-session markers (previous active session path persisted in UserDefaults and flagged on next launch), lifecycle diagnostics, argv/config summary, and bounded session-log rotation.
- On iOS, forcing Eastward to SoftwarePageTable caused heavy JIT cache allocation spam (hex lines like `00004000: 00004000 00004000`) and earlier force-close; prefer HostMapped profile for this title while keeping verbose logs disabled.
- Eastward on iOS can still hit `EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE` in scene transitions; forcing DualMapped JIT for this title (with fallback to non-dualmapped if init fails) improves safety against W^X permission faults.
- High-frequency logs in Swift bridge (`setGamepadButtonState`) and UIVisualEffect hook should stay disabled; they can explode app logs during gameplay and worsen runtime stability.
- Latest Eastward crash signature after dual-mapped rollout: `Ryujinx.Memory.InvalidMemoryRegionException` in `HostTracked.NativePageTable.VirtualMemoryEvent`; avoid HostTracked path for this title by forcing `SoftwarePageTable` and `disablePTC=true`.


