# Landale

This is Project Landale, the system built to run [twitch.tv/avalonstar](https://twitch.tv/avalonstar). In the before-times this was called Synthform, and was a Twitch-centric chat-powered overlay system. Landale aims to take this a few steps further given lessons learned during the Synthform project.

Note: While this project is licensed under the BSD 3-Clause license, I ask that you don't be a jerk and use my overlays as your own. Feel free to learn and even contribute to the embetterment of this project.

## Components

Landale is a system made up of different, interconnecting components:

* The core of Landale is the Electron app that lives in this repository. The idea behind Landale.app is to provide myself with a visual control center. One could feisably build in controls to interact with OBS or just have a place to display a customizable chat. 
* The overlays themselves live inside `/renderer/overlays` as a Next.JS project. I've chosen Next because of my familiarity with React (Synthform was also React-based).

## Acknowledgements

