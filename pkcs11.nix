# Standalone PKCS#11 module — used by p11-kit, browsers, and other
# PKCS#11 consumers. This is separate from the main FHS-wrapped package
# because the .so itself has NO hardcoded FHS paths (only links against
# libpcsclite.so.1 and libc).
{ lib
, stdenv
, fetchurl
, dpkg
, autoPatchelfHook
, pcsclite
}:

stdenv.mkDerivation {
  pname = "atostek-id-pkcs11";
  version = "4.4.1.0";

  src = fetchurl {
    url = "https://files.fineid.fi/download/atostek/4.4.1.0/linux/AtostekID_DEB_4.4.1.0.deb";
    # TODO: same hash as package.nix — consider a shared fetcher
    hash = "sha256-b+w9ib8v+VovEqzS0oVjuaTOQW2C3lLogkAcS85Mpkc=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook ];

  buildInputs = [
    pcsclite
    stdenv.cc.cc.lib
  ];

  unpackPhase = "dpkg-deb -x $src .";

  installPhase = ''
    install -Dm755 usr/lib/Atostek-ID-PKCS11.so $out/lib/Atostek-ID-PKCS11.so

    # p11-kit module definition
    install -dm755 $out/share/p11-kit/modules
    echo "module: $out/lib/Atostek-ID-PKCS11.so" \
      > $out/share/p11-kit/modules/atostek-id.module
  '';

  meta = with lib; {
    description = "Atostek ID PKCS#11 module for Finnish DVV smart cards";
    homepage = "https://dvv.fi/en/card-reader-software";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
