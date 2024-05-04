enum Game {
  RubySapphire = 1,
  Emerald,
  FireRedLeafGreen,
}

export type BizhawkMessage = {
  type: 'checkpoint' | 'init' | 'seed';
  metadata: SeedMetadata | CheckpointMetadata;
};

export type InitializeMetadata = {
  version: string;
  game: Game;
};

export type CheckpointMetadata = Checkpoint;

export type SeedMetadata = {
  number: number;
};

export type Checkpoint = {
  id: string;
  name: string;
};

export const checkpoints: Checkpoint[] = [
  { id: 'lab', name: 'Lab' },
  { id: 'rival-1', name: 'Rival 1' },
  { id: 'first-trainer', name: 'First Trainer' },
  { id: 'rival-2', name: 'Rival 2' },
  { id: 'brock', name: 'Brock' },
  { id: 'rival-3', name: 'Rival 3' },
  { id: 'rival-4', name: 'Rival 4' },
  { id: 'misty', name: 'Misty' },
  { id: 'surge', name: 'Surge' },
  { id: 'rival-5', name: 'Rival 5' },
  { id: 'rocket-hideout', name: 'Rocket Hideout' },
  { id: 'erika', name: 'Erika' },
  { id: 'koga', name: 'Koga' },
  { id: 'rival-6', name: 'Rival 6' },
  { id: 'silph-co', name: 'Silph Co.' },
  { id: 'sabrina', name: 'Sabrina' },
  { id: 'blaine', name: 'Blaine' },
  { id: 'giovanni', name: 'Giovanni' },
  { id: 'rival-7', name: 'Rival 7' },
  { id: 'lorelai', name: 'Lorelai' },
  { id: 'bruno', name: 'Bruno' },
  { id: 'agatha', name: 'Agatha' },
  { id: 'lance', name: 'Lance' },
  { id: 'champ', name: 'Champ' },
];

export interface Attempts {
  id: string;
  checkpoints: number[];
}

export const parseCSV = (csv: string): Attempts[] => {
  const lines = csv.trim().split('\n');
  const headers = lines[0].split(',').slice(1);

  const attempts: Attempts[] = [];

  for (let i = 1; i < lines.length; i++) {
    const values = lines[i].split(',');
    const id = values[0];
    const checkpoints = values.slice(1).map(Number);
    attempts.push({ id, checkpoints });
  }

  return attempts;
};

export const extractHeaders = (csv: string): string[] => {
  const lines = csv.trim().split('\n');
  return lines[0].split(',').slice(1);
};

export type PersonalBest = {
  id: string;
  checkpoint: string;
};

export const calculatePersonalBest = (
  attempts: Attempts[],
  checkpoints: string[]
): PersonalBest => {
  let id = '';
  let maxIndex = -1;

  for (const attempt of attempts) {
    const lastIndex = attempt.checkpoints.lastIndexOf(1);
    if (lastIndex > maxIndex) {
      maxIndex = lastIndex;
      id = attempt.id;
    }
  }

  const checkpoint = checkpoints[maxIndex];
  return { id, checkpoint };
};

export const calculateCheckpointAverage = (
  attempts: Attempts[],
  index: number
): string => {
  let count = 0;
  const total = attempts.length;

  attempts.forEach(attempt => {
    if (attempt.checkpoints[index] === 1) {
      count += 1;
    }
  });

  const rate = (count / total) * 100;
  return rate.toFixed(2);
};

export interface LastHitResult {
  mostRecentRunIndex: number;
  lastHitIndex: number;
  distance: number;
}

export const findLastHitForCheckpoint = (
  attempts: Attempts[],
  index: number
): LastHitResult => {
  let distance = 0;
  let lastHitIndex = -1;
  const mostRecentRunIndex = attempts.length - 1;

  for (let i = mostRecentRunIndex; i >= 0; i--) {
    if (attempts[i].checkpoints[index] === 1) {
      lastHitIndex = i;
      break;
    }
  }

  distance = mostRecentRunIndex - lastHitIndex;

  return {
    mostRecentRunIndex,
    lastHitIndex,
    distance,
  };
};
