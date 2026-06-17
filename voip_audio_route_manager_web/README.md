# voip_audio_route_manager_web

The Web implementation package of the federated plugin `voip_audio_route_manager`.

This package provides Web-specific platform integration using the browser's `navigator.mediaDevices` HTML5 API. It supports enumeration of output devices, listening for device connection changes, and mapping selected route structures.

## Usage

This package is **not intended to be used directly** by application developers. The main client package `voip_audio_route_manager` will automatically import and register this Web implementation when running in browser environments.

To install the main package, add:

```yaml
dependencies:
  voip_audio_route_manager: ^1.1.0
```

## Web Considerations

- **Secure Context Requirement**: The browser's media devices API is restricted to secure contexts (`https://` or `localhost`).
- **Permissions**: Browsers will hide actual device labels/names (returning empty descriptions) until the user grants permission to access media devices (e.g. microphone permission).
