import { PrismaClient } from '@prisma/client';
import { parse } from 'csv-parse';

const prisma = new PrismaClient({
  log: [
    { level: 'warn', emit: 'event' },
    { level: 'info', emit: 'event' },
    { level: 'error', emit: 'event' },
  ],
});

prisma.$on('warn', e => {
  console.log(e);
});

prisma.$on('info', e => {
  console.log(e);
});

prisma.$on('error', e => {
  console.log(e);
});

async function seedChallenges() {
  const json = await Bun.file(__dirname + '/seed/challenges.json').json();
  await prisma.challenge.createMany({
    data: json,
    skipDuplicates: true,
  });

  console.log('✅ Seeded challenges.');
}

async function seedCheckpoints() {
  const json = await Bun.file(__dirname + '/seed/checkpoints.json').json();
  await prisma.checkpoint.createMany({
    data: json,
    skipDuplicates: true,
  });

  console.log('✅ Seeded checkpoints.');
}

async function seedResults() {
  const csv = await Bun.file(__dirname + '/seed/results.csv').text();
  const rows = parse(csv, { columns: true, delimiter: ',' });

  for await (const row of rows) {
    const number = parseInt(row['Seed Number']);
    const checkpoints = Object.keys(row).filter(key => key !== 'Seed Number');

    const seed = await prisma.seed.upsert({
      where: { id: number },
      update: {},
      create: { id: number, challengeId: 1 },
    });

    for (const name of checkpoints) {
      const checkpoint = await prisma.checkpoint.findUnique({
        where: { name },
      });

      if (row[name] === '1') {
        await prisma.result.upsert({
          where: {
            seedId_checkpointId: {
              seedId: seed.id,
              checkpointId: checkpoint?.id!,
            },
          },
          update: {},
          create: {
            seedId: seed.id,
            checkpointId: checkpoint?.id!,
            result: row[name] === '1',
          },
        });
      }
    }
  }

  console.log('✅ Seeded results.');
}

async function main() {
  await seedChallenges();
  await seedCheckpoints();
  await seedResults();
}

// https://github.com/prisma/prisma/issues/21324
await main()
  .catch(e => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
    console.log('Disconnected from database.');
  });
