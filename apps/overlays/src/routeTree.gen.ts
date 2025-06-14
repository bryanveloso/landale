/* eslint-disable */

// @ts-nocheck

// noinspection JSUnusedGlobalSymbols

// This file was automatically generated by TanStack Router.
// You should NOT make any changes in this file as it will be overwritten.
// Additionally, you should also exclude this file from your linter and/or formatter to prevent it from being checked or modified.

// Import Routes

import { Route as rootRoute } from './routes/__root'
import { Route as NowPlayingImport } from './routes/now-playing'
import { Route as IndexImport } from './routes/index'
import { Route as widgetStatusTextImport } from './routes/(widget)/status-text'
import { Route as widgetStatusBarImport } from './routes/(widget)/status-bar'
import { Route as widgetOmnywidgetImport } from './routes/(widget)/omnywidget'
import { Route as widgetAlertsImport } from './routes/(widget)/alerts'
import { Route as fullSpeedrunningImport } from './routes/(full)/speedrunning'
import { Route as fullIronmonImport } from './routes/(full)/ironmon'
import { Route as fullFoundationImport } from './routes/(full)/foundation'
import { Route as fullFlyingToastersImport } from './routes/(full)/flying-toasters'
import { Route as fullEmoterainImport } from './routes/(full)/emoterain'

// Create/Update Routes

const NowPlayingRoute = NowPlayingImport.update({
  id: '/now-playing',
  path: '/now-playing',
  getParentRoute: () => rootRoute
} as any)

const IndexRoute = IndexImport.update({
  id: '/',
  path: '/',
  getParentRoute: () => rootRoute
} as any)

const widgetStatusTextRoute = widgetStatusTextImport.update({
  id: '/(widget)/status-text',
  path: '/status-text',
  getParentRoute: () => rootRoute
} as any)

const widgetStatusBarRoute = widgetStatusBarImport.update({
  id: '/(widget)/status-bar',
  path: '/status-bar',
  getParentRoute: () => rootRoute
} as any)

const widgetOmnywidgetRoute = widgetOmnywidgetImport.update({
  id: '/(widget)/omnywidget',
  path: '/omnywidget',
  getParentRoute: () => rootRoute
} as any)

const widgetAlertsRoute = widgetAlertsImport.update({
  id: '/(widget)/alerts',
  path: '/alerts',
  getParentRoute: () => rootRoute
} as any)

const fullSpeedrunningRoute = fullSpeedrunningImport.update({
  id: '/(full)/speedrunning',
  path: '/speedrunning',
  getParentRoute: () => rootRoute
} as any)

const fullIronmonRoute = fullIronmonImport.update({
  id: '/(full)/ironmon',
  path: '/ironmon',
  getParentRoute: () => rootRoute
} as any)

const fullFoundationRoute = fullFoundationImport.update({
  id: '/(full)/foundation',
  path: '/foundation',
  getParentRoute: () => rootRoute
} as any)

const fullFlyingToastersRoute = fullFlyingToastersImport.update({
  id: '/(full)/flying-toasters',
  path: '/flying-toasters',
  getParentRoute: () => rootRoute
} as any)

const fullEmoterainRoute = fullEmoterainImport.update({
  id: '/(full)/emoterain',
  path: '/emoterain',
  getParentRoute: () => rootRoute
} as any)

// Populate the FileRoutesByPath interface

declare module '@tanstack/react-router' {
  interface FileRoutesByPath {
    '/': {
      id: '/'
      path: '/'
      fullPath: '/'
      preLoaderRoute: typeof IndexImport
      parentRoute: typeof rootRoute
    }
    '/now-playing': {
      id: '/now-playing'
      path: '/now-playing'
      fullPath: '/now-playing'
      preLoaderRoute: typeof NowPlayingImport
      parentRoute: typeof rootRoute
    }
    '/(full)/emoterain': {
      id: '/(full)/emoterain'
      path: '/emoterain'
      fullPath: '/emoterain'
      preLoaderRoute: typeof fullEmoterainImport
      parentRoute: typeof rootRoute
    }
    '/(full)/flying-toasters': {
      id: '/(full)/flying-toasters'
      path: '/flying-toasters'
      fullPath: '/flying-toasters'
      preLoaderRoute: typeof fullFlyingToastersImport
      parentRoute: typeof rootRoute
    }
    '/(full)/foundation': {
      id: '/(full)/foundation'
      path: '/foundation'
      fullPath: '/foundation'
      preLoaderRoute: typeof fullFoundationImport
      parentRoute: typeof rootRoute
    }
    '/(full)/ironmon': {
      id: '/(full)/ironmon'
      path: '/ironmon'
      fullPath: '/ironmon'
      preLoaderRoute: typeof fullIronmonImport
      parentRoute: typeof rootRoute
    }
    '/(full)/speedrunning': {
      id: '/(full)/speedrunning'
      path: '/speedrunning'
      fullPath: '/speedrunning'
      preLoaderRoute: typeof fullSpeedrunningImport
      parentRoute: typeof rootRoute
    }
    '/(widget)/alerts': {
      id: '/(widget)/alerts'
      path: '/alerts'
      fullPath: '/alerts'
      preLoaderRoute: typeof widgetAlertsImport
      parentRoute: typeof rootRoute
    }
    '/(widget)/omnywidget': {
      id: '/(widget)/omnywidget'
      path: '/omnywidget'
      fullPath: '/omnywidget'
      preLoaderRoute: typeof widgetOmnywidgetImport
      parentRoute: typeof rootRoute
    }
    '/(widget)/status-bar': {
      id: '/(widget)/status-bar'
      path: '/status-bar'
      fullPath: '/status-bar'
      preLoaderRoute: typeof widgetStatusBarImport
      parentRoute: typeof rootRoute
    }
    '/(widget)/status-text': {
      id: '/(widget)/status-text'
      path: '/status-text'
      fullPath: '/status-text'
      preLoaderRoute: typeof widgetStatusTextImport
      parentRoute: typeof rootRoute
    }
  }
}

// Create and export the route tree

export interface FileRoutesByFullPath {
  '/': typeof IndexRoute
  '/now-playing': typeof NowPlayingRoute
  '/emoterain': typeof fullEmoterainRoute
  '/flying-toasters': typeof fullFlyingToastersRoute
  '/foundation': typeof fullFoundationRoute
  '/ironmon': typeof fullIronmonRoute
  '/speedrunning': typeof fullSpeedrunningRoute
  '/alerts': typeof widgetAlertsRoute
  '/omnywidget': typeof widgetOmnywidgetRoute
  '/status-bar': typeof widgetStatusBarRoute
  '/status-text': typeof widgetStatusTextRoute
}

export interface FileRoutesByTo {
  '/': typeof IndexRoute
  '/now-playing': typeof NowPlayingRoute
  '/emoterain': typeof fullEmoterainRoute
  '/flying-toasters': typeof fullFlyingToastersRoute
  '/foundation': typeof fullFoundationRoute
  '/ironmon': typeof fullIronmonRoute
  '/speedrunning': typeof fullSpeedrunningRoute
  '/alerts': typeof widgetAlertsRoute
  '/omnywidget': typeof widgetOmnywidgetRoute
  '/status-bar': typeof widgetStatusBarRoute
  '/status-text': typeof widgetStatusTextRoute
}

export interface FileRoutesById {
  __root__: typeof rootRoute
  '/': typeof IndexRoute
  '/now-playing': typeof NowPlayingRoute
  '/(full)/emoterain': typeof fullEmoterainRoute
  '/(full)/flying-toasters': typeof fullFlyingToastersRoute
  '/(full)/foundation': typeof fullFoundationRoute
  '/(full)/ironmon': typeof fullIronmonRoute
  '/(full)/speedrunning': typeof fullSpeedrunningRoute
  '/(widget)/alerts': typeof widgetAlertsRoute
  '/(widget)/omnywidget': typeof widgetOmnywidgetRoute
  '/(widget)/status-bar': typeof widgetStatusBarRoute
  '/(widget)/status-text': typeof widgetStatusTextRoute
}

export interface FileRouteTypes {
  fileRoutesByFullPath: FileRoutesByFullPath
  fullPaths:
    | '/'
    | '/now-playing'
    | '/emoterain'
    | '/flying-toasters'
    | '/foundation'
    | '/ironmon'
    | '/speedrunning'
    | '/alerts'
    | '/omnywidget'
    | '/status-bar'
    | '/status-text'
  fileRoutesByTo: FileRoutesByTo
  to:
    | '/'
    | '/now-playing'
    | '/emoterain'
    | '/flying-toasters'
    | '/foundation'
    | '/ironmon'
    | '/speedrunning'
    | '/alerts'
    | '/omnywidget'
    | '/status-bar'
    | '/status-text'
  id:
    | '__root__'
    | '/'
    | '/now-playing'
    | '/(full)/emoterain'
    | '/(full)/flying-toasters'
    | '/(full)/foundation'
    | '/(full)/ironmon'
    | '/(full)/speedrunning'
    | '/(widget)/alerts'
    | '/(widget)/omnywidget'
    | '/(widget)/status-bar'
    | '/(widget)/status-text'
  fileRoutesById: FileRoutesById
}

export interface RootRouteChildren {
  IndexRoute: typeof IndexRoute
  NowPlayingRoute: typeof NowPlayingRoute
  fullEmoterainRoute: typeof fullEmoterainRoute
  fullFlyingToastersRoute: typeof fullFlyingToastersRoute
  fullFoundationRoute: typeof fullFoundationRoute
  fullIronmonRoute: typeof fullIronmonRoute
  fullSpeedrunningRoute: typeof fullSpeedrunningRoute
  widgetAlertsRoute: typeof widgetAlertsRoute
  widgetOmnywidgetRoute: typeof widgetOmnywidgetRoute
  widgetStatusBarRoute: typeof widgetStatusBarRoute
  widgetStatusTextRoute: typeof widgetStatusTextRoute
}

const rootRouteChildren: RootRouteChildren = {
  IndexRoute: IndexRoute,
  NowPlayingRoute: NowPlayingRoute,
  fullEmoterainRoute: fullEmoterainRoute,
  fullFlyingToastersRoute: fullFlyingToastersRoute,
  fullFoundationRoute: fullFoundationRoute,
  fullIronmonRoute: fullIronmonRoute,
  fullSpeedrunningRoute: fullSpeedrunningRoute,
  widgetAlertsRoute: widgetAlertsRoute,
  widgetOmnywidgetRoute: widgetOmnywidgetRoute,
  widgetStatusBarRoute: widgetStatusBarRoute,
  widgetStatusTextRoute: widgetStatusTextRoute
}

export const routeTree = rootRoute._addFileChildren(rootRouteChildren)._addFileTypes<FileRouteTypes>()

/* ROUTE_MANIFEST_START
{
  "routes": {
    "__root__": {
      "filePath": "__root.tsx",
      "children": [
        "/",
        "/now-playing",
        "/(full)/emoterain",
        "/(full)/flying-toasters",
        "/(full)/foundation",
        "/(full)/ironmon",
        "/(full)/speedrunning",
        "/(widget)/alerts",
        "/(widget)/omnywidget",
        "/(widget)/status-bar",
        "/(widget)/status-text"
      ]
    },
    "/": {
      "filePath": "index.tsx"
    },
    "/now-playing": {
      "filePath": "now-playing.tsx"
    },
    "/(full)/emoterain": {
      "filePath": "(full)/emoterain.tsx"
    },
    "/(full)/flying-toasters": {
      "filePath": "(full)/flying-toasters.tsx"
    },
    "/(full)/foundation": {
      "filePath": "(full)/foundation.tsx"
    },
    "/(full)/ironmon": {
      "filePath": "(full)/ironmon.tsx"
    },
    "/(full)/speedrunning": {
      "filePath": "(full)/speedrunning.tsx"
    },
    "/(widget)/alerts": {
      "filePath": "(widget)/alerts.tsx"
    },
    "/(widget)/omnywidget": {
      "filePath": "(widget)/omnywidget.tsx"
    },
    "/(widget)/status-bar": {
      "filePath": "(widget)/status-bar.tsx"
    },
    "/(widget)/status-text": {
      "filePath": "(widget)/status-text.tsx"
    }
  }
}
ROUTE_MANIFEST_END */
