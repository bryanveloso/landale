import { Server, ServerResponse } from 'http'
import { NextApiResponse } from 'next'

import CategoryController from './category.controller';
import TwitchConteroller from './twitch.controller';

export type CustomServer = Server & {
  category: CategoryController;
  twitch: TwitchConteroller;
};

export type CustomServerResponse = ServerResponse & {
  server: CustomServer
}

export type CustomNextApiResponse = NextApiResponse & {
  server: CustomServer
}
