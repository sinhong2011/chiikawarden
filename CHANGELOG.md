# Changelog

## 1.0.0 (2026-10-06)


### ⚠ BREAKING CHANGES

* Chiikawarden is now licensed under the GNU General Public License v3.0 (previously MIT). Earlier commits remain available under MIT.

### Features

* Archive, like Bitwarden's official clients ([ac34b34](https://github.com/sinhong2011/chiikawarden/commit/ac34b340f8b0900aec28e5459b301913b6c8eb65))
* bank-vault door lock screen with a real opening sequence ([adf2f1e](https://github.com/sinhong2011/chiikawarden/commit/adf2f1ea0e9303f9364df55d226a1038fa1069ab))
* countdown rings and breathing codes, website and edit time in details, trailing switches ([121c45d](https://github.com/sinhong2011/chiikawarden/commit/121c45dad2f355b9fc18aee9e520af396f41e260))
* custom environment URLs in a sheet ([d5d54fc](https://github.com/sinhong2011/chiikawarden/commit/d5d54fca28c339cbee27109ab5c255196366f8b8))
* **import:** 1Password, LastPass, KeePass, Proton Pass and Dashlane ([ca51221](https://github.com/sinhong2011/chiikawarden/commit/ca512217e7a3c2b6eca86f4082a6a0cda4d3c885))
* **import:** organization vaults, export from Settings, batched imports ([fc515ab](https://github.com/sinhong2011/chiikawarden/commit/fc515abff27d541f85121e3e4454ea72281fdcd1))
* in-app updates with Sparkle and automated releases with release-please ([042134d](https://github.com/sinhong2011/chiikawarden/commit/042134d667ace2b36ee06902650b01e46efc2ab4))
* locking closes the gate over the vault, then the door assembles ([5e85431](https://github.com/sinhong2011/chiikawarden/commit/5e854315e4e9658193c87aee21b22ceddb4417bf))
* merge main into the transforming vault door; it parts like a gate ([4be6e51](https://github.com/sinhong2011/chiikawarden/commit/4be6e51e5356e91966f4c0f8d13d83f18378a3c4))
* New Send lives in the header's + menu ([f09dc0b](https://github.com/sinhong2011/chiikawarden/commit/f09dc0b1ae5f3db9d9edd40db8264f181a2beff2))
* relicense under GPL-3.0, third-party notices, new README ([d1128e0](https://github.com/sinhong2011/chiikawarden/commit/d1128e0d5c246dd6b6cc9943d6a280b33c80684e))
* Send composed in place, with soft fields and cards ([a4bafe6](https://github.com/sinhong2011/chiikawarden/commit/a4bafe604f4cb46aa604169d368802210580ba83))
* sort menu with A–Z sections, list-wide search, slim scroller, calmer colours ([fd27fe1](https://github.com/sinhong2011/chiikawarden/commit/fd27fe1163c759f02f65f9e2e5214e5adf74dd50))
* the command palette's code uses the breathing dot and countdown ring ([0c1153c](https://github.com/sinhong2011/chiikawarden/commit/0c1153ce5edecfd4b0c35c96d73ee3a106712707))
* the lock screen opens like a vault's inner gate ([a276767](https://github.com/sinhong2011/chiikawarden/commit/a276767f4961c87d0c3e977c4330a4d6dc932306))
* transforming vault door lock screen that parts like a gate ([#19](https://github.com/sinhong2011/chiikawarden/issues/19)) ([b4a501f](https://github.com/sinhong2011/chiikawarden/commit/b4a501ff96ea788f5ba127c95c9254193b5a6ed3))
* vault door lock screen that transforms open, as a layer over the vault ([b4a501f](https://github.com/sinhong2011/chiikawarden/commit/b4a501ff96ea788f5ba127c95c9254193b5a6ed3))
* vault door lock screen that transforms open, as a layer over the vault ([2c4e898](https://github.com/sinhong2011/chiikawarden/commit/2c4e89833267424663762e8d9f82fe19b50762b4))
* vault door on the login screen too; menu bar codes and Increase Contrast ([bafedf8](https://github.com/sinhong2011/chiikawarden/commit/bafedf8f54fad49cd55e3f53b9831c65de34e0b9))


### Fixes

* bring back the door coming apart before the gate opens ([27e8f42](https://github.com/sinhong2011/chiikawarden/commit/27e8f4243a7119745da1aafac7010f3fd98a5a7d))
* capsule switchers always slide (the generator's mode tabs jumped) ([48a14b3](https://github.com/sinhong2011/chiikawarden/commit/48a14b31ac4c56d51d2619b6b8910e8510b26b04))
* identity icon disappeared on highlighted menu rows ([0f8550b](https://github.com/sinhong2011/chiikawarden/commit/0f8550be4c336ff2f7a740e3ae7dc416c7bc0314))
* no spreading rings when the door opens; letter avatars match icon tiles ([705d19f](https://github.com/sinhong2011/chiikawarden/commit/705d19f4105cd8d104dfa0404623e4742534859a))
* the palette's code and ring centre on the whole highlighted row ([003e955](https://github.com/sinhong2011/chiikawarden/commit/003e9557292bd4556fc632ebfd98f75ffd001353))


### Performance

* the gate moves still images of the door, not two live doors ([1411692](https://github.com/sinhong2011/chiikawarden/commit/14116920c4381c7668966ca804facdada8ed3c6a))
* the lock gate is its own lightweight layer, so locking and unlocking stay smooth ([13ce306](https://github.com/sinhong2011/chiikawarden/commit/13ce3062bde9eff7172fae1bd2e6fd317e89bb3d))
