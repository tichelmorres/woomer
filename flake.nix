{
  description = "Zoomer application for wayland inspired by tsoding's boomer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    crane.url = "github:ipetkov/crane";
    nixGL = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, systems, crane, nixGL, ... }:
    let
      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in {
      checks = forEachSystem (system: {
        inherit (self.packages.${system}) woomer;
      });

      packages = forEachSystem (system: let
        pkgs = nixpkgs.legacyPackages.${system};
        craneLib = crane.mkLib pkgs;

        commonArgs =
          let
            buildInputs = (with pkgs; [
              wayland
              glfw
              libgbm
            ]) ++ (
              with pkgs; [
                libX11.dev
                libXrandr.dev
                libXinerama.dev
                libXcursor.dev
                libXi.dev
              ]);
          in {
            src = let
              shaderFilter = path: _type: builtins.match ".*fs$" path != null;
              shaderOrCargo = path: type:
                (shaderFilter path type) || (craneLib.filterCargoSources path type);
            in
              pkgs.lib.cleanSourceWith {
                src = craneLib.path ./.;
                filter = shaderOrCargo;
              };
            strictDeps = true;
            nativeBuildInputs = with pkgs; [
              cmake
              pkg-config
              clang
              wayland
            ];
            inherit buildInputs;
            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;
            LIBCLANG_PATH = pkgs.libclang.lib + "/lib/";
          };

        # The raw crane build, without the nixGL wrapper
        woomer-unwrapped = craneLib.buildPackage (commonArgs // {
          pname = "woomer";
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          postFixup = ''
            patchelf $out/bin/woomer \
              --add-needed libwayland-client.so \
              --add-needed libwayland-cursor.so \
              --add-needed libwayland-egl.so \
              --add-rpath ${pkgs.lib.makeLibraryPath [ pkgs.wayland ]}
          '';

          meta = {
            description = "Zoomer application for Wayland inspired by tsoding's boomer";
            license = pkgs.lib.licenses.mit;
            mainProgram = "woomer";
          };
        });

        woomer-wrapped = pkgs.writeShellScriptBin "woomer" ''
          export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ pkgs.mesa pkgs.libglvnd pkgs.wayland ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          export __EGL_VENDOR_LIBRARY_FILENAMES="${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json"
          export LIBGL_DRIVERS_PATH="${pkgs.mesa}/lib/dri"
          export GBM_BACKENDS_PATH="${pkgs.mesa}/lib/gbm"
          exec ${woomer-unwrapped}/bin/woomer "$@"
        '';
      in {
        inherit woomer-unwrapped;
        woomer = woomer-wrapped;
        default = woomer-wrapped;
      });

      apps = forEachSystem (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/woomer";
        };
      });

      devShells = forEachSystem (system: let
        pkgs = nixpkgs.legacyPackages.${system};
        craneLib = crane.mkLib pkgs;
      in {
        default = craneLib.devShell {
          checks = self.checks.${system};
          packages = with pkgs; [
            rust-analyzer
          ];
          env = {
            inherit (self.packages.${system}.woomer-unwrapped)
              LIBCLANG_PATH LD_LIBRARY_PATH;
          };
          inputsFrom = [
            self.packages.${system}.woomer-unwrapped
          ];
        };
      });
    };
}
