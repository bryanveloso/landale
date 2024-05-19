/*
  Warnings:

  - A unique constraint covering the columns `[seedId,checkpointId]` on the table `results` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateIndex
CREATE UNIQUE INDEX "results_seedId_checkpointId_key" ON "results"("seedId", "checkpointId");
