{ config, lib, pkgs, ... }:

let
  cfg = config.programs.atostek-id;
in
{
  options.programs.atostek-id = {
    enable = lib.mkEnableOption "Atostek ID smart card reader software (Finnish DVV)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.atostek-id;
      defaultText = lib.literalExpression "pkgs.atostek-id";
      description = "The Atostek ID FHS-wrapped package.";
    };

    pkcs11Package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.atostek-id-pkcs11;
      defaultText = lib.literalExpression "pkgs.atostek-id-pkcs11";
      description = "The standalone Atostek ID PKCS#11 module package.";
    };

    configFile = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { LANGUAGE = "fi"; };
      description = ''
        Key-value pairs written to /etc/AtostekIDConfig.
        The binary reads this on startup for installation-level defaults.
        Supported keys: LANGUAGE (en/fi/sv), AIDISURL, AIDISAPIKEY.
      '';
    };

    systemConfigFile = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Key-value pairs written to /etc/atostekid/AtostekID.ini.
        System-wide settings overridden by per-user ini in ~/.local/share/.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    # pcscd is mandatory — smart card daemon
    services.pcscd.enable = true;

    # Register the PKCS#11 module with p11-kit system-wide.
    # This makes it visible to `p11-kit list-modules` and any
    # consumer that goes through p11-kit (SSSD, GnuTLS, etc.)
    environment.etc."pkcs11/modules/atostek-id.module".text = ''
      module: ${cfg.pkcs11Package}/lib/Atostek-ID-PKCS11.so
    '';

    # The main (FHS-wrapped) binary + certutil for browser cert management
    environment.systemPackages = [
      cfg.package
      pkgs.nssTools
    ];

    # /etc/AtostekIDConfig — installation-level config
    environment.etc."AtostekIDConfig" = lib.mkIf (cfg.configFile != { }) {
      text = lib.concatStringsSep "\n"
        (lib.mapAttrsToList (k: v: "${k}=${v}") cfg.configFile)
        + "\n";
    };

    # /etc/atostekid/AtostekID.ini — system-wide settings
    environment.etc."atostekid/AtostekID.ini" = lib.mkIf (cfg.systemConfigFile != { }) {
      text = lib.concatStringsSep "\n"
        (lib.mapAttrsToList (k: v: "${k}=${v}") cfg.systemConfigFile)
        + "\n";
    };

    # DNS: erasmartcard.ehoito.fi must resolve to 127.0.0.1.
    # The binary checks this. It's also required for the HTTPS
    # signature API to work — it listens on localhost and the
    # browser connects via this hostname.
    networking.hosts = {
      "127.0.0.1" = [ "erasmartcard.ehoito.fi" ];
    };
  };
}
