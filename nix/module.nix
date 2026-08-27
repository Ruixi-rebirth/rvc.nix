{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.rvc;
  system = pkgs.stdenv.hostPlatform.system;
  virtualMicPulseCommands = [
    {
      cmd = "load-module";
      args = "module-null-sink sink_name=rvc_output sink_properties=device.description=RVC-Output";
      flags = [ ];
    }
    {
      cmd = "load-module";
      args = "module-remap-source master=rvc_output.monitor source_name=rvc_mic source_properties=device.description=RVC-Microphone";
      flags = [ ];
    }
  ];
  echoCancellationModule = {
    name = "libpipewire-module-echo-cancel";
    args = {
      "library.name" = "aec/libspa-aec-webrtc";
      "monitor.mode" = true;
      "capture.props" = {
        "node.name" = "rvc_echo_cancel_capture";
        "node.description" = "RVC Echo Cancellation Capture";
      };
      "source.props" = {
        "node.name" = "rvc_echo_cancelled_input";
        "node.description" = "RVC Echo-Cancelled Input";
        "media.class" = "Audio/Source";
      };
      "sink.props" = {
        "node.name" = "rvc_echo_cancel_monitor";
        "node.description" = "RVC Echo Cancellation Monitor";
      };
    };
  };
in
{
  options.programs.rvc = {
    enable = lib.mkEnableOption "Retrieval-based Voice Conversion";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${system}.cpu-with-models;
      defaultText = lib.literalExpression "rvc-nix.packages.${system}.cpu-with-models";
      example = lib.literalExpression "rvc-nix.packages.${system}.cuda118-with-models";
      description = ''
        RVC package to install. The CPU package with pinned inference assets
        is the default; select a CUDA package explicitly when appropriate.
      '';
    };

    chinese.enable = lib.mkEnableOption "Simplified Chinese RVC interfaces";

    webui = {
      enable = lib.mkEnableOption "automatic RVC WebUI user service";

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          Default address used by rvc-web and by the optional user service.
        '';
      };

      port = lib.mkOption {
        type = lib.types.ints.between 1 65535;
        default = 7865;
        description = ''
          Starting port used by rvc-web. If it is occupied, upstream RVC tries
          the next available port.
        '';
      };
    };

    virtualMic.enable = lib.mkEnableOption ''
      the RVC PipeWire virtual output and microphone
    '';

    virtualMic.echoCancellation.enable = lib.mkEnableOption ''
      the WebRTC acoustic echo-cancelled input for speaker use
    '';
  };

  config = lib.mkIf cfg.enable {
    security.rtkit = lib.mkIf cfg.virtualMic.enable {
      enable = lib.mkDefault true;
    };

    services.pipewire = lib.mkIf cfg.virtualMic.enable {
      enable = lib.mkDefault true;
      audio.enable = lib.mkDefault true;
      alsa.enable = lib.mkDefault true;
      pulse.enable = lib.mkDefault true;
      wireplumber.enable = lib.mkDefault true;

      extraConfig.pipewire-pulse."90-rvc-virtual-mic" = {
        "pulse.cmd" = virtualMicPulseCommands;
      };

      extraConfig.pipewire."90-rvc-echo-cancellation" = lib.mkIf cfg.virtualMic.echoCancellation.enable {
        "context.modules" = [ echoCancellationModule ];
      };
    };

    environment.systemPackages = [ cfg.package ];

    environment.sessionVariables = {
      RVC_WEBUI_HOST = cfg.webui.host;
      RVC_WEBUI_PORT = toString cfg.webui.port;
    }
    // lib.optionalAttrs cfg.chinese.enable {
      RVC_UI_LANGUAGE = "zh_CN.UTF-8";
    };

    environment.etc."alsa/conf.d/60-rvc.conf" = lib.mkIf cfg.virtualMic.enable {
      mode = "0444";
      text = ''
        # Stable ALSA name for feeding the RVC PipeWire output. PipeWire
        # negotiates the audio format; no physical device is selected here.
        pcm."RVC-Output" {
          type asym
          playback.pcm {
            type pipewire
            playback_node "rvc_output"
          }
          hint { show on description "RVC-Output" }
        }

        ${lib.optionalString cfg.virtualMic.echoCancellation.enable ''
          # Input-only endpoint backed by PipeWire's WebRTC AEC. In monitor
          # mode it correlates the default microphone with the default sink's
          # monitor, so physical device names never need to be hard-coded.
          pcm."RVC-Echo-Cancelled-Input" {
            type asym
            capture.pcm {
              type pipewire
              capture_node "rvc_echo_cancelled_input"
            }
            hint { show on description "RVC-Echo-Cancelled-Input" }
          }
        ''}
      '';
    };

    systemd.user.services.pipewire-pulse.restartTriggers = lib.mkIf cfg.virtualMic.enable [
      (builtins.toJSON virtualMicPulseCommands)
    ];

    systemd.user.services.rvc-webui = lib.mkIf cfg.webui.enable {
      description = "RVC WebUI";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      environment = {
        RVC_WEBUI_HOST = cfg.webui.host;
        RVC_WEBUI_PORT = toString cfg.webui.port;
      }
      // lib.optionalAttrs cfg.chinese.enable {
        RVC_UI_LANGUAGE = "zh_CN.UTF-8";
      };
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/rvc-web --noautoopen";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
