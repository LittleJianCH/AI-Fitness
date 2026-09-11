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
          fitSdk = stable.stdenv.mkDerivation {
            pname = "garmin-fit-cpp-sdk";
            version = "21.214.0";
            src = stable.fetchzip {
              url = "https://codeload.github.com/garmin/fit-cpp-sdk/tar.gz/37cc1743e6b4e9e1642f1cbc83a6cf0c49632931";
              hash = "sha256-cXeMKX8M1K2xgsY84uHWC6ATo4KY+GeI+ka5RHOiKsk=";
            };
            buildPhase = ''
              runHook preBuild
              mkdir objects
              for source in src/*.cpp; do
                $CXX -std=c++17 -O2 -fPIC -Isrc -c "$source" -o "objects/$(basename "$source" .cpp).o"
              done
              $AR rcs libfitsdk.a objects/*.o
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out/lib/pkgconfig $out/include/fitsdk $out/share/licenses/fitsdk
              cp libfitsdk.a $out/lib/
              cp src/*.hpp src/*.h $out/include/fitsdk/
              cp LICENSE.txt $out/share/licenses/fitsdk/
              cat > $out/lib/pkgconfig/fitsdk.pc <<EOF
              Name: fitsdk
              Description: Garmin FIT C++ SDK
              Version: 21.214.0
              Libs: -L$out/lib -lfitsdk -l${if stable.stdenv.isDarwin then "c++" else "stdc++"}
              Cflags: -I$out/include/fitsdk
              EOF
              runHook postInstall
            '';
          };
        in
        {
          web = stable.mkShell {
            packages = [ stable.nodejs stable.pnpm ];
          };
          default = stable.mkShell {
            packages = [
              (haskell.ghc.withPackages (p: [
                p.ihp p.servant p.servant-server p.text p.time p.uuid-types p.vector p.wai p.warp
                p.aeson p.bytestring p.http-api-data p.http-types p.lens
                p.openapi3 p.servant-openapi3 p.wai-extra
                p.hasql p.hasql-transaction p.contravariant p.transformers p.async
              ]))
              haskell.cabal-install
              haskell.hlint
              haskell.fourmolu
              haskell.haskell-language-server
              haskell.ihp-migrate
              stable.postgresql
              fitSdk
              stable.pkg-config
              stable.clang-tools
              stable.gnumake
              stable.nodejs
              stable.pnpm
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
