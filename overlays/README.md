# Landale

### Composition of a Scene

| Layer      | Description                                                 |
| ---------- | ----------------------------------------------------------- |
| Atmos      | This is the topmost layer in the stack. Active              |
|            | notifications and other front-facing overlay toys live      |
|            | on this layer.                                              |
| Video      | The contents of this layer is handled by the ATEM Mini or   |
|            | other display sources within OBS.                           |
| Astheno    | The lower layer that sits beneath the video. It serves as a |
|            | general background layer with regard to the window          |
|            | elements on the screen.                                     |
| Background | This is the bottommost later in the stack. The background   |
|            | layer is handled by OBS, and controled with Bitfocus        |
|            | Companion if necessary.                                     |

## Overlay Routes

Each major type of screen is handled by a pair of overlays: an _atmos_ and _astheno_ layer, respectively.
