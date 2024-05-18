/*
  Warnings:

  - You are about to drop the `Challenge` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `Checkpoint` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `Seed` table. If the table is not empty, all the data it contains will be lost.

*/
-- DropForeignKey
ALTER TABLE "Checkpoint" DROP CONSTRAINT "Checkpoint_id_fkey";

-- DropForeignKey
ALTER TABLE "Seed" DROP CONSTRAINT "Seed_id_fkey";

-- DropTable
DROP TABLE "Challenge";

-- DropTable
DROP TABLE "Checkpoint";

-- DropTable
DROP TABLE "Seed";

-- CreateTable
CREATE TABLE "challenges" (
    "id" SERIAL NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,

    CONSTRAINT "challenges_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "seeds" (
    "id" INTEGER NOT NULL,

    CONSTRAINT "seeds_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "checkpoints" (
    "id" SERIAL NOT NULL,
    "seedId" INTEGER NOT NULL,
    "name" TEXT NOT NULL,
    "reached" BOOLEAN NOT NULL,

    CONSTRAINT "checkpoints_pkey" PRIMARY KEY ("id")
);

-- AddForeignKey
ALTER TABLE "seeds" ADD CONSTRAINT "seeds_id_fkey" FOREIGN KEY ("id") REFERENCES "challenges"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "checkpoints" ADD CONSTRAINT "checkpoints_id_fkey" FOREIGN KEY ("id") REFERENCES "seeds"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
