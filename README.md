# Landale

This is Project Landale, the overlays that are built to run [altair.tv/avalonstar](https://altair.tv/avalonstar). In the before-times this was called Synthform, and was a Twitch-centric chat-powered system. Landale aims to take this a few steps further given lessons learned during the Synthform project.

## Components

Landale is a system made up of different, interconnecting components:

### Composition of a Scene

| Layer      | Description                                                                                                                            |
|------------|----------------------------------------------------------------------------------------------------------------------------------------|
| Atmos      | This is the topmost layer in the stack. Active notifications and other front-facing overlay toys live on this layer.                   |
| Video      | The contents of this layer is handled by the ATEM Mini or other display sources within OBS.                                            |
| Asthenos   | The lower layer that sits beneath the video. It serves as a general background layer with regard to the window elements on the screen. |
| Background | This is the bottommost later in the stack. The background layer is handled by OBS, and controled with Bitfocus Companion if necessary. |

## Overlay Routes

Each major type of screen is handled by a pair of overlays: an _atmos_ (upper) and _astheno_ (lower) layer, respectively.

```
/pages
 |- /asthenos
 |- /atmos 
```