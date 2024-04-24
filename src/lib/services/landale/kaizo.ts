export interface Attempts {
  id: string;
  checkpoints: number[];
}

export interface LastHitResult {}

export const checkpoints = [
  { 0: { id: 'rival-1', name: 'Lab', detailed: 'Past Lab' } },
  {
    1: {
      id: 'first-trainer',
      name: 'First Trainer',
      detailed: 'Past First Trainer',
    },
  },
  { 2: { id: 'rival-2', name: 'Rival 2', detailed: 'Past Rival 2' } },
  { 3: { id: 'brock', name: 'Brock', detailed: 'Past Brock' } },
  { 4: { id: 'rival-3', name: 'Rival 3', detailed: 'Past Rival 3' } },
  { 5: { id: 'misty', name: 'Misty', detailed: 'Past Misty' } },
] as { [key: number]: { id: string; name: string; detailed: string } }[];

export const parseCSV = (csv: string): Attempts[] => {
  const lines = csv.trim().split('\n');
  const headers = lines[0].split(',').slice(1); // Skip the first column, assuming it's "ID"

  const attempts: Attempts[] = [];

  for (let i = 1; i < lines.length; i++) {
    const values = lines[i].split(',');
    const id = values[0];
    const checkpoints = values.slice(1).map(Number);
    attempts.push({ id, checkpoints });
  }

  return attempts;
};

export const calculatePersonalBest = (
  attempts: Attempts[],
  checkpoints: string[]
): Record<string, string> => {
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

  distance = mostRecentRunIndex - lastHitIndex - 1;

  return {
    mostRecentRunIndex,
    lastHitIndex,
    distance,
  };
};
