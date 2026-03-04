# TrollTitan

**Runtime** dylib injection with CoreTrust bypass and ROP (opainject).  
Fork of [TrollFools](https://github.com/82flex/TrollFools) that **replaces** in-place Mach-O editing with injecting into the **running** process.

- **Target app must be running** when you tap Inject.
- Uses [opainject](https://github.com/iolate/opainject)-style ROP injection and the same CoreTrust bypass (e.g. `ct_bypass`) for signing the dylib.
- Expected to work on iOS versions supported by TrollStore (iOS 14.0 – 17.x) with appropriate entitlements.

## Build

- Open `TrollFools.xcodeproj` in Xcode and build for your device/simulator.
- Requires **CoreSymbolication** (private framework) linked for the RuntimeInject/opainject code.

## Credits

- [TrollFools](https://github.com/82flex/TrollFools) by [@82Flex](https://github.com/82Flex) – original app and UI.
- [Titanium](https://github.com/andrdevv/Titanium) – CoreTrust bypass + opainject flow.
- [opainject](https://github.com/iolate/opainject) – ROP-based dylib injection.

## License

See [LICENSE](LICENSE).
