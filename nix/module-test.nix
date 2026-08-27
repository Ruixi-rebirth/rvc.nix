{
  nixosSystem,
  nixosModule,
  pkgs,
  cpuPackage,
  cudaPackage,
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  evalModule =
    settings:
    nixosSystem {
      inherit system;
      modules = [
        nixosModule
        {
          system.stateVersion = "26.05";
          programs.rvc = {
            enable = true;
          }
          // settings;
        }
      ];
    };

  defaults = (evalModule { }).config;
  configured =
    (evalModule {
      package = cudaPackage;
      chinese.enable = true;
      webui = {
        enable = true;
        host = "192.0.2.10";
        port = 9000;
      };
      virtualMic = {
        enable = true;
        echoCancellation.enable = true;
      };
    }).config;

  virtualCommands =
    configured.services.pipewire.extraConfig.pipewire-pulse."90-rvc-virtual-mic"."pulse.cmd";
  virtualRestartTriggers = configured.systemd.user.services.pipewire-pulse.restartTriggers;
  echoModules =
    configured.services.pipewire.extraConfig.pipewire."90-rvc-echo-cancellation"."context.modules";
  invalidLowPort = builtins.tryEval (
    builtins.deepSeq (evalModule { webui.port = 0; }).config.programs.rvc.webui.port true
  );
  invalidHighPort = builtins.tryEval (
    builtins.deepSeq (evalModule { webui.port = 65536; }).config.programs.rvc.webui.port true
  );
  generatedConfig = configured.environment.etc.pipewire.source;
in
assert defaults.programs.rvc.package == cpuPackage;
assert configured.programs.rvc.package == cudaPackage;
assert !defaults.services.pipewire.enable;
assert !defaults.services.pipewire.audio.enable;
assert !defaults.services.pipewire.alsa.enable;
assert !defaults.services.pipewire.pulse.enable;
assert !defaults.services.pipewire.wireplumber.enable;
assert !defaults.security.rtkit.enable;
assert configured.services.pipewire.enable;
assert configured.services.pipewire.audio.enable;
assert configured.services.pipewire.alsa.enable;
assert configured.services.pipewire.pulse.enable;
assert configured.services.pipewire.wireplumber.enable;
assert configured.security.rtkit.enable;
assert builtins.elem cpuPackage defaults.environment.systemPackages;
assert builtins.elem cudaPackage configured.environment.systemPackages;
assert defaults.environment.sessionVariables.RVC_UI_LANGUAGE or null == null;
assert configured.environment.sessionVariables.RVC_UI_LANGUAGE == "zh_CN.UTF-8";
assert defaults.environment.sessionVariables.RVC_WEBUI_HOST == "127.0.0.1";
assert defaults.environment.sessionVariables.RVC_WEBUI_PORT == "7865";
assert configured.environment.sessionVariables.RVC_WEBUI_HOST == "192.0.2.10";
assert configured.environment.sessionVariables.RVC_WEBUI_PORT == "9000";
assert defaults.services.pipewire.extraConfig.pipewire-pulse."90-rvc-virtual-mic" or { } == { };
assert defaults.services.pipewire.extraConfig.pipewire."90-rvc-echo-cancellation" or { } == { };
assert defaults.environment.etc."alsa/conf.d/60-rvc.conf" or { } == { };
assert defaults.systemd.user.services.rvc-webui or { } == { };
assert builtins.length virtualCommands == 2;
assert
  virtualCommands == [
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
assert virtualRestartTriggers == [ (builtins.toJSON virtualCommands) ];
assert builtins.length echoModules == 1;
assert (builtins.head echoModules).name == "libpipewire-module-echo-cancel";
assert (builtins.head echoModules).args."library.name" == "aec/libspa-aec-webrtc";
assert (builtins.head echoModules).args."monitor.mode";
assert (builtins.head echoModules).args."source.props"."node.name" == "rvc_echo_cancelled_input";
assert
  builtins.match ".*pcm\\.\"RVC-Output\".*" configured.environment.etc."alsa/conf.d/60-rvc.conf".text
  != null;
assert
  builtins.match ".*pcm\\.\"RVC-Echo-Cancelled-Input\".*"
    configured.environment.etc."alsa/conf.d/60-rvc.conf".text != null;
assert
  builtins.match ".*capture_node \"rvc_echo_cancelled_input\".*"
    configured.environment.etc."alsa/conf.d/60-rvc.conf".text != null;
assert configured.systemd.user.services.rvc-webui.after == [ "graphical-session.target" ];
assert configured.systemd.user.services.rvc-webui.partOf == [ "graphical-session.target" ];
assert configured.systemd.user.services.rvc-webui.wantedBy == [ "graphical-session.target" ];
assert
  configured.systemd.user.services.rvc-webui.serviceConfig.ExecStart
  == "${cudaPackage}/bin/rvc-web --noautoopen";
assert configured.systemd.user.services.rvc-webui.environment.RVC_WEBUI_HOST == "192.0.2.10";
assert configured.systemd.user.services.rvc-webui.environment.RVC_WEBUI_PORT == "9000";
assert configured.systemd.user.services.rvc-webui.environment.RVC_UI_LANGUAGE == "zh_CN.UTF-8";
assert !(builtins.elem 9000 configured.networking.firewall.allowedTCPPorts);
assert !invalidLowPort.success;
assert !invalidHighPort.success;
pkgs.runCommand "rvc-nixos-module-test" { nativeBuildInputs = [ pkgs.jq ]; } ''
  config=${generatedConfig}/pipewire-pulse.conf.d/90-rvc-virtual-mic.conf
  test -f "$config"
  jq --exit-status '
    (.["pulse.cmd"] | length == 2) and
    (.["pulse.cmd"][0].args | contains("sink_name=rvc_output"))
  ' "$config" >/dev/null

  echo_config=${generatedConfig}/pipewire.conf.d/90-rvc-echo-cancellation.conf
  test -f "$echo_config"
  jq --exit-status '
    (.["context.modules"] | length == 1) and
    (.["context.modules"][0].name == "libpipewire-module-echo-cancel") and
    (.["context.modules"][0].args["monitor.mode"] == true) and
    (.["context.modules"][0].args["source.props"]["node.name"] ==
      "rvc_echo_cancelled_input")
  ' "$echo_config" >/dev/null
  touch "$out"
''
