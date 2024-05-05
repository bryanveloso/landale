import { motion } from 'framer-motion';
import { FC, useEffect, useState } from 'react';

import { Versus } from './_components/versus';

import trainer from '~/public/games/kaizo/trainer.png';
import { useKaizoAttempts } from '@/hooks/use-kaizo-attempts';
import {
  LastHitResult,
  calculateCheckpointAverage,
  findLastHitForCheckpoint,
  parseCSV,
} from '@/lib/services/landale/kaizo';

/**
 * Checkpoint: Rival One
 * Next Checkpoint: First Trainer
 */

export const Checkpoint: FC = () => {
  const { csv, status } = useKaizoAttempts();

  const [successRate, setSuccessRate] = useState<string>();
  const [lastSuccess, setLastSuccess] = useState<LastHitResult>();

  useEffect(() => {
    if (status === 'success') {
      const attempts = parseCSV(csv);
      setSuccessRate(calculateCheckpointAverage(attempts, 1));
      setLastSuccess(findLastHitForCheckpoint(attempts, 1));
    }
  }, [csv, status]);

  return (
    <>
      <Versus name="Trainer" image={trainer} />
      <motion.div className="flex items-center">
        <span className="relative rounded border-b border-shark-50/25 bg-black p-1 px-2 font-bold uppercase">
          SUCCESS RATE
        </span>
        <span className="pl-4 font-mono text-xl">{successRate}%</span>
      </motion.div>
      <motion.div className="flex items-center">
        <span className="relative rounded border-b border-shark-50/25 bg-black p-1 px-2 font-bold uppercase">
          LAST SUCCESS
        </span>
        <span className="pl-4 font-mono text-xl">
          {lastSuccess?.distance} runs ago
        </span>
      </motion.div>
    </>
  );
};
