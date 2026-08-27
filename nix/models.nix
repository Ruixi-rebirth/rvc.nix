{
  fetchurl,
  lib,
  linkFarm,
  runCommand,
  symlinkJoin,
  unzip,
  writeText,
}:

let
  revision = "e6d0c1a17da07c33557852f9dfa2bd44cc75737d";
  shortRevision = lib.substring 0 7 revision;
  baseUrl = "https://huggingface.co/lj1995/VoiceConversionWebUI/resolve/${revision}";

  modelMeta = {
    description = "Pinned model assets for Retrieval-based Voice Conversion";
    homepage = "https://huggingface.co/lj1995/VoiceConversionWebUI/tree/${revision}";
    # The model repository's cardData and license tag both declare MIT at the
    # pinned revision; this is not inferred from the RVC source-code license.
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };

  modelCard = fetchurl {
    name = "rvc-model-card-${shortRevision}.md";
    url = "${baseUrl}/README.md";
    hash = "sha256-Pg4V+gxcyBZ1vWmvjrRp0SinJcGnv8cfA7eHe3tlBWc=";
  };

  sourceNotice = writeText "rvc-model-source-${shortRevision}.txt" ''
    Source: https://huggingface.co/lj1995/VoiceConversionWebUI
    Immutable revision: ${revision}
    Declared license: MIT

    The accompanying MODEL_CARD.md is fetched from that exact revision. Model
    assets remain subject to the source repository's license and terms.
  '';

  documentationLinks = [
    {
      name = "share/doc/rvc-models/MODEL_CARD.md";
      path = modelCard;
    }
    {
      name = "share/doc/rvc-models/SOURCE.txt";
      path = sourceNotice;
    }
  ];

  fetchModel =
    {
      path,
      hash,
      sourcePath ? path,
    }:
    {
      name = "assets/${path}";
      path = fetchurl {
        url = "${baseUrl}/${sourcePath}";
        inherit hash;
      };
    };

  mkModelSet =
    {
      name,
      modelChecks,
      models,
    }:
    (linkFarm "rvc-${name}-${shortRevision}" ((map fetchModel models) ++ documentationLinks))
    .overrideAttrs
      (_old: {
        meta = modelMeta;
        passthru = {
          assetPaths = map (model: model.path) models;
          inherit modelChecks revision;
        };
      });

  mkCombinedModelSet =
    {
      extraModelChecks ? [ ],
      modelSets,
      name,
    }:
    symlinkJoin {
      inherit name;
      paths = modelSets;
      meta = modelMeta;
      passthru = {
        inherit revision;
        assetPaths = lib.unique (lib.concatMap (modelSet: modelSet.assetPaths) modelSets);
        modelChecks = lib.unique (
          lib.concatMap (modelSet: modelSet.modelChecks) modelSets ++ extraModelChecks
        );
      };
    };

  muteArchive = fetchurl {
    name = "rvc-mute-${shortRevision}.zip";
    url = "${baseUrl}/mute.zip";
    hash = "sha256-7pSOhSE+TtLyui+N/O6BC/0LYxMdkUUOkgu+HL0DIdA=";
  };
in
rec {
  # Required for inference and feature extraction. Keep this small so realtime
  # users do not fetch the much larger pretrained weights used for training.
  inference = mkModelSet {
    name = "inference-models";
    modelChecks = [ "hubert-rmvpe-forward" ];
    models = [
      {
        path = "hubert_base/config.json";
        hash = "sha256-A0aVB3nft/kxb6dO2EbiuKIqCO7f3FOHtz8yfLGkp88=";
      }
      {
        path = "hubert_base/preprocessor_config.json";
        hash = "sha256-fBl2poD7esx1fNNvsI7vh4+jbHC0ydLVld+cYIu7vw4=";
      }
      {
        path = "hubert_base/pytorch_model.bin";
        hash = "sha256-zIwg9LkKUgdXJgGXo/8lBXBaetvSCtnuqk4amzhELvU=";
      }
      {
        path = "rmvpe/rmvpe.pt";
        sourcePath = "rmvpe.pt";
        hash = "sha256-bWIhX0MG48ongkYYhgcgnwmvPcd+1CMu/dBpeYxOwZM=";
      }
    ];
  };

  # The five source-separation checkpoints listed by the pinned upstream
  # WebUI. Their YAML configurations are part of the RVC source tree and the
  # launcher links those alongside these weights at runtime.
  pymss = mkModelSet {
    name = "pymss-models";
    modelChecks = [ ];
    models = [
      {
        path = "pymss_weights/dereverb_mel_band_roformer_anvuew_sdr_19.1729.ckpt";
        hash = "sha256-T8v8nUGav9HweiT5INg/gNUXJ8o83j6dhMmTmEGNNfM=";
      }
      {
        path = "pymss_weights/dereverb_mel_band_roformer_less_aggressive_anvuew_sdr_18.8050.ckpt";
        hash = "sha256-k5lwHaM9F54yikNuiC/ix5ri8Rij1JYD28chC/60KOo=";
      }
      {
        path = "pymss_weights/model_bs_roformer_ep_317_sdr_12.9755.ckpt";
        hash = "sha256-Te7TFxm3uSGVUwqdDobqHI1cSqnw4t2WfB8FQZ6/ltU=";
      }
      {
        path = "pymss_weights/model_bs_roformer_ep_368_sdr_12.9628.ckpt";
        hash = "sha256-l8nhARkk/2R9FHtHRjjBYbgFhv1bnoP6tZy7twAUv2I=";
      }
      {
        path = "pymss_weights/model_mel_band_roformer_karaoke_aufr33_viperx_sdr_10.1956.ckpt";
        hash = "sha256-ZgPFbhboXw6reNRx5DNBt4ndxlQjC5vMgaJajRRXqME=";
      }
    ];
  };

  # RVC v1 pretrained generator/discriminator weights, with and without F0 guidance,
  # for every sample rate supported by the v1 WebUI.
  pretrained-v1 = mkModelSet {
    name = "pretrained-v1";
    modelChecks = [ ];
    models = [
      {
        path = "pretrained/D32k.pth";
        hash = "sha256-KrIGRYKUYP2tDTxEJU8atTwyyuUMIqZskmrlqjCr2m8=";
      }
      {
        path = "pretrained/D40k.pth";
        hash = "sha256-VH9m27zZAjuQUe0kTRKrBDuopOhUsVTMKHYax8ACkJs=";
      }
      {
        path = "pretrained/D48k.pth";
        hash = "sha256-jMAT+mDtnD+QL1vZn0jH47k1LXY9TTzWvCQcN7C/2a0=";
      }
      {
        path = "pretrained/f0D32k.pth";
        hash = "sha256-KU2zCHI24sdSYNYXkFZ5HJIxJF2vXQSFVF2eVMQFfHc=";
      }
      {
        path = "pretrained/f0D40k.pth";
        hash = "sha256-fU9aRBWUtHDWdXmViy/UxrmShS3tKP+ecu2merzr5CM=";
      }
      {
        path = "pretrained/f0D48k.pth";
        hash = "sha256-G4TIvzR60eU5yELo8qTDbs2ef7I8FgQRieSHfpsHklw=";
      }
      {
        path = "pretrained/f0G32k.pth";
        hash = "sha256-KF9SS/SLtpLHate9C8ZUwSvZ5e3reE3d9/YaeJpghXQ=";
      }
      {
        path = "pretrained/f0G40k.pth";
        hash = "sha256-kRVlSu7xmV9908b8QUC+u+8MqXYL7XmBBaI4CjQpmDE=";
      }
      {
        path = "pretrained/f0G48k.pth";
        hash = "sha256-eLycqyfjS8/BlPkwKTdNhx2LPmY93t6jKpcJ6JTMj+g=";
      }
      {
        path = "pretrained/G32k.pth";
        hash = "sha256-gYF2Rc3n7S4tg/I++IPzPdpWSSS0l+hNeSdDkS7KTCM=";
      }
      {
        path = "pretrained/G40k.pth";
        hash = "sha256-5ChXO9oRJLCuCuhD/Y3N7WAn05k0RHkLPpsBAJOLIRM=";
      }
      {
        path = "pretrained/G48k.pth";
        hash = "sha256-OGKmfqYxPo/+/AXO5r7mVu8+CJRC6ez0pmGNYHIfPpU=";
      }
    ];
  };

  # RVC v2 pretrained generator/discriminator weights, with and without F0 guidance,
  # for every sample rate supported by the v2 WebUI.
  pretrained-v2 = mkModelSet {
    name = "pretrained-v2";
    modelChecks = [ ];
    models = [
      {
        path = "pretrained_v2/D32k.pth";
        hash = "sha256-2AQzeMxmGQg9OF9aBF3gm4P7O/jeRcQzyoY7cXI6w8o=";
      }
      {
        path = "pretrained_v2/D40k.pth";
        hash = "sha256-RxN46JTnGR+JqU7agojFlHsWu+CxDD8fF+/beh2ZgkI=";
      }
      {
        path = "pretrained_v2/D48k.pth";
        hash = "sha256-2wEJSpPAmGiieOA9r+i7eBv8waW6jfFoyUi/kWjITYI=";
      }
      {
        path = "pretrained_v2/f0D32k.pth";
        hash = "sha256-vXE053k2dMhUdNUUXS2YLjxdgST8e7bCD3EO1lgI+oo=";
      }
      {
        path = "pretrained_v2/f0D40k.pth";
        hash = "sha256-a2qwkecIAbKOP0HzNfL8Xz81x1s5riYo1BlkTsKw+gk=";
      }
      {
        path = "pretrained_v2/f0D48k.pth";
        hash = "sha256-Imm3PHpM802gmuqZJ02r+Zst24pCy/sGX7PAqpovx0g=";
      }
      {
        path = "pretrained_v2/f0G32k.pth";
        hash = "sha256-IzJhEpe42Ix0Nt6PF+9fB6IRk1PpYs2TzaWAbVmhEz0=";
      }
      {
        path = "pretrained_v2/f0G40k.pth";
        hash = "sha256-OyxEA154LEsU3cC+3p4vSnJNAlzQc/c21PQ3CEU638s=";
      }
      {
        path = "pretrained_v2/f0G48k.pth";
        hash = "sha256-tdUfWJzDYy1OrjajFbQXk5dpUELtwB0VMS4b3cK3ZKQ=";
      }
      {
        path = "pretrained_v2/G32k.pth";
        hash = "sha256-hpsmpH91Fo1hJvZKw55t5SRwF6hljP1orKYA9zI++58=";
      }
      {
        path = "pretrained_v2/G40k.pth";
        hash = "sha256-o4Q9p/3jPbHasXYUbHDWwt8G6v6UV/TjqhACTpxqS2k=";
      }
      {
        path = "pretrained_v2/G48k.pth";
        hash = "sha256-LisVgaQ20Hp2sQudOHZfZKoCg23GXH3uHOQUDBHqFYs=";
      }
    ];
  };

  # The archive contains a top-level `mute` directory. Extracting it below
  # `logs` produces exactly the paths referenced by webui.py: logs/mute/...
  mute =
    runCommand "rvc-training-mute-${shortRevision}"
      {
        nativeBuildInputs = [ unzip ];
        meta = modelMeta;
        passthru = {
          archive = muteArchive;
          inherit revision;
          assetPaths = [ ];
          modelChecks = [ ];
        };
      }
      ''
        mkdir -p "$out/logs"
        unzip -qq ${muteArchive} -d "$out/logs"

        mkdir -p "$out/share/doc/rvc-models"
        ln -s ${modelCard} "$out/share/doc/rvc-models/MODEL_CARD.md"
        ln -s ${sourceNotice} "$out/share/doc/rvc-models/SOURCE.txt"

        test -f "$out/logs/mute/0_gt_wavs/mute32k.wav"
        test -f "$out/logs/mute/0_gt_wavs/mute40k.wav"
        test -f "$out/logs/mute/0_gt_wavs/mute48k.wav"
        test -f "$out/logs/mute/2a_f0/mute.wav.npy"
        test -f "$out/logs/mute/2b-f0nsf/mute.wav.npy"
        test -f "$out/logs/mute/3_feature256/mute.npy"
        test -f "$out/logs/mute/3_feature768/mute.npy"
        test "$(find "$out/logs/mute" -type f | wc -l)" -eq 11
        grep -F 'license: mit' "$out/share/doc/rvc-models/MODEL_CARD.md"
        grep -F '${revision}' "$out/share/doc/rvc-models/SOURCE.txt"
      '';

  # symlinkJoin merges the component directory trees without duplicating their
  # large files in the Nix store.
  training = mkCombinedModelSet {
    name = "rvc-training-models-${shortRevision}";
    modelSets = [
      pretrained-v1
      pretrained-v2
      mute
    ];
  };

  all = mkCombinedModelSet {
    name = "rvc-all-models-${shortRevision}";
    modelSets = [
      inference
      training
      pymss
    ];
    # This check needs both RMVPE from inference and a voice checkpoint from
    # training, so it belongs to their combined set rather than either input.
    extraModelChecks = [ "realtime-synth-forward" ];
  };
}
