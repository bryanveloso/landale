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

// ---

type Checkpoint = {
  id: number;
  slug: string;
  trainers: string;
};

export const checkpoints: Checkpoint[] = [
  { id: 1, trainers: 'None', slug: 'LAB' },
  { id: 2, trainers: 'Rival', slug: 'RIVAL1' },
  { id: 3, trainers: 'Trainer', slug: 'FIRSTTRAINER' },
  { id: 4, trainers: 'Rival', slug: 'RIVAL2' },
  { id: 5, trainers: 'Brock', slug: 'BROCK' },
  { id: 6, trainers: 'Rival', slug: 'RIVAL3' },
  { id: 7, trainers: 'Rival', slug: 'RIVAL4' },
  { id: 8, trainers: 'Misty', slug: 'MISTY' },
  { id: 9, trainers: 'Surge', slug: 'SURGE' },
  { id: 10, trainers: 'Rival', slug: 'RIVAL5' },
  { id: 11, trainers: 'Giovanni', slug: 'ROCKETHIDEOUT' },
  { id: 12, trainers: 'Erika', slug: 'ERIKA' },
  { id: 13, trainers: 'Koga', slug: 'KOGA' },
  { id: 14, trainers: 'Rival', slug: 'RIVAL6' },
  { id: 15, trainers: 'Giovanni', slug: 'SILPHCO' },
  { id: 16, trainers: 'Sabrina', slug: 'SABRINA' },
  { id: 17, trainers: 'Blaine', slug: 'BLAINE' },
  { id: 18, trainers: 'Giovanni', slug: 'GIOVANNI' },
  { id: 19, trainers: 'Rival', slug: 'RIVAL7' },
  { id: 20, trainers: 'Lorelai', slug: 'LORELAI' },
  { id: 21, trainers: 'Bruno', slug: 'BRUNO' },
  { id: 22, trainers: 'Agatha', slug: 'AGATHA' },
  { id: 23, trainers: 'Lance', slug: 'LANCE' },
  { id: 24, trainers: 'Champ', slug: 'CHAMP' },
];
