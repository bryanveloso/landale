# Landale Overlay System

This is the **Landale Overlay System**, the continuing culmination of my efforts over the past decade to create an overlay system [for my Twitch channel](https://twitch.tv/avalonstar). It is a series of components and tools that are used in conjunction with [OBS Studio](https://obsproject.com) to support the games I play and the content I create. This is not meant to be a general-purpose overlay system, as it is highly specialized for my needs, but it's public so that you can see how I've built it.

## Features

TBD.

## Design Philosophy

The philosophy behind **my brand of overlay design** has always been:

1. **Every element on an overlay should appear as a part of a greater whole.** It should not feel like a collection of disparate elements.

- Satisfying broadcast design is about cohesion and a sense of space.
  - Most elements in my designs are visually anchored, in one way or another, to a side of the screen. This anchoring makes the appearance and disappearance of elements feel like they have an origin point.
  - Elements follow a base-12 system, meaning that they are either spaced or sized in multiples of 12 pixels.
  - I purposefully create slight overlaps between elements to create a sense of depth.
- Alert design has been and still is based on the concept of each alert being designed in a vacuum. While alerts designed this way can share a similar aesthetic, they feel separate from the rest of the experience. This denies the end-user guidance on where to place these elements, leading to a very disjointed experience where anything can appear out of nowhere at any time.

2. **Browser sources are a layer of the canvas stack like any other source.** Design and build with that in mind.

- Browser sources are stacked around other "immutable" sources, mainly video sources. Browser sources further down the stack serve as buckets for the aforementioned immutable sources, with ones higher in the stack serving as adornment, as a mask, or as the layer that displays alerts.

3. **Do as much as possible with a browser source.** The less reliance the system has on other sources, such as images and (more importantly) image masks, the better.

- This is mainly a personal preference, as it is much faster for me to make changes to styling than to create and export a new image asset.
- When I worked for Twitch, I hosted my overlays online so they could be used while away from home with minimal setup.

## History

### Why Landale?

**Landale** is the name of the ship from the Sega Genesis-era RPG Phantasy Star IV. It's also the last name of the titular character from the original Phantasy Star, Alis Landale.

## Installation

The LOS takes advantage of a lot of the baked-in functionality of the [Bun](https://bun.sh) JavaScript runtime.

To install dependencies:

```bash
bun install
```

To run:

```bash
bun run index.ts
```
