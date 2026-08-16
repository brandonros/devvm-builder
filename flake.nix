{
  description = "devvm — NixOS aarch64 qcow2 image for QEMU";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      modules = [

        ## --- linux base (boot, locale, nix settings) ---
        ({ config, lib, pkgs, modulesPath, ... }: {
          imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

          # Boot. systemd-boot manages bootloader updates after first boot;
          # the *initial* bootloader files are written into the ESP at image-build
          # time by the repart module below (see "10-esp" contents).
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = false;
          boot.tmp.cleanOnBoot = true;

          # Filesystems — discovered by GPT partition label (set in repart config).
          fileSystems."/" = {
            device = "/dev/disk/by-partlabel/root";
            fsType = "ext4";
          };
          fileSystems."/boot" = {
            device = "/dev/disk/by-partlabel/ESP";
            fsType = "vfat";
          };
          boot.kernelParams = [ "root=PARTLABEL=root" ];

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

        ## --- image build via systemd-repart (no VM, no KVM) ---
        ## Builds the partitioned raw disk image entirely in the nix sandbox.
        ## We hand-place the systemd-boot binary and a single bootloader entry
        ## into the ESP so the image is bootable on first power-on; after that,
        ## NixOS's systemd-boot module manages /boot normally.
        ({ config, lib, pkgs, modulesPath, ... }: {
          imports = [ (modulesPath + "/image/repart.nix") ];

          image.repart = {
            name = "devvm";
            partitions = {
              "10-esp" = {
                contents = {
                  # Removable-media path (firmware fallback) and standard systemd path.
                  "/EFI/BOOT/BOOTAA64.EFI".source =
                    "${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootaa64.efi";
                  "/EFI/systemd/systemd-bootaa64.efi".source =
                    "${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootaa64.efi";

                  "/loader/loader.conf".source = pkgs.writeText "loader.conf" ''
                    default nixos-generation-1.conf
                    timeout 1
                  '';

                  "/loader/entries/nixos-generation-1.conf".source =
                    pkgs.writeText "nixos-generation-1.conf" ''
                      title NixOS
                      linux /EFI/nixos/kernel
                      initrd /EFI/nixos/initrd
                      options init=${config.system.build.toplevel}/init ${lib.concatStringsSep " " config.boot.kernelParams}
                    '';

                  "/EFI/nixos/kernel".source =
                    "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
                  "/EFI/nixos/initrd".source =
                    "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
                };
                repartConfig = {
                  Type = "esp";
                  Format = "vfat";
                  Label = "ESP";
                  SizeMinBytes = "256M";
                  SizeMaxBytes = "256M";
                };
              };
              "20-root" = {
                storePaths = [ config.system.build.toplevel ];
                repartConfig = {
                  Type = "root";
                  Format = "ext4";
                  Label = "root";
                  SizeMinBytes = "8G";
                };
              };
            };
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

            programs.bash = {
              enable = true;
            };

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

      ## --- flake outputs ---
      ## repart produces a raw image; we wrap it in qemu-img convert to get qcow2.
      ## Both steps run in the nix sandbox — no VM, no KVM.
      packages.${system} = {
        devvm = pkgs.runCommand "devvm.qcow2" {
          nativeBuildInputs = [ pkgs.qemu-utils ];
        } ''
          qemu-img convert -f raw -O qcow2 \
            ${self.nixosConfigurations.devvm.config.system.build.image}/devvm.raw \
            $out
        '';
        default = self.packages.${system}.devvm;
      };
    };
}
