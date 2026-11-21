# pico-fido2 — flash & secure boot

Steps to flash pico-fido2 onto a Raspberry Pi Pico 2 (RP2350) and lock it to
your signing keys.

> **OTP bits only go from 0 to 1.** Stages 1–4 can't be undone. Run one command
> at a time and stop at the first result that doesn't match.

## Tokens: 3

All three boards get the same firmware and the same two signing keys. What
differs is the order and how carefully each one is done:

| Token | Role | How |
| --- | --- | --- |
| 1 | First board, daily use | Stages 1–4 **one at a time**, with a check after each. If anything is wrong, you lose one €6 board, not all of them. |
| 2 | Backup | Only after token 1 works: `otp-all.json` + stage 4. The files are already proven. |
| 3 | Spare / second backup | Same as token 2. |

Register **every** token everywhere you use one (SSH, websites, gopass), so
losing any single token locks you out of nothing.

## Files

| File | Purpose |
| --- | --- |
| `picotool/picotool` | The pinned picotool used to build and sign everything. Use this one, not another install. |
| `pico_fido2.uf2` | Unsigned firmware. For testing before anything is burned. |
| `pico_fido2.key0.signed.uf2` | Firmware signed with key0. The one you keep installed. |
| `pico_fido2.key1.signed.uf2` | Firmware signed with key1. Used once to prove slot 1 works. |
| `key0.pem.vault`, `key1.pem.vault` | Private signing keys, encrypted with ansible-vault. **Back these up.** Losing both means the board can never run new firmware. |
| `key0.pub.pem`, `key1.pub.pem` | Public keys. Not secret. |
| `seal-key0.json`, `seal-key1.json` | Raw output of `picotool seal`. Each holds the hash of its key. |
| `otp-stage-1-add-keys.json` | Writes the key0 + key1 hashes into slots 0 and 1 and marks them valid. |
| `otp-stage-2-enable-secure-boot.json` | Turns on secure boot. From then on, only signed images boot. |
| `otp-stage-3-invalidate-slots.json` | Permanently disables slots 2 and 3, so nobody can add their own key. |
| `otp-stage-4-lock-pages.json` | Makes the boot settings and key hashes read-only. For `otp permissions`, not `otp load`. |
| `otp-all.json` | Stages 1–3 in one file, for the second token. |

## The private keys

`key0.pem.vault` and `key1.pem.vault` are encrypted with your ansible-vault
password. `picotool` can't read encrypted keys, so stage 4 (and signing future
updates) needs a decrypted copy:

```bash
ansible-vault decrypt key0.pem.vault --output key0.pem
# ... use key0.pem ...
rm key0.pem
```

Delete the decrypted file as soon as you're done.

## BOOTSEL mode

Every step starts in BOOTSEL mode: hold the **BOOTSEL** button, plug the Pico
in, release. A drive called `RP2350` appears, and `picotool` can talk to the
board.

Make sure **only one** Pico is connected:

```bash
./picotool/picotool info -a
```

---

## Step 0 — test the firmware (nothing burned)

1. BOOTSEL mode, then copy the unsigned firmware:

   ```bash
   cp pico_fido2.uf2 /Volumes/RP2350/
   ```

   The Pico reboots into pico-fido2 and the drive disappears.

2. Check it from the usage side:

   ```bash
   fido2-token -L                                  # the Pico is listed
   ssh-keygen -t ed25519-sk -f /tmp/pico-test      # asks for PIN, LED blinks, press BOOTSEL button
   ```

3. Repeat with the signed image. Secure boot is still off, so it must behave
   exactly the same:

   ```bash
   cp pico_fido2.key0.signed.uf2 /Volumes/RP2350/
   ```

   If drag-and-drop misbehaves, use
   `./picotool/picotool load -x pico_fido2.key0.signed.uf2`.

**Stop if** either image doesn't work. Fix the build before going further.

---

## Token 1 — stages 1 to 4

### Stage 1: key hashes

**What it does:** writes the SHA-256 hash of each public key into the chip's
OTP: key0 into slot 0, key1 into slot 1. It also sets `KEY_VALID` for both
slots, which tells the bootrom "these slots are in use". Two keys means losing
one of them doesn't lock you out of updates.

**Effect:** none yet. The chip only *stores* the hashes. Until stage 2, it still
boots any image, signed or not. That's why you check the hashes now: if one is
wrong, the board still works, and nothing is enforced against a bad value.

**Permanent:** yes. A written slot can never be changed again.

```bash
./picotool/picotool otp load otp-stage-1-add-keys.json
./picotool/picotool otp get bootkey0 bootkey1 boot_flags1
```

Compare `bootkey0` and `bootkey1` with the hashes from the seal files:

```bash
python3 -c 'import json;[print(f"key{i}:",bytes(json.load(open(f"seal-key{i}.json"))["bootkey0"]).hex()) for i in (0,1)]'
```

Each OTP row holds 2 bytes of the hash. `BOOT_FLAGS1.KEY_VALID` must be `3`
(slots 0 and 1).

**Stop if** anything differs. Don't go on to stage 2.

### Stage 2: enable secure boot

**What it does:** sets `SECURE_BOOT_ENABLE` in `CRIT1`.

**Effect:** from the next boot on, the bootrom checks every image before running
it: the public key inside the image must match a hash in a valid slot, and the
signature must be correct. Anything else doesn't boot. BOOTSEL mode still works,
so you can always copy a new (signed) image over.

This is what keeps the master key safe: pico-fido2 stores it in OTP, readable
only by code running in Secure mode, and only your signed firmware can run there
now. Without secure boot, anyone could flash a program that reads the master key
out.

**Permanent:** yes. Secure boot can never be turned off again.

```bash
./picotool/picotool otp load otp-stage-2-enable-secure-boot.json
./picotool/picotool otp get crit1                # SECURE_BOOT_ENABLE = 1
```

Prove it works. BOOTSEL mode before each copy:

| Copy | Expected |
| --- | --- |
| `pico_fido2.key1.signed.uf2` | Boots: slot 1 works |
| `pico_fido2.uf2` (unsigned) | **Does not boot**: enforcement works |
| `pico_fido2.key0.signed.uf2` | Boots: slot 0 works. Leave this one installed |

### Stage 3: disable slots 2 and 3

**What it does:** sets `KEY_INVALID` for slots 2 and 3 (`12` = binary `1100`).

**Effect:** the chip has 4 key slots, and you only use 2. An empty slot is a
back door: someone with your token in BOOTSEL mode could burn **their own** key
hash into it, mark it valid, and boot their own firmware, which could then read
the master key. `KEY_INVALID` overrides `KEY_VALID`, so slots 2 and 3 are
ignored forever, whatever gets written into them.

**Permanent:** yes.

```bash
./picotool/picotool otp load otp-stage-3-invalidate-slots.json
./picotool/picotool otp get boot_flags1          # KEY_VALID = 3, KEY_INVALID = 12
```

### Stage 4: lock the pages

**What it does:** sets hardware locks on two OTP pages:

- **Page 1** (boot flags, `CRIT1`, the anti-rollback counter): read-only for
  BOOTSEL and untrusted code. Your own signed firmware can still change it, for
  example to raise the anti-rollback version later.
- **Page 2** (the key hashes): read-only for everyone.

**Effect:** stages 1–3 wrote the settings; stage 4 freezes them. Without it,
someone in BOOTSEL mode could still burn extra bits into those pages: changing
boot flags, or even disabling BOOTSEL to brick the token.

**Always last:** once page 1 is read-only for BOOTSEL, `otp load` can't write
stages 1–3 anymore.

**How it runs:** `otp permissions` doesn't write over USB like `otp load`. It
loads a small helper program into the Pico's RAM, which writes the locks from
inside the chip. Your firmware in flash isn't touched, and the locks themselves
go into OTP, so they survive power-off. With secure boot on, the helper must be
signed like any other program, so it needs the decrypted key0:

```bash
ansible-vault decrypt key0.pem.vault --output key0.pem
./picotool/picotool otp permissions --sign key0.pem otp-stage-4-lock-pages.json
rm key0.pem
```

The LED blinks while the locks are written. BOOTSEL mode again, then check:

```bash
./picotool/picotool otp get page1_lock1 page2_lock1
```

- Page 1: `LOCK_BL=1 LOCK_NS=1 LOCK_S=0`
- Page 2: `LOCK_BL=1 LOCK_NS=1 LOCK_S=1`

### Verify from the usage side

Unplug and plug in normally (without BOOTSEL):

```bash
fido2-token -L
ssh-keygen -t ed25519-sk -f /tmp/pico-test2      # PIN + press must still work
```

---

## Tokens 2 and 3 — once token 1 works

The hashes are already proven, so stages 1–3 go in one step. Stage 4 stays
separate and last.

1. **Step 0** (test both images).
2. Stages 1–3:

   ```bash
   ./picotool/picotool otp load otp-all.json
   ./picotool/picotool otp get bootkey0 bootkey1 boot_flags1 crit1
   ```

   Same checks as stages 1–3 above: hashes match the seal files,
   `KEY_VALID = 3`, `KEY_INVALID = 12`, `SECURE_BOOT_ENABLE = 1`.
3. Run the stage 2 boot tests (key1 boots, unsigned doesn't, key0 back on).
4. **Stage 4** with the decrypted key0, then delete it.
5. **Verify from the usage side.**

---

## Never

- Never run stage 2 (or `otp-all.json`) before the stage 1 hashes matched.
- Never run stage 4 before stages 1–3: page 1 becomes read-only for BOOTSEL.
- Never write a different hash into slot 0 or 1. Bits get OR'ed, and the hash is
  destroyed.
- Never disable USB boot / BOOTSEL. It's the only way to update.
- Never lose both private keys.
- Never run pico-fido2's own "Secure Lock" without checking what it does first.
  It overlaps with stages 3–4.

## Updating the firmware later

```bash
ansible-vault decrypt key0.pem.vault --output key0.pem
./picotool/picotool seal --sign new.uf2 new.signed.uf2 key0.pem
rm key0.pem
cp new.signed.uf2 /Volumes/RP2350/               # in BOOTSEL mode
```

Stay on the pico-fido2 project, so new versions can still read the master key
the firmware keeps in OTP. Otherwise your stored credentials become unreadable.
