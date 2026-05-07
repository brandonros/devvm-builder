{
  description = "devvm — NixOS aarch64 qcow2 image for QEMU";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixos-generators }:
    let
      system = "aarch64-linux";

      modules = [

        ## --- linux base (boot, locale, nix settings) ---
        ({ config, lib, pkgs, modulesPath, ... }: {
          imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

          # Boot — systemd-boot is simpler than grub for pure-EFI VMs and plays
          # cleanly with make-disk-image (which nixos-generators uses).
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = false;
          boot.tmp.cleanOnBoot = true;

          # Locale
          time.timeZone = "America/New_York";
          i18n.defaultLocale = "en_US.UTF-8";

          # Nix
          nix.settings.experimental-features = [ "nix-command" "flakes" ];
          nixpkgs.config.allowUnfree = true;
          system.stateVersion = "25.11";

          nix.gc = {
            automatic = true;
            dates = "weekly";
            options = "--delete-older-than 30d";
          };

          nix.optimise = {
            automatic = true;
            dates = [ "weekly" ];
          };
        })

        ## --- user account ---
        ({ lib, ... }: {
          users.users.user = {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
            hashedPassword = "$6$ZIVIn9wTIImsqY8a$8ApSAAI8GOJXKx330giWu.y7.qYip/txYZHdvOD5zp1BSINVW001aam.g8bWcrG9MQhPYnAlzzJHshffzSmLq1"; # foobar123
            openssh.authorizedKeys.keys =
              let
                raw = builtins.readFile ./keys/brandon.pub;
                lines = map (l: lib.strings.trim l) (lib.splitString "\n" raw);
              in
                lib.filter (l: l != "" && !(lib.hasPrefix "#" l)) lines;
          };
          users.mutableUsers = false;
          security.sudo.wheelNeedsPassword = false;
        })

        ## --- qemu guest profile (virtio kernel modules, etc.) ---
        ({ modulesPath, ... }: {
          imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
        })

        ## --- networking (QEMU user-mode net, DHCP via slirp) ---
        {
          networking.hostName = "devvm";
          networking.useDHCP = true;
        }

        ## --- home-manager ---
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.user = { config, pkgs, lib, ... }: {
            home.stateVersion = "25.11";
            home.username = "user";
            home.homeDirectory = "/home/user";

            ## home: packages
            home.packages = with pkgs; [
              # core
              bash
              tmux
              git

              # language runtimes
              python3       # ad-hoc scripts, build-script deps
              uv            # python package manager

              # hardware
              usbutils      # lsusb
              pciutils      # lspci
              inxi          # system summary (inxi -F)
              dmidecode     # bios/memory/motherboard info
              lshw          # detailed hardware listing

              # disk
              parted        # partition editor
              hdparm        # disk params/benchmarks

              # monitoring
              btop          # system monitor tui
              bandwhich     # per-process bandwidth
              below         # per-cgroup resource monitor
              iotop         # per-process I/O monitor
              ncdu          # interactive disk usage explorer
              duf           # disk free overview (pretty df)
              procs         # pretty ps
              systemctl-tui # systemd service manager

              # networking
              ethtool       # ethernet interface stats
              iperf3        # network bandwidth testing
              mtr           # traceroute + ping
              dnsutils      # dig/nslookup
              nmap          # network scanner
              tcpdump       # packet capture

              # debugging
              lsof          # list open files/sockets
              strace        # system call tracer

              # media
              ffmpeg        # video/audio transcoding + probing

              # utilities
              curl          # HTTP client
              wget          # HTTP fetcher
              aria2         # download manager
              rsync         # efficient file sync/copy
              socat         # multipurpose socket relay
              pv            # pipe progress meter
              jq            # json processor
              tree          # directory tree
              fd            # fast find
              ripgrep       # fast grep (rg)
              xxd           # hex
              file          # file type identification
              binutils      # strings, objdump, nm, etc.
              unzip         # .zip
              p7zip         # .7z
              unrar         # .rar
            ];

            programs.home-manager.enable = true;

            ## home: bash
            programs.bash = {
              enable = true;
            };

            ## home: git (identity + push behavior + gh credential helper)
            programs.git = {
              enable = true;
              settings = {
                user = {
                  name = "Brandon Ros";
                  email = "brandonros1@gmail.com";
                };
                push = {
                  autoSetupRemote = true;
                };
                credential."https://github.com" = {
                  helper = "!${pkgs.gh}/bin/gh auth git-credential";
                };
                credential."https://gist.github.com" = {
                  helper = "!${pkgs.gh}/bin/gh auth git-credential";
                };
              };
            };

            ## home: direnv (auto-activate per-project flakes on `cd`)
            programs.direnv = {
              enable = true;
              nix-direnv.enable = true;
            };
          };
        }

        ## --- ssh daemon ---
        {
          services.openssh = {
            enable = true;
            settings.PermitRootLogin = "prohibit-password";
            settings.PasswordAuthentication = false;
          };
        }

        ## --- nix-ld: dynamic linker shim so unpatched FHS binaries work ---
        ## (VSCode Remote-SSH server's bundled node, language servers, etc.)
        { programs.nix-ld.enable = true; }
      ];
    in {
      nixosConfigurations.devvm = nixpkgs.lib.nixosSystem {
        inherit system modules;
      };

      ## --- flake outputs: `nix build .#devvm` produces qcow2 under ./result/ ---
      ## nixos-generators builds the qcow2 in the sandbox via make-disk-image.nix
      ## — no nested VM, no KVM needed (works on aarch64 GitHub runners).
      packages.${system} = {
        devvm = nixos-generators.nixosGenerate {
          inherit system modules;
          format = "qcow-efi";
        };
        default = self.packages.${system}.devvm;
      };
    };
}
