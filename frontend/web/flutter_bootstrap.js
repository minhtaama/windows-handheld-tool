{{flutter_js}}
{{flutter_build_config}}

// Force the engine to load CanvasKit from the local build output (canvaskit/) instead of
// the www.gstatic.com CDN. Without this the panel stays blank when the device is offline.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
