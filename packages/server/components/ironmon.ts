import prisma from 'database';

const handleCheckpoint = async (message: any) => {
  const {
    metadata: { id },
  } = message;

  // If a checkpoint has been cleared (id > 0), save the result.
  if (id > 0) {
    await prisma.result.upsert({
      where: {
        seedId_checkpointId: { checkpointId: id, seedId: message.seed },
      },
      update: {},
      create: { checkpointId: id, seedId: message.seed, result: true },
    });
  }

  // Include information about the upcoming checkpoint.
  const info = await prisma.checkpoint.findUnique({
    where: { id: id + 1 },
    select: { trainer: true },
  });

  // Calculate the clear rate for the upcoming checkpoint.
  const clearCount = await prisma.result.count({
    where: { checkpointId: id + 1 },
  });
  const seedCount = await prisma.seed.count();
  const factor = 10 ** 2;
  const clearRate =
    Math.round((clearCount / seedCount) * 100 * factor) / factor;

  // Calculate when the last seed that cleared the upcoming checkpoint was.
  const lastCleared = await prisma.result.findFirst({
    where: { checkpointId: id + 1 },
    orderBy: { seedId: 'desc' },
    select: { seedId: true },
  });

  return {
    next: {
      ...info,
      clearRate,
      lastCleared: lastCleared?.seedId || null,
    },
  };
};

const handleSeed = async (message: any) => {
  const {
    metadata: { count },
  } = message;

  // Create a new seed in the database.
  await prisma.seed.upsert({
    where: { id: count },
    update: {},
    create: { challengeId: 1, id: count },
  });
};

export const handleMessage = async (message: any) => {
  const payload = { source: 'tcp', ...message };

  // Handle the message based on its type,
  // calculating any derived data if necessary.
  let derived = {};
  switch (message.type) {
    case 'seed':
      // No derived data to calculate for seeds.
      await handleSeed(message);
      break;
    case 'checkpoint':
      derived = await handleCheckpoint(message);
      break;
    default:
      break;
  }

  // Merged our derived data with the original payload.
  payload.metadata = { ...payload.metadata, ...derived };

  return payload;
};
