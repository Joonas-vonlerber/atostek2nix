# Atostek ID for NixOS

Nix flake packaging of [Atostek ID](https://dvv.fi/en/card-reader-software) — the official Finnish DVV (Digital and Population Data Services Agency) smart card reader software.

Supports DVV-issued certificate cards for:
- Electronic identification (mTLS / suomi.fi)
- Digital signatures (SCS API, PAdES, CAdES, etc.)
- Healthcare ERA system login

## Architecture

The binary contains ~8 hardcoded `/usr/*` paths that can't be fixed by `patchelf` alone (they're string constants, not ELF headers). This flake uses `buildFHSEnv` to present a virtual FHS filesystem to the process.

| Component | Purpose |
|---|---|
| `packages.atostek-id` | FHS-wrapped main application (GUI + HTTPS servers) |
| `packages.atostek-id-pkcs11` | Standalone PKCS#11 module (no FHS paths, clean) |
| `nixosModules.atostek-id` | System: pcscd, p11-kit registration, DNS, /etc config |
| `homeManagerModules.atostek-id` | Per-user: browser certs, PKCS#11 in Firefox/Chrome, autostart |

## Usage

### 1. Add the flake input

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    atostek-id = {
      url = "github:YOUR_USER/atostek-id-nix";  # or path, git, etc.
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

### 2. Apply the overlay to your nixpkgs

This is the key step — it makes `pkgs.atostek-id` and `pkgs.atostek-id-pkcs11` available, built with YOUR nixpkgs config (including `allowUnfree`).

```nix
# In your NixOS configuration (e.g. flake.nix outputs)
nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
  modules = [
    { nixpkgs.overlays = [ inputs.atostek-id.overlays.default ]; }
    inputs.atostek-id.nixosModules.atostek-id
    # ... your other modules
  ];
};
```

### 3. NixOS module (system-level)

```nix
# In your NixOS configuration module
{
  programs.atostek-id = {
    enable = true;
    # package and pkcs11Package default to pkgs.atostek-id / pkgs.atostek-id-pkcs11
    # via the overlay — no need to set them explicitly.

    # Optional: set default language
    configFile = {
      LANGUAGE = "fi";
    };
  };
}
```

This gives you:
- `pcscd` service enabled
- PKCS#11 module registered in p11-kit (`p11-kit list-modules` will show it)
- `erasmartcard.ehoito.fi` → `127.0.0.1` in `/etc/hosts`
- `atostekid` binary on `$PATH`
- `certutil` (nss-tools) available

### 4. Home Manager module (per-user)

```nix
# In your Home Manager configuration
{
  imports = [ inputs.atostek-id.homeManagerModules.atostek-id ];

  programs.atostek-id = {
    enable = true;
    # Defaults from the overlay — no explicit package needed.

    autostart = true;          # XDG autostart entry
    setupBrowserCerts = true;  # install SCS/ehoito CA certs in browsers

    # Enable PKCS#11 for mTLS authentication (suomi.fi)
    firefox.enablePkcs11 = true;
    chrome.enablePkcs11 = true;
  };
}
```

### 5. Desktop environment: tray icon

Atostek ID uses a tray indicator (AppIndicator). You need support in your DE:

**GNOME** — install and enable the AppIndicator extension:
```nix
# In your NixOS config
environment.systemPackages = [ pkgs.gnomeExtensions.appindicator ];
# Or enable via dconf/Home Manager
```

**KDE Plasma** — works out of the box (built-in SNI/AppIndicator support).

**Hyprland / Sway** — use `waybar` with the `tray` module, or `swaybar` (no extra config needed if you already have a system tray).

## First run

After `nixos-rebuild switch` and `home-manager switch`:

1. Start `atostekid` (or log out/in if autostart is enabled)
2. The app may prompt to run user-specific setup on first launch — accept it
3. Insert your smart card into a PC/SC-compatible reader
4. The tray icon should turn green when a card is detected

### Testing

- **SCS interface**: open `https://localhost:53952/` in your browser — should show "Atostek ID SCS test page loaded OK."
- **erasmartcard interface**: open `https://erasmartcard.ehoito.fi:44304/` — same test page
- **mTLS (suomi.fi)**: go to `https://dvv.fineid.fi/en/authentication`
- **PKCS#11 module**: run `p11-kit list-modules` — should list `atostek-id`

## Known issues / TODO

- [ ] `fetchurl` hash needs to be filled on first build (nix will tell you the correct one)
- [ ] The bundled OpenSSL 3.3.2 has an OPENSSLDIR of `/usr/local/ssl` — the FHS env doesn't populate this, which may cause issues with cert chain resolution. If signatures fail, try symlinking system CA certs there.
- [ ] The `buildFHSEnv` wrapper means the process runs in a lightweight namespace. This shouldn't affect pcscd communication (it goes through the Unix socket) but test thoroughly.
- [ ] The browser cert setup activation script calls the atostekid binary with `-installSCSCA` / `-installCA` flags. This may fail on first `home-manager switch` if the binary hasn't run yet (it needs to generate certs first). A second `home-manager switch` after the first manual run should work.
- [ ] The PKCS#11 module (the `.so` itself) does NOT need FHS wrapping — it's clean. But the main application it cooperates with does. Test that `p11-kit list-modules` works and tokens are visible when a card is inserted.

## Troubleshooting

**"Failed to open SCS server on port 53952!"**
Another process is using the port. Check with `ss -tlnp | grep 53952`. Likely another card reader software (e.g. DigiSign).

**Card not detected**
```bash
# Check pcscd is running
systemctl status pcscd.service
# Check the reader is visible
pcsc_scan
```

**Browser doesn't offer certificate for mTLS**
- Firefox: check `about:preferences#privacy` → Security Devices → p11-kit-proxy should be listed
- Chrome: run `modutil -dbdir sql:$HOME/.pki/nssdb -list` — "Atostek ID" should appear

**The tray icon doesn't appear**
Ensure your DE has AppIndicator/SNI support enabled (see section 4 above).
