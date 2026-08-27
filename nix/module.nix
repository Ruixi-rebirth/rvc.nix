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
  virtualMicPulseConfig = {
    # PipeWire's Pulse compatibility layer defaults unspecified capture
    # fragments to two seconds. Use one graph quantum for interactive voice
    # applications; clients that request their own fragment size are unchanged.
    "pulse.properties" = {
      "pulse.default.frag" = "1024/48000";
    };
    "pulse.cmd" = virtualMicPulseCommands;
  };
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
      default = self.packages.${system}.default;
      defaultText = lib.literalExpression "rvc-nix.packages.${system}.default";
      example = lib.literalExpression "rvc-nix.packages.${system}.cuda118";
      description = ''
        RVC package used by every module feature. It is installed system-wide,
        and the optional WebUI service starts rvc-web from this same package.
        The default is the complete CPU inference package.
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

      extraConfig.pipewire-pulse."90-rvc-virtual-mic" = virtualMicPulseConfig;

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
      (builtins.toJSON virtualMicPulseConfig)
    ];

    systemd.user.services.pipewire.restartTriggers = lib.mkIf cfg.virtualMic.enable [
      (builtins.toJSON (lib.optional cfg.virtualMic.echoCancellation.enable echoCancellationModule))
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
