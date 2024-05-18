-- CreateTable
CREATE TABLE "Challenge" (
    "id" SERIAL NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,

    CONSTRAINT "Challenge_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Seed" (
    "id" INTEGER NOT NULL,

    CONSTRAINT "Seed_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Checkpoint" (
    "id" SERIAL NOT NULL,
    "seedId" INTEGER NOT NULL,
    "name" TEXT NOT NULL,
    "reached" BOOLEAN NOT NULL,

    CONSTRAINT "Checkpoint_pkey" PRIMARY KEY ("id")
);

-- AddForeignKey
ALTER TABLE "Seed" ADD CONSTRAINT "Seed_id_fkey" FOREIGN KEY ("id") REFERENCES "Challenge"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Checkpoint" ADD CONSTRAINT "Checkpoint_id_fkey" FOREIGN KEY ("id") REFERENCES "Seed"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
