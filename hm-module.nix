{ config, lib, pkgs, ... }:

let
  cfg = config.programs.atostek-id;

  # The browser setup script shipped in the package uses env vars
  # for tool paths, so we can override them cleanly.
  browserSetupWrapper = pkgs.writeShellScript "atostekid-setup-user-browser" ''
    export ATOSTEK_ID_BIN="${cfg.package}/bin/atostekid"
    export CERTUTIL_BIN="${pkgs.nssTools}/bin/certutil"
    export FIND_BIN="${pkgs.findutils}/bin/find"
    exec ${cfg.package.passthru.browserSetupScript} "$@"
  '';
in
{
  options.programs.atostek-id = {
    enable = lib.mkEnableOption "Atostek ID per-user setup";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.atostek-id;
      defaultText = lib.literalExpression "pkgs.atostek-id";
      description = "The Atostek ID FHS-wrapped package.";
    };

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start Atostek ID automatically on login.";
    };

    setupBrowserCerts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run the Atostek ID browser certificate setup on activation.
        This installs the SCS and erasmartcard.ehoito.fi CA certificates
        into Firefox profiles and the Chrome/Chromium NSS database so
        the browser trusts the local HTTPS interfaces.
      '';
    };

    firefox.enablePkcs11 = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Append p11-kit-proxy to Firefox's pkcs11.txt in each profile.
        This enables mTLS authentication (e.g. suomi.fi) via the
        Atostek ID PKCS#11 module through p11-kit.

        Note: requires the .deb (non-snap) version of Firefox.
        The p11-kit module must be registered system-wide via the
        NixOS module for this to pick it up.
      '';
    };

    chrome.enablePkcs11 = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Register the Atostek ID PKCS#11 module in the NSS shared
        database (~/.pki/nssdb) for Chrome/Chromium.
      '';
    };

    pkcs11ModulePath = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.atostek-id-pkcs11}/lib/Atostek-ID-PKCS11.so";
      defaultText = lib.literalExpression ''"''${pkgs.atostek-id-pkcs11}/lib/Atostek-ID-PKCS11.so"'';
      description = "Path to the Atostek ID PKCS#11 .so file.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Autostart desktop entry
    xdg.configFile."autostart/atostekid.desktop" = lib.mkIf cfg.autostart {
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Atostek ID
        Exec=${cfg.package}/bin/atostekid
        Comment=Smart card reader software for Finnish DVV certificate cards
        StartupNotify=false
        X-GNOME-Autostart-enabled=true
      '';
    };

    # Browser certificate activation.
    #
    # The upstream script calls `atostekid -installSCSCA` and
    # `atostekid -installCA` to generate the CA certs, then uses
    # certutil to register them in Firefox/Chrome NSS databases.
    #
    # This runs on every `home-manager switch` but is idempotent —
    # it removes and re-adds the certs.
    home.activation.atostek-id-browser-certs =
      lib.mkIf cfg.setupBrowserCerts
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          # Only run if atostekid binary is available
          if [ -x "${cfg.package}/bin/atostekid" ]; then
            $VERBOSE_ECHO "Setting up Atostek ID browser certificates..."
            ${browserSetupWrapper} || \
              $VERBOSE_ECHO "Warning: Atostek ID browser cert setup had errors (may be expected on first run)"
          fi
        '');

    # Firefox PKCS#11 via p11-kit-proxy.
    # Appends module registration to pkcs11.txt in each Firefox profile.
    home.activation.atostek-id-firefox-pkcs11 =
      lib.mkIf cfg.firefox.enablePkcs11
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $VERBOSE_ECHO "Registering p11-kit-proxy in Firefox profiles..."
          for profile_dir in "$HOME"/.mozilla/firefox/*.default*; do
            [ -d "$profile_dir" ] || continue
            pkcs11_txt="$profile_dir/pkcs11.txt"

            # Check if already registered
            if [ -f "$pkcs11_txt" ] && grep -q "p11-kit-proxy" "$pkcs11_txt"; then
              $VERBOSE_ECHO "  p11-kit-proxy already in $pkcs11_txt"
              continue
            fi

            $VERBOSE_ECHO "  Adding p11-kit-proxy to $pkcs11_txt"
            printf '\nlibrary=p11-kit-proxy.so\nname=p11-kit-proxy\n' >> "$pkcs11_txt"
          done
        '');

    # Chrome/Chromium NSS database registration.
    home.activation.atostek-id-chrome-pkcs11 =
      lib.mkIf cfg.chrome.enablePkcs11
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          NSS_DB="$HOME/.pki/nssdb"
          if [ -d "$NSS_DB" ]; then
            # Check if already registered
            if ${pkgs.nssTools}/bin/modutil -dbdir sql:"$NSS_DB" -list 2>/dev/null | grep -q "Atostek ID"; then
              $VERBOSE_ECHO "Atostek ID already registered in Chrome NSS database"
            else
              $VERBOSE_ECHO "Registering Atostek ID PKCS#11 module in Chrome NSS database..."
              ${pkgs.nssTools}/bin/modutil -add "Atostek ID" \
                -libfile "${cfg.pkcs11ModulePath}" \
                -dbdir sql:"$NSS_DB" \
                -mechanisms FRIENDLY \
                -force || $VERBOSE_ECHO "Warning: modutil registration failed"
            fi
          else
            $VERBOSE_ECHO "No Chrome NSS database at $NSS_DB — skipping PKCS#11 registration"
          fi
        '');
  };
}
