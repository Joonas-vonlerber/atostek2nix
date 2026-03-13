{
  description = "Atostek ID – Finnish DVV smart card reader software";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system} = {
        atostek-id = pkgs.callPackage ./package.nix { };
        atostek-id-pkcs11 = pkgs.callPackage ./pkcs11.nix { };
        default = self.packages.${system}.atostek-id;
      };

      nixosModules.atostek-id = import ./module.nix;
      nixosModules.default = self.nixosModules.atostek-id;

      homeManagerModules.atostek-id = import ./hm-module.nix;
      homeManagerModules.default = self.homeManagerModules.atostek-id;
    };
}
