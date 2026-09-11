{
  description = "AI Fitness";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";
    ihp.url = "https://codeload.github.com/digitallyinduced/ihp/tar.gz/refs/heads/v1.6";
    systems.follows = "ihp/systems";
  };

  outputs = { nixpkgs, ihp, systems, ... }:
    let
      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    {
      devShells = forEachSystem (system:
        let
          stable = import nixpkgs { inherit system; };
          ihpPkgs = import ihp.inputs.nixpkgs {
            inherit system;
            overlays = [ ihp.overlays.default ];
          };
          haskell = ihpPkgs.ghc;
        in
        {
          default = stable.mkShell {
            packages = [
              (haskell.ghc.withPackages (p: [
                p.ihp p.servant p.servant-server p.text p.time p.uuid-types p.vector p.wai p.warp
              ]))
              haskell.cabal-install
              haskell.hlint
              haskell.fourmolu
              haskell.haskell-language-server
              stable.gnumake
              stable.nodejs
              stable.curl
              stable.git
            ];
          };
        });
    };

  nixConfig = {
    extra-substituters = [
      "https://devenv.cachix.org"
      "https://cachix.cachix.org"
      "https://digitallyinduced.cachix.org"
      "https://cache.digitallyinduced.com/public"
    ];
    extra-trusted-public-keys = [
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
      "digitallyinduced.cachix.org-1:y+wQvrnxQ+PdEsCt91rmvv39qRCYzEgGQaldK26hCKE="
      "public:kR6JCoqAIMaO4s+EdDGh+jsHEHnoLq4ZLJPMCo0hcIQ="
    ];
  };
}
