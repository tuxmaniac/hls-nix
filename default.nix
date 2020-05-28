let

  # haskell.nix
  haskell-nix-src = builtins.fetchTarball {
    name = "haskell-nix-src";
    url = "https://github.com/tuxmaniac/haskell.nix/archive/c1bdbb283818ce848487b49eb65d7935020715e2.tar.gz";
    sha256 = "1w9h340blj3xl49p00xfzm42y1vhyk05jzjn3vm0r2661a7apgc0";
  };

  # nixpkgs release 20.03
  pinned-pkgs-src = builtins.fetchTarball {
    name = "nixpkgs";
    url = "https://github.com/NixOS/nixpkgs/archive/5272327b81ed355bbed5659b8d303cf2979b6953.tar.gz";
    sha256 = "0182ys095dfx02vl2a20j1hz92dx3mfgz2a6fhn31bqlp1wa8hlq";
  };

  # haskell-language-server
  hls-src = builtins.fetchTarball {
    name = "hls-src";
    url = "https://github.com/haskell/haskell-language-server/archive/0d5c5d4d62f637aebfc1cff8770ff40c2afbab4d.tar.gz";
    sha256 = "0b3wkgyxn9dlj4ypkb4mydf2jd1kdpn5s0b190yzjy2akkz3zla8";
  };

  # ghcide submodule
  ghcide-src = builtins.fetchTarball {
    name = "ghcide-src";
    url = "https://github.com/alanz/ghcide/archive/5ca6556996543312e718559eab665fe3b1926b03.tar.gz";
    sha256 = "1sni15wbj9jmrvhsfv31c0j587xhcfqkc0qg9pmlhf9zw4kgpghd";
  };

  haskell-nix-config = import "${haskell-nix-src}/config.nix";
  haskell-nix-overlays = [ (import "${haskell-nix-src}/overlays" {}).combined ];

  pkgs-glibc = import pinned-pkgs-src {
    config = haskell-nix-config;
    overlays = haskell-nix-overlays;
  };

  pkgs-cross = import pinned-pkgs-src {
    config = haskell-nix-config;
    overlays = haskell-nix-overlays ++ [(self: super: {
      haskell-nix = super.haskell-nix // {
        bootstrap = super.haskell-nix.bootstrap // {
          compiler = pkgs-glibc.haskell-nix.compiler;
          packages = pkgs-glibc.haskell-nix.bootstrap.packages;
        };
      };
    })];
    crossSystem = pkgs-glibc.lib.systems.examples.musl64;
  };

  pkgs-musl = import pinned-pkgs-src {
    config = haskell-nix-config;
    overlays = [(_: super: super.pkgsMusl)] ++ haskell-nix-overlays ++ [(self: super: {
      haskell-nix = super.haskell-nix // {
        bootstrap = super.haskell-nix.bootstrap // {
          compiler = pkgs-cross.haskell-nix.compiler;
          packages = pkgs-glibc.haskell-nix.bootstrap.packages;
        };
      };
    })];
  };

  hls-build = pkgs: ghc: (
    let
      # Making static binaries with musl
      isStatic = pkgs.stdenv.hostPlatform.isMusl;

      # Force Cabal 3.0 usage for ghc-8.6.x
      forceCabal3 = builtins.compareVersions ghc.version "8.8.0" < 0;

      # For now input-output-hk/stackage.nix repo
      # have bad builtin packages descriptions
      # for lts-15.3 stackage (last for ghc-8.8.2)
      # Need some quirks until maintainers fix it
      badStackage = builtins.compareVersions ghc.version "8.8.2" == 0;

      # Dynamic linking with haskell libraries when using glibc
      exeConfigureFlags = if !isStatic then [ "--enable-executable-dynamic" ] else [];

      # Any patches related to stack.yaml must be done before stackProject call
      hls-src-patched = pkgs.stdenvNoCC.mkDerivation {
        name = "hls-src-patched-for-ghc-${ghc.version}";
        src = hls-src;
        patches = [
          # specified commit have no entry in hackage.nix db
          ./revert-shake.patch
          # temporary fix for reinstallable ghc library
          ./check-ghc-version.patch
        ];
        prePatch = ''
          rm -fr ghcide
          cp -fr ${ghcide-src} ghcide
          chmod -R u+w ghcide
        '';
        postPatch = ''
          sed -i -e 's%@rev.*$%%g' stack*.yaml
          sed -i -e 's@#GHC_VERSION#@${builtins.replaceStrings ["."] [","] ghc.version}@g' exe/Main.hs
          find . -name '*.orig' -delete
        '';
        dontBuild = true;
        installPhase = ''
          mkdir -p $out
          cp -a * $out
        '';
      };

    in pkgs.haskell-nix.stackProject {
      src = pkgs.haskell-nix.cleanSourceHaskell {
        src = "${hls-src-patched}";
      };
      stackYaml = "stack-${ghc.version}.yaml";
      pkg-def-extras = []
        ++ (if forceCabal3 then [
          (hackage: {packages = {
            Cabal = hackage.Cabal."3.0.0.0".revisions.default;
          };}) ] else [])
        ++ (if badStackage then [
          (hackage: {packages = {
            # Use lts-15.3 versions
            process = hackage.process."1.6.7.0".revisions.default;
            text = hackage.text."1.2.4.0".revisions.default;
            hpc = hackage.hpc."0.6.0.3".revisions.default;
            terminfo = hackage.terminfo."0.4.1.4".revisions.default;
            stm = hackage.stm."2.5.0.0".revisions.default;
            mtl = hackage.mtl."2.2.2".revisions.default;
            Cabal = hackage.Cabal."3.0.0.0".revisions.default;
            parsec = hackage.parsec."3.1.14.0".revisions.default;
            directory = hackage.directory."1.3.4.0".revisions.default;
            xhtml = hackage.xhtml."3000.2.2.1".revisions.default;
            filepath = hackage.filepath."1.4.2.1".revisions.default;
            unix = hackage.unix."2.7.2.2".revisions.default;
            binary = hackage.binary."0.8.7.0".revisions.default;
            containers = hackage.containers."0.6.2.1".revisions.default;
            bytestring = hackage.bytestring."0.10.10.0".revisions.default;
            transformers = hackage.transformers."0.5.6.2".revisions.default;
            time = hackage.time."1.9.3".revisions.default;
          };}) ] else [])
        ;
      modules = [
        ( {config, ...}: {
            ghc.package = ghc;
            compiler.version = ghc.version;
            reinstallableLibGhc = true;
            packages.ghc.flags.ghci = true;
            packages.ghci.flags.ghci = true;
            packages.haskell-language-server = {
              components.exes.haskell-language-server-wrapper = {
                configureFlags = exeConfigureFlags;
              };
              components.exes.haskell-language-server = {
                configureFlags = exeConfigureFlags;
                postInstall = "mv $out/bin/haskell-language-server{,-${ghc.version}}";
              };
            };
            dontStrip = false;
            doHaddock = false;
          }
        )
      ];
    }
  );

  compilers = pkgs: (with pkgs.haskell-nix.compiler; [
    ghc883
    ghc882
    ghc865
  ]);

  hls-builds = pkgs: builtins.map (hls-build pkgs) (compilers pkgs);

  hls = pkgs: (let hls-exes = hls-builds pkgs; in pkgs.symlinkJoin {
    name = "haskell-language-server";
    paths = [
      (builtins.head hls-exes).haskell-language-server.components.exes.haskell-language-server-wrapper
    ] ++ (builtins.map (a: a.haskell-language-server.components.exes.haskell-language-server) hls-exes);
  });

in {
  hls-glibc = hls pkgs-glibc;
  hls-musl  = hls pkgs-musl;
}
