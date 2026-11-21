# pico-key

Builds pico-fido2 for the Raspberry Pi Pico 2 (RP2350), creates the signing
keys, signs the firmware, and prepares everything needed to burn secure boot
into the board.

The playbook only does **reversible** work. It never touches a Pico. Burning the
OTP fuses is done by hand afterwards, following
`playbooks/pico-key/dist/README.md`.

## Run

```bash
ansible-playbook playbooks/pico-key/main.yml -e target=mac
```

`target` is required: the playbook stops if it isn't set. It's a host or group
from the inventory.

> **Important:** every version is pinned in the `vars` of `main.yml`: the
> pico-sdk, picotool (version and release tag) and the pico-fido2 ref. That's
> the one place to change them. Nothing is downloaded "latest".

## What it does

1. **Downloads picotool.** The pinned version from the official Raspberry Pi
   release, checked against the SHA-256 that GitHub publishes for the file.
   Skipped if it's already cached. The version is checked on every run.
2. **Builds pico-fido2 in Docker.** The pico-sdk, picotool and the pico-fido2
   commit are all pinned inside the image, so every build gets the same
   toolchain. The finished firmware (`.uf2`, `.elf`, …) is copied out to the
   host.
3. **Generates two signing keys, key0 and key1.** secp256k1, the only curve the
   RP2350 bootrom accepts. They're written straight into ansible-vault encrypted
   files, so the unencrypted private key never touches the disk. **Existing keys
   are never overwritten**, so re-running the playbook is safe.
4. **Signs the firmware** with each key, and builds the OTP files (stages 1–4
   plus a combined one) from picotool's output.
5. **Fills `playbooks/pico-key/dist/`:** picotool, the unsigned and signed
   firmware, the encrypted keys, the OTP files, and `README.md`, the
   step-by-step guide for burning the board.

## Then

```bash
cd playbooks/pico-key/dist
open README.md   # or read it any other way
```

and follow it. It starts with a firmware test that burns nothing.

## Keys

- `key0.pem.vault` and `key1.pem.vault` in `playbooks/pico-key/dist/` are the
  only copies. **Back them up to two offline places before burning a board.**
  Once their hashes are in a Pico's OTP, losing both means that board can never
  run new firmware.
- They're encrypted with your vault password, so whoever gets that password gets
  the keys. Keep it in Keychain or a password manager, never in the repo.
- Decrypt only when needed (stage 4, future updates), and delete the decrypted
  file right after. The README in `dist/` shows how.

## Re-running

- **Safe:** downloads are cached, existing keys are kept, and the build and
  signing run again.
- **New firmware version:** bump the pico-fido2 ref (and pico-sdk if needed) in
  `main.yml` and re-run. The same keys sign the new build, so already-burned
  boards accept it.
- **New picotool version:** bump its version and release tag in `main.yml`. The
  binary is checked against the pin on every run, so a mismatch fails loudly.
- **New keys:** delete the `.vault` files first. Only do this for boards that
  haven't been burned yet: a burned board only accepts the keys whose hashes are
  in its OTP.

## Troubleshooting

| Error | Cause / fix |
| --- | --- |
| `Failed to import the required Python library (requests)` | `pipx inject ansible requests docker` |
| Task hangs, or ansible-vault asks for a password | No `vault_password_file` in `ansible.cfg`, or it isn't found. Run from the repo root. |
| `Cannot connect to the Docker daemon` | Start Docker on the target. |
| picotool version assert fails | Old binary in the cache. Delete the cached picotool folder and re-run. |
| `prebuilt picotool requires macOS 14+` | Use a newer Mac or a Linux target. |

### The Docker build step looks stuck

Building the Docker image is by far the slowest step: it compiles pico-fido2 and
its toolchain pieces from source, and the playbook shows no progress while it
runs. To watch it, build the image yourself once, with the values from the
`vars` in `main.yml`:

```bash
docker build \
  --build-arg picosdk_version=2.3.1 \
  --build-arg picotool_release_tag=v2.3.1-0 \
  --build-arg picofido2_ref=v7.4.2-librekeys \
  -t pico-fido2-builder \
  playbooks/pico-key/container
```

With the same values, the next playbook run reuses Docker's build cache and this
step is quick.
