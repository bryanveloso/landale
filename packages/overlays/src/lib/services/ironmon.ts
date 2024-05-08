enum Game {
  RubySapphire = 1,
  Emerald,
  FireRedLeafGreen,
}

export type IronmonMessage = InitMessage | SeedMessage | CheckpointMessage;

export type InitMessage = {
  type: 'init';
  metadata: {
    version: string;
    game: Game;
  };
};

export type SeedMessage = {
  type: 'seed';
  metadata: {
    count: number;
  };
};

export type CheckpointMessage = {
  type: 'checkpoint';
  metadata: {
    id: number;
    name: string;
  };
};
