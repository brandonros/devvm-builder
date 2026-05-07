{
  description = "devvm — NixOS aarch64 qcow2 image for QEMU";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, home-manager }:
    let
      system = "aarch64-linux";
    in {
      nixosConfigurations.devvm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [

          ## --- linux base (kernel, firmware, boot, locale, nix settings) ---
          ({ config, lib, pkgs, modulesPath, ... }: {
            imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

            # Boot
            boot.loader.efi.efiSysMountPoint = "/boot/efi";
            boot.loader.grub = {
              enable = true;
              efiSupport = true;
              efiInstallAsRemovable = true;
              device = "nodev";
            };
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

            system.autoUpgrade.enable = false;

            networking.firewall.enable = true;
            networking.firewall.logRefusedConnections = true;
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

          ## --- disko (virtio-blk -> /dev/vda, EFI + ext4 root) ---
          disko.nixosModules.disko
          {
            disko.devices.disk.main = {
              device = "/dev/vda";
              type = "disk";
              content = {
                type = "gpt";
                partitions = {
                  ESP = {
                    size = "512M";
                    type = "EF00";
                    content = {
                      type = "filesystem";
                      format = "vfat";
                      mountpoint = "/boot/efi";
                    };
                  };
                  root = {
                    size = "100%";
                    content = {
                      type = "filesystem";
                      format = "ext4";
                      mountpoint = "/";
                    };
                  };
                };
              };
            };
          }

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
      };

      ## --- flake outputs: `nix build .#devvm` produces qcow2 under ./result/ ---
      packages.${system} = {
        devvm = self.nixosConfigurations.devvm.config.system.build.diskoImages;
        default = self.packages.${system}.devvm;
      };
    };
}
