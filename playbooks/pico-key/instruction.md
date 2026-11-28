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

### 0.1 Prerequisites (macOS)

Apple's OpenSSH has no FIDO support. Use MacPorts:

```bash
sudo port install libfido2 openssh +fido2
hash -r                       # zsh may still have /usr/bin/ssh-keygen cached
whence -p ssh-keygen          # must print /opt/local/bin/ssh-keygen
```

Apple's launchd `ssh-agent` can't hold `-sk` keys. Use `/opt/local/bin/ssh-agent` if you need an agent.

### 0.2 Wipe the flash (twice)

Flashing a UF2 does **not** clear pico-fido's data (master secret, PIN, resident
keys, PHY settings). They live in a separate partition that the firmware's
partition table protects from BOOTSEL mode, so the first erase stops at it.

```bash
# BOOTSEL mode (unplug, hold BOOTSEL, plug in)
./picotool/picotool info -d                          # flash size: 4096K
./picotool/picotool erase -r 0x10000000 0x10400000   # stops at ~25% with "permission failure"

# BOOTSEL mode again: the partition table is gone now
./picotool/picotool partition info                   # no partition table
./picotool/picotool erase -r 0x10000000 0x10400000   # must reach 100%

# verify blank: must print 0
./picotool/picotool save -r 0x10000000 0x10400000 /tmp/flash.bin
LC_ALL=C tr -d '\377' < /tmp/flash.bin | wc -c
rm /tmp/flash.bin
```

### 0.3 Flash and check a clean device

```bash
cp pico_fido2.uf2 /Volumes/RP2350/        # or: ./picotool/picotool load -v -x pico_fido2.uf2

DEV=$(fido2-token -L | head -1 | awk -F': ' '{print $1}')   # path changes on every replug
fido2-token -I "$DEV" | grep options      # must show noclientPin
```

### 0.4 PIN and resident SSH key

```bash
fido2-token -S "$DEV"                     # set PIN
/opt/local/bin/ssh-keygen -t ed25519-sk -O resident -O application=ssh:main -C pico -f ./sk
fido2-token -L -r "$DEV"                  # PIN → shows ssh:main
```

### 0.5 Button press test

The firmware patch makes a press required (15 s timeout). Upstream default is
`up_btn = 0`, which auto-confirms presence.

```bash
echo hello > msg
rm -f msg.sig && /opt/local/bin/ssh-keygen -Y sign -f ./sk -n file msg
# press BOOTSEL when the LED blinks → writes msg.sig
rm -f msg.sig && /opt/local/bin/ssh-keygen -Y sign -f ./sk -n file msg
# don't press → must FAIL after ~15 s
```

### 0.6 Key lives on the Pico

```bash
# unplugged: must fail
ssh -i ./sk -o IdentitiesOnly=yes -o PasswordAuthentication=no user@host

# plugged in, files deleted: recover from the token
mkdir /tmp/rk && cd /tmp/rk
/opt/local/bin/ssh-keygen -K              # PIN → id_ed25519_sk_rk_main(.pub)
ssh-keygen -lf id_ed25519_sk_rk_main.pub  # fingerprint must match sk.pub
```

Optional browser test: webauthn.io or demo.yubico.com/webauthn-technical. With
user verification set to "discouraged" and the username entered, login must
need only a press (UP=true, UV=false).

### 0.7 Repeat with the signed image

Secure boot is still off, so it must behave exactly the same. Redo 0.2–0.6 with:

```bash
cp pico_fido2.key0.signed.uf2 /Volumes/RP2350/
```

Confirm the signed image is what's on the chip (see below).

### 0.8 Checking that the signed image is on the chip

In BOOTSEL mode, compare the chip with the file:

```bash
./picotool/picotool verify pico_fido2.key0.signed.uf2    # must pass
./picotool/picotool verify pico_fido2.uf2                # must FAIL (signature block differs)
```

Verify reads the program area back and compares it byte for byte with the
file. Only the program area is checked, so the protected data partition
doesn't get in the way. If the signed file passes and the unsigned one fails,
the signed image is what's running.

To look at the image details:

```bash
./picotool/picotool info -a                               # what's on the chip
./picotool/picotool info -a pico_fido2.key0.signed.uf2    # what's in the file
```

### 0.9 Clean up

- Remove test public keys from `authorized_keys` on every server you used.
- Delete test credentials: `fido2-token -D -i '<cred-id>' "$DEV"`, or just do the wipe in 0.2.

**Stop if** any check fails. Fix the build before going further.

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
./picotool/picotool otp get bootkey0_{0..15} bootkey1_{0..15} | grep -E "^ROW|VALUE"
```

Compare `bootkey0` and `bootkey1` with the hashes from the seal files:

```bash
python3 -c '
import json
[print(f"key{i}:",bytes(json.load(open(f"seal-key{i}.json"))["bootkey0"]).hex()) for i in (0,1)]
for i in (0, 1):
    h = bytes(json.load(open(f"seal-key{i}.json"))["bootkey0"])
    for r in range(16):
        print(f"ROW 0x{0x80 + 16*i + r:04x}: OTP_DATA_BOOTKEY{i}_{r} (Part {r+1}/16)")
        print(f"    VALUE 0x{h[2*r] | h[2*r+1] << 8:04x}")
'
```

Each OTP row holds 2 bytes of the hash. `BOOT_FLAGS1.KEY_VALID` must be `3`
(slots 0 and 1).

**Stop if** anything differs. Don't go on to stage 2.

### Stage 2: enable secure boot

**What it does:** sets `SECURE_BOOT_ENABLE`, `DEBUG_DISABLE` and
`SECURE_DEBUG_DISABLE` in `CRIT1`.

**Effect:** only signed images boot, and the SWD debug port is off for good.
Without the debug lock, anyone with a debug probe could halt the chip in
Secure mode and read the master key straight out of OTP, secure boot or not.

This is what keeps the master key safe: pico-fido2 stores it in OTP, readable
only by code running in Secure mode, and only your signed firmware can run there
now. Without secure boot, anyone could flash a program that reads the master key
out.

**Permanent:** yes. Secure boot can never be turned off again.

Check before burn:

```bash
./picotool/picotool info -d | grep -iE "secure boot|debug"
./picotool/picotool otp get crit1 | grep -E "VALUE|= "
```

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
