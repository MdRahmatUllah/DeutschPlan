# Launch image

Generated — do not edit by hand. These six PNGs are `SplashLockup` rendered by
`app/test/golden/ios_launch_image_golden_test.dart`, so the launch screen shows
the mark Flutter's first frame draws. After changing the mark:

```
make update-goldens
```

The field behind it is `SplashField.colorset`, whose values
`test/features/splash_native_test.dart` checks against `DpPalette`.

Written without a Mac (#238): not yet seen on an iPhone or a simulator.
